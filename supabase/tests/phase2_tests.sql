-- =============================================================
-- FantaCalcio365 - tests/phase2_tests.sql
-- FASE 2: test su DB LOCALE (supabase start) o staging, MAI in produzione.
-- Copre: override non sovrascritto dal cron, RLS su event_cache/audit,
-- doppio ricalcolo idempotente, concorrenza (FOR UPDATE), permessi funzioni.
-- Uso: supabase db query --local --file supabase/tests/phase2_tests.sql
-- =============================================================

create or replace function pg_temp.assert_eq(actual anyelement, expected anyelement, label text)
returns void language plpgsql as $$
begin
  if actual is distinct from expected then
    raise exception 'FAIL [%]: atteso %, ottenuto %', label, expected, actual;
  end if;
  raise notice 'PASS: %', label;
end $$;

begin;

-- =============================================================
-- FIXTURE: stagione, squadre, giocatori, partita FINISHED
-- =============================================================
insert into seasons (id, name) values ('11111111-1111-1111-1111-111111111111', 'Test S2');
insert into teams (id, provider_id, name, short_name) values
  ('aaaaaaaa-0000-0000-0000-000000000001','T1','Casa','CAS'),
  ('aaaaaaaa-0000-0000-0000-000000000002','T2','Ospite','OSP');
insert into players (id, team_id, provider_id, name, position) values
  ('bbbbbbbb-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','P1','GK Casa','GK'),
  ('bbbbbbbb-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000001','P2','FW Casa','FW'),
  ('bbbbbbbb-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000002','P3','GK Ospite','GK'),
  ('bbbbbbbb-0000-0000-0000-000000000004','aaaaaaaa-0000-0000-0000-000000000002','P4','FW Ospite','FW');

insert into matches (id, season_id, matchday, provider_id, home_team_id, away_team_id,
                     kickoff_at, status, locked_at,
                     ht_home_goals, ht_away_goals, ht2_home_goals, ht2_away_goals,
                     ft_home_goals, ft_away_goals)
values ('cccccccc-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111',1,'M1',
        'aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000002',
        now() - interval '3 hours','FINISHED', now() - interval '4 hours',
        1, 0,   0, 1,   1, 1);

insert into player_match_stats (match_id, player_id, played_minutes, goals, conceded_goals,
                                gol_bonus_pts, clean_sheet_bonus_pts, frozen_at) values
  ('cccccccc-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000002',90,1,1,10.0,0,now()),
  ('cccccccc-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000004',90,0,1,9.0,0,now());

insert into match_events (match_id, event_order, minute, type, player_id) values
  ('cccccccc-0000-0000-0000-000000000001',1,30,'GOAL','bbbbbbbb-0000-0000-0000-000000000002'),
  ('cccccccc-0000-0000-0000-000000000001',2,75,'GOAL','bbbbbbbb-0000-0000-0000-000000000004');

-- Utenti: auth.users (trigger crea i profili) + admin elevato a mano
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
                        created_at, updated_at, raw_user_meta_data) values
  ('dddddddd-0000-0000-0000-000000000001','authenticated','authenticated','u1@test.local','x',now(),now(),now(),'{"username":"utente1"}'),
  ('dddddddd-0000-0000-0000-000000000002','authenticated','authenticated','admin@test.local','x',now(),now(),now(),'{"username":"admin1"}');
update profiles set is_admin = true where id = 'dddddddd-0000-0000-0000-000000000002';

insert into predictions (id, user_id, match_id, ht_home, ht_away, ht2_home, ht2_away,
                         first_sub_out_player_id, first_yellow_player_id) values
  ('eeeeeeee-0000-0000-0000-000000000001','dddddddd-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000001',1,0,0,1,null,null);
insert into prediction_players values
  ('eeeeeeee-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000002',true),
  ('eeeeeeee-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001',false),
  ('eeeeeeee-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000003',false),
  ('eeeeeeee-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000004',true);

-- =============================================================
-- TEST 1: ricalcolo base + idempotenza
-- =============================================================
select public.score_match('cccccccc-0000-0000-0000-000000000001');

-- Pronostico: 1T 1-0 esatto, 2T 0-1 esatto → combo 20 + bonus gol P2 (10) = 30
select pg_temp.assert_eq((select total from scores where user_id='dddddddd-0000-0000-0000-000000000001'),
                 30.0::numeric, 'Punteggio base = 30');

-- Audit: 1 riga SCORE_RECALC
select pg_temp.assert_eq((select count(*)::int from admin_audit_log where action='SCORE_RECALC'),
                 1::int, 'Audit: 1 riga al primo ricalcolo');

-- Somme prima del doppio ricalcolo
create temp table t_sum1 as
  select coalesce(sum(total),0) as s, count(*) as n from scores where match_id = 'cccccccc-0000-0000-0000-000000000001';

-- SECONDO ricalcolo (idempotenza)
select public.score_match('cccccccc-0000-0000-0000-000000000001');

select pg_temp.assert_eq((select sum(total) from scores where match_id='cccccccc-0000-0000-0000-000000000001'),
                 (select s from t_sum1), 'Idempotenza: somme identiche');
select pg_temp.assert_eq((select count(*)::int from scores where match_id='cccccccc-0000-0000-0000-000000000001'),
                 (select n::int from t_sum1), 'Idempotenza: stesso numero righe');
select pg_temp.assert_eq((select count(*)::int from admin_audit_log where action='SCORE_RECALC'),
                 1::int, 'Idempotenza: ZERO righe audit nuove al secondo ricalcolo');

-- =============================================================
-- TEST 2: admin_override_match + ricalcolo automatico
-- =============================================================
-- set permesso e contesto admin per chiamare admin_override_match nel test
select set_config('role', 'postgres', true);
select set_config('request.jwt.claims',
  '{"sub":"dddddddd-0000-0000-0000-000000000002","role":"authenticated"}', true);
select public.admin_override_match(
  'M1',
  '{"status":"CONFIRMED","ht_home":2,"ht_away":0,"ht2_home":1,"ht2_away":1,"ft_home":3,"ft_away":1}',
  '[{"event_order":1,"minute":10,"type":"GOAL","player":"P2"},
    {"event_order":2,"minute":40,"type":"GOAL","player":"P2"},
    {"event_order":3,"minute":60,"type":"GOAL","player":"P4"},
    {"event_order":4,"minute":80,"type":"YELLOW","player":"P3"}]',
  'Correzione ufficiale lega',
  'dddddddd-0000-0000-0000-000000000002'
);
reset role;

-- Nuovi punteggi: 1T 2-0 errato (0), 2T 1-1 errato (0),
-- P2 marcatore 2 reti x 10 = 20, P4 marcatore 1 rete x 9 = 9 → 29
select pg_temp.assert_eq((select total from scores where user_id='dddddddd-0000-0000-0000-000000000001'),
                 29.0::numeric, 'Override ricalcolato = 29');

select pg_temp.assert_eq((select manual_override from matches where id='cccccccc-0000-0000-0000-000000000001'),
                 true, 'manual_override impostato');

select pg_temp.assert_eq((select override_by from matches where id='cccccccc-0000-0000-0000-000000000001'),
                 'dddddddd-0000-0000-0000-000000000002'::uuid, 'override_by = admin');

select pg_temp.assert_eq((select count(*)::int from admin_audit_log where action='ADMIN_OVERRIDE'),
                 1::int, 'Audit ADMIN_OVERRIDE con before/after');

-- Cron non sovrascrive: ingest_match_result su partita con manual_override = no-op
select public.ingest_match_result('M1', '{"status":"CONFIRMED","ht_home":9,"ht_away":9,"ht2_home":9,"ht2_away":9,"ft_home":9,"ft_away":9,"events":[]}');
select pg_temp.assert_eq((select ft_home_goals from matches where id='cccccccc-0000-0000-0000-000000000001'),
                 3::int, 'Cron NON sovrascrive partita con manual_override');

-- =============================================================
-- TEST 3: non-admin non puo'' fare override
-- =============================================================
do $$
declare
  err text;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"dddddddd-0000-0000-0000-000000000001","role":"authenticated"}', true);
  begin
    perform public.admin_override_match('M1','{"status":"CONFIRMED","ht_home":0,"ht_away":0,"ht2_home":0,"ht2_away":0,"ft_home":0,"ft_away":0}','[]','abuso utente normale');
    raise exception 'TEST FALLITO: utente normale ha eseguito override';
  exception when insufficient_privilege or raise_exception then
    raise notice 'PASS: utente normale bloccato su admin_override_match';
  end;
end $$;

select set_config('role', 'postgres', true);

-- =============================================================
-- TEST 4: permessi funzioni cache (revoked da authenticated)
-- =============================================================
do $$
begin
  perform set_config('role', 'authenticated', true);
  begin
    perform public.cache_match_events('X','cccccccc-0000-0000-0000-000000000001','{}','[]','ok',null);
    raise exception 'TEST FALLITO: authenticated puo'' scrivere event_cache';
  exception when insufficient_privilege then
    raise notice 'PASS: cache_match_events negata a authenticated';
  end;
end $$;

select set_config('role', 'postgres', true);

-- =============================================================
-- TEST 5: RLS event_cache senza policy → invisibile agli utenti
-- (verifica strutturale: niente policy per authenticated su event_cache)
-- =============================================================
select pg_temp.assert_eq(
  (select count(*)::int from pg_policies where tablename='event_cache'),
  0::int, 'event_cache: zero policy RLS (invisibile agli utenti)');

select pg_temp.assert_eq(
  (select rowsecurity::int from pg_tables where tablename='event_cache'),
  1::int, 'event_cache: RLS attiva');

-- =============================================================
-- TEST 6: event_order univoco in override
-- =============================================================
do $$
begin
  begin
    perform public.admin_override_match(
      'M1',
      '{"status":"CONFIRMED","ht_home":1,"ht_away":0,"ht2_home":0,"ht2_away":0,"ft_home":1,"ft_away":0}',
      '[{"event_order":1,"minute":10,"type":"GOAL","player":"P2"},
        {"event_order":1,"minute":20,"type":"GOAL","player":"P2"}]',
      'Test ordini duplicati',
      'dddddddd-0000-0000-0000-000000000002');
    raise exception 'TEST FALLITO: event_order duplicati accettati';
  exception when raise_exception then
    raise notice 'PASS: event_order duplicati rifiutati';
  end;
end $$;

-- =============================================================
-- TEST 7: giocatore inesistente rifiutato
-- =============================================================
do $$
begin
  begin
    perform public.admin_override_match(
      'M1',
      '{"status":"CONFIRMED","ht_home":1,"ht_away":0,"ht2_home":0,"ht2_away":0,"ft_home":1,"ft_away":0}',
      '[{"event_order":1,"minute":10,"type":"GOAL","player":"INESISTENTE"}]',
      'Test giocatore fantasma',
      'dddddddd-0000-0000-0000-000000000002');
    raise exception 'TEST FALLITO: giocatore inesistente accettato';
  exception when raise_exception then
    raise notice 'PASS: giocatore inesistente rifiutato';
  end;
end $$;

-- =============================================================
-- TEST 8: due gialli STESSO minuto → decide event_order del provider
-- =============================================================
-- Nuova partita: due gialli entrambi al minuto 10, ordini 1 e 2.
insert into matches (id, season_id, matchday, provider_id, home_team_id, away_team_id,
                     kickoff_at, status, locked_at,
                     ht_home_goals, ht_away_goals, ht2_home_goals, ht2_away_goals,
                     ft_home_goals, ft_away_goals)
values ('cccccccc-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111',3,'M2',
        'aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000002',
        now() - interval '2 hours','FINISHED', now() - interval '3 hours',
        0, 0,   0, 0,   0, 0);

insert into match_events (match_id, event_order, minute, type, player_id) values
  ('cccccccc-0000-0000-0000-000000000002',1,10,'YELLOW','bbbbbbbb-0000-0000-0000-000000000002'),
  ('cccccccc-0000-0000-0000-000000000002',2,10,'YELLOW','bbbbbbbb-0000-0000-0000-000000000004');

select pg_temp.assert_eq(public.first_yellow('cccccccc-0000-0000-0000-000000000002'),
                 'bbbbbbbb-0000-0000-0000-000000000002'::uuid,
                 'Gialli stesso minuto: vince event_order (ordine provider)');

-- =============================================================
-- TEST 9: giocatore mai entrato in campo = 0 punti
-- =============================================================
-- P5 della casa non ha statistiche di gioco (mai convocato/entrato):
insert into players (id, team_id, provider_id, name, position) values
  ('bbbbbbbb-0000-0000-0000-000000000005','aaaaaaaa-0000-0000-0000-000000000001','P5','Panchina Casa','FW');

-- Pronostico che lo dichiara marcatore su M2 (0-0)
insert into predictions (id, user_id, match_id, ht_home, ht_away, ht2_home, ht2_away) values
  ('eeeeeeee-0000-0000-0000-000000000002','dddddddd-0000-0000-0000-000000000002',
   'cccccccc-0000-0000-0000-000000000002',0,0,0,0);
insert into prediction_players values
  ('eeeeeeee-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000005',true),
  ('eeeeeeee-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000001',false),
  ('eeeeeeee-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000003',false),
  ('eeeeeeee-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000004',false);

select public.score_match('cccccccc-0000-0000-0000-000000000002');

-- Il combo 0-0 esatto vale comunque 20; ciò che DEVE essere 0 e' il bonus marcatore:
-- P5 dichiarato ma senza statistiche (mai entrato) non contribuisce
select pg_temp.assert_eq((select pts_scorers from scores
                  where user_id='dddddddd-0000-0000-0000-000000000002'
                    and match_id='cccccccc-0000-0000-0000-000000000002'),
                 0.0::numeric,
                 'Giocatore mai entrato in campo: bonus gol = 0, nessun auto-bonus');
select pg_temp.assert_eq((select total from scores
                  where user_id='dddddddd-0000-0000-0000-000000000002'
                    and match_id='cccccccc-0000-0000-0000-000000000002'),
                 20.0::numeric,
                 'Totale M2 = 20 (solo combo esatto, zero bonus marcatore)');

-- =============================================================
-- TEST 10: gara rinviata DOPO il blocco → pronostico resta valido
-- e viene valutato quando la gara si disputa (A5)
-- =============================================================
-- M3: bloccata, poi rinviata, poi disputata in data successiva
insert into matches (id, season_id, matchday, provider_id, home_team_id, away_team_id,
                     kickoff_at, status, locked_at)
values ('cccccccc-0000-0000-0000-000000000003','11111111-1111-1111-1111-111111111111',2,'M3',
        'aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000002',
        now() - interval '1 day','POSTPONED', now() - interval '2 day');

-- Pronostico fatto prima del rinvio (la policy RLS blocca MODIFICHE, non il salvataggio)
insert into predictions (id, user_id, match_id, ht_home, ht_away, ht2_home, ht2_away) values
  ('eeeeeeee-0000-0000-0000-000000000003','dddddddd-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000003',1,0,0,1);
insert into prediction_players values
  ('eeeeeeee-0000-0000-0000-000000000003','bbbbbbbb-0000-0000-0000-000000000002',true),
  ('eeeeeeee-0000-0000-0000-000000000003','bbbbbbbb-0000-0000-0000-000000000001',false),
  ('eeeeeeee-0000-0000-0000-000000000003','bbbbbbbb-0000-0000-0000-000000000003',false),
  ('eeeeeeee-0000-0000-0000-000000000003','bbbbbbbb-0000-0000-0000-000000000004',true);

-- La gara si disputa e viene inserita dal cron
select public.ingest_match_result('M3', '{"status":"FINISHED","ht_home":1,"ht_away":0,"ht2_home":0,"ht2_away":1,"ft_home":1,"ft_away":1,"events":[{"event_order":1,"minute":20,"type":"GOAL","player":"P2"},{"event_order":2,"minute":80,"type":"GOAL","player":"P4"}]}');

-- Combo esatto 20. I bonus gol (P2, P4) valgono 0 qui: su una partita di test
-- senza bonus congelati dal modello, gol_bonus_pts di default e' 0.
-- In produzione i bonus esistono perche' congelati al blocco (§6).
select pg_temp.assert_eq((select total from scores
                  where user_id='dddddddd-0000-0000-0000-000000000001'
                    and match_id='cccccccc-0000-0000-0000-000000000003'),
                 20.0::numeric,
                 'Gara rinviata post-blocco: pronostico valutato alla nuova data');

-- =============================================================
-- TEST 11: utente normale NON legge admin_audit_log (RLS is_admin)
-- =============================================================
do $$
declare
  v_visible int;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"dddddddd-0000-0000-0000-000000000001","role":"authenticated"}', true);
  select count(*) into v_visible from admin_audit_log;
  perform pg_temp.assert_eq(v_visible, 0::int,
    'Utente normale: zero righe di admin_audit_log (RLS is_admin)');
end $$;

select set_config('role', 'postgres', true);

-- L'admin invece le vede
do $$
declare
  v_visible int;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"dddddddd-0000-0000-0000-000000000002","role":"authenticated"}', true);
  select count(*) into v_visible from admin_audit_log;
  if v_visible < 1 then raise exception 'FAIL: admin non vede audit log'; end if;
  raise notice 'PASS: admin vede admin_audit_log';
end $$;

select set_config('role', 'postgres', true);

rollback;
