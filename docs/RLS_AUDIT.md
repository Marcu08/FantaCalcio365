# Audit RLS — FantaCalcio365

Ultimo audit: FASE 4 (2026-10-19). Esecuzione test: GitHub Actions (`ci.yml`, stack
Supabase locale) con `supabase/tests/rls_tests.sql` e `phase2_tests.sql`.

## Matrice tabelle × policy

| Tabella | RLS | Policy | Copertura |
|---|---|---|---|
| `seasons` | ✅ | select per authenticated | completa |
| `teams` | ✅ | select per authenticated | completa |
| `players` | ✅ | select per authenticated | completa |
| `matches` | ✅ | select per authenticated | completa |
| `match_events` | ✅ | select per authenticated | completa |
| `player_match_stats` | ✅ | select per authenticated | completa (bonus pubblici per design §6) |
| `predictions` | ✅ | select/insert/update/delete solo owner + vincoli di blocco | completa (vedi GAP 2) |
| `prediction_players` | ✅ | read owner; write owner + non bloccata | completa (vedi GAP 1) |
| `scores` | ✅ | select owner only; nessuna insert/update/delete | completa |
| `leaderboard` (vista) | — | read-only per authenticated | completa |
| `groups` | ✅ | read membri/owner; update owner; insert autenticato | completa (fix ricorsione 0007) |
| `group_members` | ✅ | read membri/owner; join con codice; remove owner | completa |
| `profiles` | ✅ | select own/admin; update own con is_admin invariabile + `REVOKE UPDATE (is_admin)` | completa |
| `admin_audit_log` | ✅ | select solo admin; **append-only** (revoke update/delete) | completa |
| `score_corrections` | ✅ | select solo admin | completa |
| `event_cache` | ✅ | **nessuna policy** → invisibile ai client, solo service_role | completa |

## Problemi trovati e fix

| ID | Gravità | Problema | Fix | Test |
|---|---|---|---|---|
| GAP 1 | **ALTA** | `prediction_players`: il `with check` verificava solo la proprietà, non il blocco → aggiunta giocatori a schedina bloccata via API diretta | `0009`: policy di scrittura con verifica blocco (lettura separata, resta possibile al owner) | `rls_tests.sql` TEST 6 |
| GAP 2 | **MEDIA** | `predictions` UPDATE: il `using` non verificava il blocco della riga vecchia → spostamento di una schedina bloccata su una partita aperta | `0009`: `using` + `with check` entrambi con verifica blocco | `rls_tests.sql` TEST 7 |
| GAP 0 (chiuso in FASE 2) | ALTA | ricorsione infinita policy `groups` ↔ `group_members` | `0007`: helper `is_group_member`/`is_group_owner` security definer | CI (creazione gruppo test) |
| GAP 0-bis (chiuso in FASE 2) | MEDIA | funzioni interne eseguibili da PUBLIC di default | `0008`: REVOKE/GRANT espliciti, audit `pg_proc` in CI (5 funzioni eseguibili: `admin_override_match`, `admin_release_override`, `is_admin`, `is_group_member`, `is_group_owner`) | `phase2_tests.sql` TEST 8b |

## Funzioni eseguibili dai ruoli client (verificato in CI)

- `authenticated`: `admin_override_match`, `admin_release_override`, `is_admin`,
  `is_group_member`, `is_group_owner`, `matchday_first_kickoff` — le prime due
  protette dalla guard `is_admin()` interna, l'ultima usata dalle policy di blocco
- `anon`: nessuna
- tutto il resto (scoring, sync, cache, lock): solo `service_role`
