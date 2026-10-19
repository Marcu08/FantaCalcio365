# FantaCalcio365

App Android nativa (Kotlin + Jetpack Compose) per pronostici gratuiti sulla Serie A.
Nessuna puntata, nessun premio in denaro: solo punti e classifica stagionale cumulativa.

## Regolamento (approvato)

- **Risultati per tempo (modalità combinata prevale):**
  - 1T esatto + 2T esatto = 4 + 6 + 10 bonus = **20 punti**
  - Solo 2T esatto = **6 punti**
  - Solo 1T esatto = **0 punti** (vale solo nel combo — decisione A1)
  - Nessun punto per il solo segno; nessuna regola speciale per 1T 0-0
- **Quattro giocatori** per partita: almeno 1 di casa, almeno 1 ospite, **almeno 1 dichiarato marcatore**.
  Ogni rete di un marcatore dichiarato vale il **bonus gol dinamico 5–15 punti** (moltiplicato per le reti).
  Giocatore selezionato non dichiarato = 0 punti anche se segna. Non entrato in campo = 0 punti.
- **Porta inviolata** (somma al bonus gol): GK/DF scesi in campo, 0 gol subiti. Valore del modello congelato; tetto **10 punti solo per i portieri**.
- **Primo sostituto** (chi esce) = 2 punti. **Primo ammonito** (in campo) = 2 punti. Parità risolta con l'ordinamento evento del provider.
- **Blocco pronostici** all'inizio della prima gara della giornata, verificato dal server. Mai riaperture; le gare rinviate post-blocco conservano i pronostici.
- **Classifica generale cumulativa** con spareggi: risultati esatti → marcatori esatti → orario di compilazione.

## Struttura

```
app/                      App Android (Kotlin, Compose, MVVM)
supabase/
  migrations/             Schema SQL + RLS + motore di scoring (PL/pgSQL)
  functions/              Edge Functions: proxy provider + cron (blocco/sync)
  tests/                  Suite di test SQL del motore di scoring
```

## Setup

1. Progetto Supabase + applicare le migrations (`supabase db push` o SQL editor).
2. Segreti Edge Functions: `API_FOOTBALL_KEY` (mai nell'app).
3. `gradle.properties`: compilare `supabase.url` e `supabase.anonKey`.
4. Build: `./gradlew assembleDebug` · Test: `./gradlew test` · Test SQL: `psql -f supabase/tests/scoring_tests.sql`.

## Provider calcistico

Scelto **API-Football (api-sports.io)** per copertura Serie A completa (eventi minutati,
formazioni, sostituzioni, cartellini), eventi ordinati e costi contenuti (piano gratuito
per lo sviluppo, ~29 USD/mese in produzione). POC da fare per verificare l'affidabilità
dell'ordinamento eventi simultanei e le formazioni ufficiali.
