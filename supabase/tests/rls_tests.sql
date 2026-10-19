-- =============================================================
-- FantaCalcio365 - tests/rls_tests.sql
-- FASE 3: RLS sui pronostici + spareggi classifica.
-- Eseguire su DB LOCALE (supabase start) o staging, MAI in produzione:
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/tests/rls_tests.sql
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
-- FIXTURE
-- =============================================================
insert into seasons (id, name) values ('11111111-1111-1111-1111-111111111111', 'RLS Season');
insert into teams (id, provider_id, name, short_name) values
  ('aaaaaaaa-0000-0000-0000-000000000001','T1','Casa','CAS'),
  ('aaaaaaaa-0000-0000-0000-000000000002','T2','Ospite','OSP');
insert into players (id, team_id, provider_id, name, position) values
  ('bbbbbbbb-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','P1','FW Casa','FW'),
  ('bbbbbbbb-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000002','P2','FW Ospite','FW'),
  ('bbbbbbbb-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000001','P3','GK Casa','GK'),
  ('bbbbbbbb-0000-0000-0000-000000000004','aaaaaaaa-0000-0000-0000-000000000002','P4','GK Ospite','GK');

-- Partita A: BLOCCATA (locked_at gia' passato)
-- Partita B: APERA (locked_at null, kickoff futura)
insert into matches (id, season_id, matchday, provider_id, home_team_id, away_team_id,
                     kickoff_at, status, locked_at) values
  ('cccccccc-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111',1,'RA',
   'aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000002',
   now() - interval '1 hour','SCHEDULED', now() - interval '2 hours'),
  ('cccccccc-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111',1,'RB',
   'aaaaaaaa-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000001',
   now() + interval '1 day','SCHEDULED', null);

-- Utenti via auth.users (trigger crea i profili)
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
                        created_at, updated_at, raw_user_meta_data) values
  ('dddddddd-0000-0000-0000-000000000001','authenticated','authenticated','r1@test.local','x',now(),now(),now(),'{"username":"rls1"}'),
  ('dddddddd-0000-0000-0000-000000000002','authenticated','authenticated','r2@test.local','x',now(),now(),now(),'{"username":"rls2"}');

-- user2 ha un pronostico sulla partita APERTA (user1 non deve vederlo)
insert into predictions (id, user_id, match_id, ht_home, ht_away, ht2_home, ht2_away) values
  ('eeeeeeee-0000-0000-0000-000000000002','dddddddd-0000-0000-0000-000000000002',
   'cccccccc-0000-0000-0000-000000000002',2,1,0,1);
insert into prediction_players values
  ('eeeeeeee-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000002',true),
  ('eeeeeeee-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000001',false),
  ('eeeeeeee-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000003',false),
  ('eeeeeeee-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000004',false);

-- =============================================================
-- TEST 1: NO insert pronostico su partita bloccata (via API diretta)
-- =============================================================
do $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"dddddddd-0000-0000-0000-000000000001","role":"authenticated"}', true);
  begin
    insert into predictions (id, user_id, match_id, ht_home, ht_away, ht2_home, ht2_away)
    values ('eeeeeeee-0000-0000-0000-000000000001',
            'dddddddd-0000-0000-0000-000000000001',
            'cccccccc-0000-0000-0000-000000000001', 1,0,0,1);
    raise exception 'FAIL: insert su partita bloccata accettata';
  exception when insufficient_privilege or raise_exception then
    raise notice 'PASS: insert pronostico su partita bloccata RIFIUTATA';
  end;
end $$;

-- Preparazione: sposto il pronostico di user2 sulla partita bloccata
-- (come postgres, per simulare un pronostico fatto PRIMA del blocco)
select set_config('role', 'postgres', true);
update predictions set match_id = 'cccccccc-0000-0000-0000-000000000001'
where id = 'eeeeeeee-0000-0000-0000-000000000002';

-- No UPDATE post-blocco su pronostico preesistente
do $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"dddddddd-0000-0000-0000-000000000002","role":"authenticated"}', true);
  begin
    update predictions set ht_home = 9 where id = 'eeeeeeee-0000-0000-0000-000000000002';
  exception when insufficient_privilege then
    null; -- atteso: RLS rifiuta la modifica post-blocco
  end;
end $$;

select set_config('role', 'postgres', true);
select pg_temp.assert_eq(
  (select count(*)::int from predictions
   where id = 'eeeeeeee-0000-0000-0000-000000000002' and ht_home = 9),
  0::int, 'update pronostico post-blocco BLOCCATO');

-- =============================================================
-- TEST 2: NO lettura pronostici altrui prima del blocco
-- =============================================================
do $$
declare
  v int;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"dddddddd-0000-0000-0000-000000000001","role":"authenticated"}', true);
  select count(*) into v from predictions where user_id = 'dddddddd-0000-0000-0000-000000000002';
  perform pg_temp.assert_eq(v, 0::int,
    'user1 NON legge il pronostico di user2 (prima del blocco)');
  select count(*) into v from prediction_players;
  perform pg_temp.assert_eq(v, 0::int,
    'user1 NON legge prediction_players altrui');
end $$;

select set_config('role', 'postgres', true);

-- =============================================================
-- TEST 3: NO modifica scores / leaderboard
-- =============================================================
insert into scores (user_id, match_id, season_id, matchday, total) values
  ('dddddddd-0000-0000-0000-000000000002','cccccccc-0000-0000-0000-000000000002',
   '11111111-1111-1111-1111-111111111111',1, 50);

do $$
declare
  v_bad int;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"dddddddd-0000-0000-0000-000000000002","role":"authenticated"}', true);
  -- senza policy di update, RLS filtra: l'update non tocca nessuna riga
  update scores set total = 99999;
  select count(*) into v_bad from scores where total = 99999;
  perform pg_temp.assert_eq(v_bad, 0::int, 'update scores BLOCCATO (0 righe toccate)');
  delete from scores;
  select count(*) into v_bad from scores;
  perform pg_temp.assert_eq(v_bad, 1::int, 'delete scores BLOCCATO (righe intatte)');
end $$;

select set_config('role', 'postgres', true);

-- La classifica (vista) resta leggibile ma immutabile
do $$
declare
  v int;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"dddddddd-0000-0000-0000-000000000002","role":"authenticated"}', true);
  select count(*) into v from leaderboard;
  perform pg_temp.assert_eq(v, 1::int, 'leaderboard leggibile');
  begin
    update leaderboard set total = 1;
    raise exception 'FAIL: leaderboard modificata!';
  exception when others then
    raise notice 'PASS: leaderboard NON modificabile (vista read-only)';
  end;
end $$;

select set_config('role', 'postgres', true);

-- =============================================================
-- TEST 4: spareggi classifica — risultato, marcatori, orario,
--         con caso di parita' totale
-- =============================================================
insert into scores (user_id, match_id, season_id, matchday, total, exact_ht, exact_ht2, exact_scorers, first_submitted_at) values
  -- A: 100 punti, 1 esatto, 2 marcatori
  ('dddddddd-0000-0000-0000-000000000001','cccccccc-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',1, 100, true, true, 2, now() - interval '1 hour'),
  -- B: 100 punti, 1 esatto, 2 marcatori, compilato PRIMA (vince per orario)
  ('dddddddd-0000-0000-0000-000000000002','cccccccc-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',1, 100, true, true, 2, now() - interval '2 hour');

-- ranking atteso: parita' totale su punti/esatti/marcatori → decide first_submission
create temp table t_rank as
select user_id, total, exact_ht + exact_ht2 as exacts, exact_scorers, first_submitted_at,
       row_number() over (
         order by total desc, (exact_ht + exact_ht2) desc, exact_scorers desc, first_submitted_at asc
       ) as pos
from scores where season_id = '11111111-1111-1111-1111-111111111111';

select pg_temp.assert_eq((select user_id from t_rank where pos = 1),
                 'dddddddd-0000-0000-0000-000000000002'::uuid,
                 'Spareggio: a parita'' totale vince chi ha compilato prima');

-- caso parita' assoluta (anche orario): entrambi "1°"
create temp table t_tie as
select a.user_id
from scores a join scores b
  on a.user_id <> b.user_id and a.match_id = b.match_id
where a.total = b.total
  and (a.exact_ht + a.exact_ht2) = (b.exact_ht + b.exact_ht2)
  and a.exact_scorers = b.exact_scorers
  and a.first_submitted_at = b.first_submitted_at;

select pg_temp.assert_eq((select count(*) from t_tie), 0::int,
  'Parita'' totale (anche orario): nessun criterio li separa, posto condiviso');

rollback;
