# FantaCalcio365

App Android nativa per pronostici gratuiti sulla Serie A italiana. Nessuna puntata,
nessun premio in denaro: solo punti, classifica generale cumulativa e gruppi privati
con gli amici.

Backend Supabase (PostgreSQL + RLS + Edge Functions), provider dati API-Football,
client Android in Kotlin con Jetpack Compose (MVVM). Tutta la logica di punteggio,
validazione e blocco dei pronostici vive **sul server**: l'app non calcola nulla.

## Come si guadagnano i punti

Prevedi il risultato del **primo tempo** e i **soli gol del secondo tempo**.
Se entrambi sono esatti: 4 + 6 + 10 bonus = **20 punti**. Solo 2T esatto = 6 punti.
Scegli **4 giocatori** (almeno 1 di casa, 1 ospite) e dichiara chi segna: ogni rete
di un marcatore dichiarato vale **5-15 punti** moltiplicati per le reti.
Portieri e difensori prendono un bonus se la loro squadra non subisce gol
(fino a 10 punti per i portieri). Indovina **primo sostituto** o **primo ammonito**: 2 punti ciascuno.

**Esempi:**
- Pronostichi 1T 1-0 e 2T 1-1, escono così → **20 punti**
- 1T esatto (1-0) ma 2T sbagliato → **0 punti** (il 1T da solo non vale)
- Dichiaro Osimhen marcatore (+10), segna doppietta → **20 punti**

## Stato di avanzamento

### ✅ Funziona
- Autenticazione (registrazione/accesso con email), profili automatici
- Calendario Serie A con giornate, risultati provvisori/ufficiali distinti
- Compilazione schedina: risultati per tempo, 4 giocatori (≥1 casa, ≥1 ospite,
  ≥1 marcatore), primo sostituto, primo ammonito, bonus visibili prima del blocco
- Motore di scoring server-side in PL/pgSQL con test SQL
- RLS completa: pronostici privati fino al blocco, punteggi immutabili dal client
- Blocco automatico delle giornate via cron (pg_cron → Edge Function, ogni minuto)
- Sync risultati/eventi dal provider con anti-duplicazione eventi
- Classifica generale cumulativa con spareggi; gruppi privati con codice invito
- UI Compose: home con countdown, calendario, schedina, classifica con podio, gruppi

### 🔧 Da fare (prossime fasi)
- Cache degli eventi nel database per non consumare quota del provider a ogni sync
- Correzioni manuali da admin con audit trail completo
- CI su GitHub Actions (build + test Kotlin + test SQL)
- Test RLS automatizzati (violazioni pronostici altrui, modifiche post-blocco)
- Modello statistico reale per i bonus (oggi: valori semplificati per ruolo congelati al seed)
- Statistiche individuali reali (minuti giocati, gol subiti dal portiere) dal provider

### 🔬 POC da verificare
- Affidabilità dell'ordinamento degli **eventi simultanei** (doppio giallo stesso minuto)
  su API-Football: oggi usiamo `event_order` del provider, da validare su partite vere
- Disponibilità e orario delle **formazioni ufficiali** rispetto al blocco delle schedine

## Architettura

```
┌─ App Android (Kotlin, Compose, MVVM, Hilt-less)
│    └─ Supabase Kotlin SDK (auth + postgrest) — solo chiave anonima, RLS attiva
├─ Supabase
│    ├─ Auth (email/password) + profili automatici via trigger
│    ├─ PostgreSQL: schema, RLS, scoring engine (PL/pgSQL), pg_cron
│    └─ Edge Functions (Deno):
│         provider-proxy — accesso all'API calcistica (chiave solo qui)
│         cron-tasks     — blocco giornate + sync risultati/eventi (ogni minuto)
│         seed-league    — ingestione squadre/rose/calendario (protetta da SEED_SECRET)
└─ API-Football v3 (serie A = league 135)
```

Nota test: il piano gratuito di API-Football copre solo 2022-2024. Il database è
seminato con la stagione 2023/24 reale; le giornate 9+ hanno date spostate di ~3 anni
per renderle pronosticabili in demo (artefatto dichiarato, da rimuovere con il piano a pagamento).

## Struttura del repository

```
app/                          App Android (Kotlin, Compose, MVVM)
  src/main/java/.../data/     Modelli, client Supabase, repository
  src/main/java/.../ui/       ViewModel + schermate Compose (italiano)
  src/test/java/...           Test regole client-side (schedina, spareggi)
supabase/
  migrations/                 0001 schema · 0002 RLS · 0003 scoring ·
                              0004 admin · 0005 cron lock · 0006 schedule ·
                              0007 fix RLS gruppi
  functions/                  Edge Functions (Deno/TypeScript)
  tests/scoring_tests.sql     Suite di test del motore di punteggio
```

## Setup e comandi

### Build e test app
```powershell
# Credenziali: crea C:\Users\<tuonome>\.gradle\gradle.properties con
#   supabase.url=https://YOUR-PROJECT.supabase.co
#   supabase.anonKey=YOUR-ANON-KEY

.\gradlew.bat assembleDebug        # APK: app\build\outputs\apk\debug\
.\gradlew.bat test                 # test regole client-side
.\gradlew.bat installDebug         # su dispositivo adb collegato
```

### Database Supabase
```powershell
supabase link --project-ref <REF>          # richiede SUPABASE_ACCESS_TOKEN
supabase db push                           # applica le migrations in ordine
supabase db query --linked "select status, count(*) from matches group by status;"
```

### Ordine di deploy (importante!)
1. **Prima la migration** (`supabase db push`): aggiorna `score_match`/`ingest_match_result`
   e crea event_cache, colonne override e audit before/after.
   ATTENZIONE: la 0008 **sostituisce** `score_match` e `ingest_match_result` (non è
   puramente additiva). Prima del push in produzione eseguire
   `supabase\tests\compare_old_vs_new.sql` (**verifica contro la formula**) su una
   giornata già chiusa: l'output deve essere 0 righe, cioè i punteggi coincidono
   con il regolamento applicato in forma esplicita.
2. **Poi le Edge Functions** (le versioni precedenti di cron-tasks chiamano
   `cache_is_fresh` che non esisterebbe ancora, e non rispetterebbero `manual_override`):
```powershell
supabase functions deploy provider-proxy
supabase functions deploy admin-override
supabase functions deploy admin-release-override
supabase functions deploy cron-tasks
```

### Backup prima del push in produzione (obbligatorio)
```powershell
# 1. Dump completo (schema + dati) con timestamp
supabase db dump --linked --file "backup_$(Get-Date -Format yyyyMMdd_HHmm).sql"

# 2. Solo dati (per restore selettivo)
supabase db dump --linked --data --file "backup_data_$(Get-Date -Format yyyyMMdd_HHmm).sql"

# 3. Conservare i file fuori dal repo (già esclusi da .gitignore: dump.sql, *.dump)
```
In caso di rollback: `psql "<DB_URL>" -f backup_<ts>.sql` dopo aver interrotto il cron
(Dashboard → Database → Cron → disable `fantacalcio365-cron-tasks`).

### Admin: correzione manuale di una partita

`admin-override` sovrascrive risultato, eventi e statistiche di una partita, marca
`manual_override = true` e ricalcola i punteggi. **Mentre l'override è attivo il cron
NON tocca la partita.** Per restituirla al provider usa `admin-release-override`:
dopo il rilascio, il cron al ciclo successivo risincronizza la partita **ricalcolando
i punteggi dai dati del provider**.

Chiamata (solo admin; JWT nel header):

```powershell
# Correzione manuale
Invoke-WebRequest "https://<PROJECT>.supabase.co/functions/v1/admin-override" `
  -Method POST `
  -Headers @{ Authorization = "Bearer <JWT_ADMIN>"; "Content-Type" = "application/json" } `
  -Body '{
    "provider_id": "1234567",
    "reason": "Correzione ufficiale: gol al 62 cambiato in autogol",
    "result": { "status": "CONFIRMED", "ht_home": 1, "ht_away": 0,
                "ht2_home": 1, "ht2_away": 1, "ft_home": 2, "ft_away": 1 },
    "events": [
      { "event_order": 1, "minute": 20, "type": "GOAL", "player": "1089" },
      { "event_order": 2, "minute": 62, "type": "GOAL", "player": "2341", "own_goal": true },
      { "event_order": 3, "minute": 78, "type": "GOAL", "player": "3102" }
    ]
  }'

# Rilascio override: il cron riprende la sincronizzazione e ricalcola
Invoke-WebRequest "https://<PROJECT>.supabase.co/functions/v1/admin-release-override" `
  -Method POST `
  -Headers @{ Authorization = "Bearer <JWT_ADMIN>"; "Content-Type" = "application/json" } `
  -Body '{ "provider_id": "1234567", "reason": "Dati provider confermati corretti" }'
```

Vincoli del payload: `ft = ht + ht2` per entrambe le squadre; il numero di eventi
`GOAL` (autogoli inclusi) deve coincidere con i gol totali; ogni `player` e
`related_player` deve esistere; `event_order` univoco; motivo obbligatorio (5-500 caratteri).

### Edge Functions
```powershell
supabase functions deploy provider-proxy
supabase functions deploy cron-tasks
supabase functions deploy seed-league
supabase secrets set API_FOOTBALL_KEY=...      # chiave provider: SOLO qui
supabase secrets set SEED_SECRET=...           # protezione della seed
```

### Test motore di scoring
```powershell
# su un DB di test con le migrations applicate
psql "<DB_URL>" -f supabase\tests\scoring_tests.sql
```

## Roadmap

1. **Fase 2** — resilienza provider: cache eventi, correzioni manuali admin, audit trail
2. **Fase 3** — CI: GitHub Actions (build + test Kotlin + test SQL su Postgres di servizio)
3. **Fase 4** — sicurezza: test automatizzati RLS e hardening
4. **Fase 5** — proposta semplificazione regolamento (documento)
5. **Lancio** — piano API a pagamento per stagione corrente, rimozione artefatti demo,
   modello statistico bonus calibrato su storico 2022-2024, release firmata su Play Store

## Licenza e_note

Progetto personale/dimostrativo. I dati calcistici sono forniti da API-Football e
usati nel rispetto delle condizioni del provider. Il gioco è gratuito, senza vincite.
