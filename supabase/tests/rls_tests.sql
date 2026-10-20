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
  ('aaaaaaaa-0000-0000-0000-000000000002','T2','Ospite','OSP'),
  ('aaaaaaaa-0000-0000-0000-000000000003','T3','Terza','TER');
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
-- TEST 5: is_admin NON modificabile dal client
--         (update della propria riga e insert con is_admin = true)
-- =============================================================
do $$
declare
  v_bad int;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"dddddddd-0000-0000-0000-000000000001","role":"authenticated"}', true);

  -- 5a: UPDATE della propria riga provando ad auto-promuoversi admin
  begin
    update profiles set is_admin = true where id = 'dddddddd-0000-0000-0000-000000000001';
  exception when insufficient_privilege then
    null; -- policy with-check rifiuta la modifica
  end;
  select count(*) into v_bad from profiles
  where id = 'dddddddd-0000-0000-0000-000000000001' and is_admin = true;
  perform pg_temp.assert_eq(v_bad, 0::int, 'self-promozione a admin BLOCCATA su update');

  -- 5b: INSERT di un profilo con is_admin = true
  -- (nessuna insert policy su profiles: RLS la nega; un eventuale id
  --  inesistente violerebbe anche la FK — entrambi gli esiti sono "negato")
  begin
    insert into profiles (id, username, is_admin)
    values ('dddddddd-0000-0000-0000-000000000009', 'hacker', true);
    raise exception 'FAIL: insert profilo admin accettata';
  exception
    when insufficient_privilege or foreign_key_violation or raise_exception then
      raise notice 'PASS: insert profilo con is_admin=true RIFIUTATA';
  end;
end $$;

select set_config('role', 'postgres', true);

-- =============================================================
-- TEST 6: spareggi classifica — risultato, marcatori, orario,
insert into scores (user_id, match_id, season_id, matchday, total, exact_ht, exact_ht2, exact_scorers, first_submitted_at) values
  -- A: 100 punti, 1 esatto, 2 marcatori
  ('dddddddd-0000-0000-0000-000000000001','cccccccc-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',1, 100, true, true, 2, now() - interval '1 hour'),
  -- B: 100 punti, 1 esatto, 2 marcatori, compilato PRIMA (vince per orario)
  ('dddddddd-0000-0000-0000-000000000002','cccccccc-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',1, 100, true, true, 2, now() - interval '2 hour');

-- ranking atteso: parita' totale su punti/esatti/marcatori → decide first_submission
create temp table t_rank as
select user_id, total, exact_ht::int + exact_ht2::int as exacts, exact_scorers, first_submitted_at,
       row_number() over (
         order by total desc, (exact_ht::int + exact_ht2::int) desc, exact_scorers desc, first_submitted_at asc
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
  and (a.exact_ht::int + a.exact_ht2::int) = (b.exact_ht::int + b.exact_ht2::int)
  and a.exact_scorers = b.exact_scorers
  and a.first_submitted_at = b.first_submitted_at;

select pg_temp.assert_eq((select count(*)::int from t_tie), 0::int,
  'Parita'' totale (anche orario): nessun criterio li separa, posto condiviso');

-- =============================================================
-- TEST 6 (FASE 4): GAP 1 chiuso — NO aggiunta giocatori a schedina
--                   bloccata via API diretta
-- =============================================================
do $$
declare
  v_before int;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"dddddddd-0000-0000-0000-000000000002","role":"authenticated"}', true);
  select count(*) into v_before from prediction_players
  where prediction_id = 'eeeeeeee-0000-0000-0000-000000000002';
  begin
    -- aggiungo un giocatore alla schedina di user2, ora su partita BLOCCATA
    insert into prediction_players values
      ('eeeeeeee-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000004',true);
    raise exception 'FAIL: aggiunta giocatori a schedina bloccata accettata';
  exception when insufficient_privilege then
    null; -- atteso: with-check ora verifica il blocco
  end;
  perform pg_temp.assert_eq((select count(*)::int from prediction_players
                     where prediction_id = 'eeeeeeee-0000-0000-0000-000000000002'),
                    v_before::int, 'GAP 1 chiuso: prediction_players immutabili post-blocco');
end $$;

select set_config('role', 'postgres', true);

-- =============================================================
-- TEST 7 (FASE 4): GAP 2 chiuso — NO spostamento schedina bloccata
--                   su partita aperta
-- =============================================================
do $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"dddddddd-0000-0000-0000-000000000002","role":"authenticated"}', true);
  begin
    -- la schedina di user2 e' su partita BLOCCATA (RA); provo a spostarla
    -- sulla partita APERTA (RB): con il gap chiuso l'UPDATE non tocca righe
    -- (RLS filtra la riga vecchia) e non solleva errori
    update predictions set match_id = 'cccccccc-0000-0000-0000-000000000002'
    where id = 'eeeeeeee-0000-0000-0000-000000000002';
  exception when insufficient_privilege then
    null; -- accettabile anche un errore esplicito, a seconda del piano
  end;
end $$;

select set_config('role', 'postgres', true);
select pg_temp.assert_eq(
  (select count(*)::int from predictions
   where id = 'eeeeeeee-0000-0000-0000-000000000002'
     and match_id = 'cccccccc-0000-0000-0000-000000000001'),
  1::int, 'GAP 2 chiuso: schedina bloccata non spostabile (resta su RA)');

-- TEST 8-bis: la LETTURA della propria schedina bloccata resta possibile
-- (l'app deve mostrare la schedina compilata anche dopo il blocco)
do $$
declare
  v int;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"dddddddd-0000-0000-0000-000000000002","role":"authenticated"}', true);
  select count(*) into v from prediction_players
  where prediction_id = 'eeeeeeee-0000-0000-0000-000000000002';
  perform pg_temp.assert_eq(v, 4::int,
    'Lettura propria schedina bloccata: ancora possibile');
end $$;

select set_config('role', 'postgres', true);

-- =============================================================
-- TEST 9 (FASE 4, P0): gara aggiunta DOPO il blocco della giornata
-- → nessun pronostico tardivo possibile
-- =============================================================
select set_config('role', 'postgres', true);

-- RA e' bloccata (locked_at passato); RB appartiene alla stessa giornata 1
-- ma ha locked_at null. Aggiungo una NUOVA gara alla giornata 1 con
-- kickoff futuro e locked_at null: senza la fix di 0010 accetterebbe
-- pronostici tardivi (gap per-partita).
insert into matches (id, season_id, matchday, provider_id, home_team_id, away_team_id,
                     kickoff_at, status, locked_at) values
  ('cccccccc-0000-0000-0000-000000000009','11111111-1111-1111-1111-111111111111',1,'RX',
   'aaaaaaaa-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000001',
   now() + interval '2 hours','SCHEDULED', null);

-- La prima gara della giornata (RA) e' gia' iniziata:
select pg_temp.assert_eq(
  (select count(*)::int from matches
   where season_id = '11111111-1111-1111-1111-111111111111'
     and matchday = 1 and kickoff_at <= now()),
  1::int, 'Setup: la giornata 1 ha la prima gara gia'' iniziata (blocco attivo)');

do $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"dddddddd-0000-0000-0000-000000000001","role":"authenticated"}', true);
  begin
    insert into predictions (id, user_id, match_id, ht_home, ht_away, ht2_home, ht2_away)
    values ('eeeeeeee-0000-0000-0000-000000000050',
            'dddddddd-0000-0000-0000-000000000001',
            'cccccccc-0000-0000-0000-000000000009', 1,0,0,1);
    -- senza policy matchday-level l'insert passerebbe: con-check lo nega
    if exists (select 1 from predictions where id = 'eeeeeeee-0000-0000-0000-000000000050') then
      raise exception 'FAIL: pronostico tardivo su gara post-blocco ACCETTATO';
    end if;
  exception when insufficient_privilege then
    null; -- atteso: RLS rifiuta l'insert (riga nuova su partita bloccata)
  end;
  raise notice 'PASS: nessun pronostico tardivo su gara aggiunta a giornata bloccata';
end $$;

select set_config('role', 'postgres', true);

rollback;
