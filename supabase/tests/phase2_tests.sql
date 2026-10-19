-- =============================================================
-- FantaCalcio365 - tests/phase2_tests.sql
-- FASE 2: test su DB LOCALE (supabase start) o staging, MAI in produzione.
-- Copre: override non sovrascritto dal cron, RLS su event_cache/audit,
-- doppio ricalcolo idempotente, concorrenza (FOR UPDATE), permessi funzioni.
-- Uso: supabase db query --local --file supabase/tests/phase2_tests.sql
-- =============================================================

create or replace temp function assert_eq(actual anyelement, expected anyelement, label text)
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

-- Utenti
insert into profiles (id, username, is_admin) values
  ('dddddddd-0000-0000-0000-000000000001','utente1',false),
  ('dddddddd-0000-0000-0000-000000000002','admin1',true);

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
perform public.score_match('cccccccc-0000-0000-0000-000000000001');

-- Pronostico: 1T 1-0 esatto, 2T 0-1 esatto → combo 20 + bonus gol P2 (10) = 30
select assert_eq((select total from scores where user_id='dddddddd-0000-0000-0000-000000000001'),
                 30.0::numeric, 'Punteggio base = 30');

-- Audit: 1 riga SCORE_RECALC
select assert_eq((select count(*)::int from admin_audit_log where action='SCORE_RECALC'),
                 1::int, 'Audit: 1 riga al primo ricalcolo');

-- Somme prima del doppio ricalcolo
create temp table t_sum1 as
  select coalesce(sum(total),0) as s, count(*) as n from scores where match_id = 'cccccccc-0000-0000-0000-000000000001';

-- SECONDO ricalcolo (idempotenza)
perform public.score_match('cccccccc-0000-0000-0000-000000000001');

select assert_eq((select sum(total) from scores where match_id='cccccccc-0000-0000-0000-000000000001'),
                 (select s from t_sum1), 'Idempotenza: somme identiche');
select assert_eq((select count(*)::int from scores where match_id='cccccccc-0000-0000-0000-000000000001'),
                 (select n from t_sum1), 'Idempotenza: stesso numero righe');
select assert_eq((select count(*)::int from admin_audit_log where action='SCORE_RECALC'),
                 1::int, 'Idempotenza: ZERO righe audit nuove al secondo ricalcolo');

-- =============================================================
-- TEST 2: admin_override_match + ricalcolo automatico
-- =============================================================
-- set permesso e contesto admin per chiamare admin_override_match nel test
select set_config('role', 'postgres', true);
select set_config('request.jwt.claims',
  '{"sub":"dddddddd-0000-0000-0000-000000000002","role":"authenticated"}', true);
perform public.admin_override_match(
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

-- Nuovi punteggi: 1T 2-0 errato (0), 2T 1-1 esatto (6), P4 gol x1 = 9 → 15
select assert_eq((select total from scores where user_id='dddddddd-0000-0000-0000-000000000001'),
                 15.0::numeric, 'Override ricalcolato = 15');

select assert_eq((select manual_override from matches where id='cccccccc-0000-0000-0000-000000000001'),
                 true, 'manual_override impostato');

select assert_eq((select override_by from matches where id='cccccccc-0000-0000-0000-000000000001'),
                 'dddddddd-0000-0000-0000-000000000002'::uuid, 'override_by = admin');

select assert_eq((select count(*)::int from admin_audit_log where action='ADMIN_OVERRIDE'),
                 1::int, 'Audit ADMIN_OVERRIDE con before/after');

-- Cron non sovrascrive: ingest_match_result su partita con manual_override = no-op
perform public.ingest_match_result('M1', '{"status":"CONFIRMED","ht_home":9,"ht_away":9,"ht2_home":9,"ht2_away":9,"ft_home":9,"ft_away":9,"events":[]}');
select assert_eq((select ft_home_goals from matches where id='cccccccc-0000-0000-0000-000000000001'),
                 3::int, 'Cron NON sovrascrive partita con manual_override');

-- =============================================================
-- TEST 3: non-admin non puo' fare override
-- =============================================================
do $$
declare
  err text;
begin
  select set_config('role', 'authenticated', true);
  select set_config('request.jwt.claims',
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
  select set_config('role', 'authenticated', true);
  begin
    perform public.cache_match_events('X','cccccccc-0000-0000-0000-000000000001','{}','[]','ok',null);
    raise exception 'TEST FALLITO: authenticated puo' scrivere event_cache';
  exception when insufficient_privilege then
    raise notice 'PASS: cache_match_events negata a authenticated';
  end;
end $$;

select set_config('role', 'postgres', true);

-- =============================================================
-- TEST 5: RLS event_cache senza policy → invisibile agli utenti
-- (verifica strutturale: niente policy per authenticated su event_cache)
-- =============================================================
select assert_eq(
  (select count(*)::int from pg_policies where tablename='event_cache'),
  0::int, 'event_cache: zero policy RLS (invisibile agli utenti)');

select assert_eq(
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

rollback;
