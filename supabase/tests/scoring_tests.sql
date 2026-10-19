-- =============================================================
-- FantaCalcio365 - tests/scoring_tests.sql
-- Suite di test del motore di scoring (eseguire su DB di test,
-- es. supabase db reset + questo script).
-- Uso: psql ... -f tests/scoring_tests.sql
-- =============================================================

-- Utilità di asserzione
create or replace function pg_temp.assert_eq(actual anyelement, expected anyelement, label text)
returns void language plpgsql as $$
begin
  if actual is distinct from expected then
    raise exception 'FAIL [%]: atteso %, ottenuto %', label, expected, actual;
  end if;
  raise notice 'PASS: %', label;
end $$;

begin;

-- Fixture minima ------------------------------------------------
insert into seasons (id, name) values ('11111111-1111-1111-1111-111111111111', 'Test Season');
insert into teams (id, provider_id, name, short_name)
values ('aaaaaaaa-0000-0000-0000-000000000001','T1','Casa','CAS'),
       ('aaaaaaaa-0000-0000-0000-000000000002','T2','Ospite','OSP');
insert into players (id, team_id, provider_id, name, position) values
  ('bbbbbbbb-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','P1','GK Casa','GK'),
  ('bbbbbbbb-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000001','P2','DF Casa','DF'),
  ('bbbbbbbb-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000001','P3','FW Casa','FW'),
  ('bbbbbbbb-0000-0000-0000-000000000004','aaaaaaaa-0000-0000-0000-000000000002','P4','GK Ospite','GK'),
  ('bbbbbbbb-0000-0000-0000-000000000005','aaaaaaaa-0000-0000-0000-000000000002','P5','FW Ospite','FW');

insert into matches (id, season_id, matchday, provider_id, home_team_id, away_team_id,
                     kickoff_at, status, locked_at,
                     ht_home_goals, ht_away_goals, ht2_home_goals, ht2_away_goals,
                     ft_home_goals, ft_away_goals)
values ('cccccccc-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111',1,'M1',
        'aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000002',
        now() - interval '2 hours','FINISHED', now() - interval '3 hours',
        1, 0,   1, 1,   2, 1);
-- Partita reale: 1T 1-0, 2T 1-1, finale 2-1

-- Utenti di prova: creati in auth.users (il trigger on_auth_user_created
-- genera automaticamente i profili in profiles)
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
                        created_at, updated_at, raw_user_meta_data) values
  ('dddddddd-0000-0000-0000-000000000001','authenticated','authenticated','u1@test.local','x',now(),now(),now(),'{"username":"utente1"}'),
  ('dddddddd-0000-0000-0000-000000000002','authenticated','authenticated','u2@test.local','x',now(),now(),now(),'{"username":"utente2"}');

-- Statistiche giocatori (bonus congelati)
insert into player_match_stats (match_id, player_id, played_minutes, goals, conceded_goals,
                                gol_bonus_pts, clean_sheet_bonus_pts, frozen_at) values
  ('cccccccc-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000003',90,2,1,10.0,0,now()),
  ('cccccccc-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000005',90,1,2,8.0,0,now()),
  ('cccccccc-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001',90,0,1,0,0,now()),
  ('cccccccc-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000004',90,0,2,0,0,now());

-- Eventi: 1° gol FW Casa (ord.1), giallo GK Ospite (ord.2), sostituzione DF Casa (ord.3),
-- gol FW Ospite (ord.4), gol FW Casa (ord.5), giallo FW Ospite (ord.6)
insert into match_events (match_id, event_order, minute, type, player_id, related_player_id) values
  ('cccccccc-0000-0000-0000-000000000001',1,20,'GOAL','bbbbbbbb-0000-0000-0000-000000000003',null),
  ('cccccccc-0000-0000-0000-000000000001',2,35,'YELLOW','bbbbbbbb-0000-0000-0000-000000000004',null),
  ('cccccccc-0000-0000-0000-000000000001',3,60,'SUB_OUT','bbbbbbbb-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000003'),
  ('cccccccc-0000-0000-0000-000000000001',4,70,'GOAL','bbbbbbbb-0000-0000-0000-000000000005',null),
  ('cccccccc-0000-0000-0000-000000000001',5,80,'GOAL','bbbbbbbb-0000-0000-0000-000000000003',null),
  ('cccccccc-0000-0000-0000-000000000001',6,90,'YELLOW','bbbbbbbb-0000-0000-0000-000000000005',null);

-- Pronostico utente1: PERFETTO (1T 1-0, 2T 1-1) -> 20 punti + 2x10 bonus gol FW Casa = 40
insert into predictions (id, user_id, match_id, ht_home, ht_away, ht2_home, ht2_away,
                         first_sub_out_player_id, first_yellow_player_id) values
  ('eeeeeeee-0000-0000-0000-000000000001','dddddddd-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000001',1,0,1,1,
   'bbbbbbbb-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000004');
insert into prediction_players values
  ('eeeeeeee-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000003',true),  -- FW Casa marcatore
  ('eeeeeeee-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001',false), -- GK Casa
  ('eeeeeeee-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000004',false), -- GK Ospite
  ('eeeeeeee-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000005',false); -- FW Ospite (NON marcato!)

-- Pronostico utente2: 1T errato (0-0), 2T esatto (1-1) -> 6 punti solo 2T
insert into predictions (id, user_id, match_id, ht_home, ht_away, ht2_home, ht2_away,
                         first_sub_out_player_id, first_yellow_player_id) values
  ('eeeeeeee-0000-0000-0000-000000000002','dddddddd-0000-0000-0000-000000000002',
   'cccccccc-0000-0000-0000-000000000001',0,0,1,1,
   null,'bbbbbbbb-0000-0000-0000-000000000005');
insert into prediction_players values
  ('eeeeeeee-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000005',true),
  ('eeeeeeee-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000004',false),
  ('eeeeeeee-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000001',false),
  ('eeeeeeee-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000002',true);
-- NB: utente2 ha P2 (DF Casa) selezionato ma la squadra HA subìto 1 gol -> no clean sheet

perform public.score_match('cccccccc-0000-0000-0000-000000000001');

-- TEST 1: combo perfetto = 20 base
select pg_temp.assert_eq((select pts_ht + pts_ht2 from scores
                  where user_id='dddddddd-0000-0000-0000-000000000001'), 20::int,
                 'Combo perfetto 1T+2T = 20 punti base');

-- TEST 2: bonus gol doppio = 2 reti x 10 = 20
select pg_temp.assert_eq((select pts_scorers from scores
                  where user_id='dddddddd-0000-0000-0000-000000000001'), 20.0::numeric,
                 'Doppia rete marcatore dichiarato = 2 x bonus');

-- TEST 3: giocatore NON dichiarato marcatore non prende nulla
-- (utente1 ha P5 selezionato non marcato; P5 segna 1 rete x 8 = 8 punti NON assegnati)
select pg_temp.assert_eq((select pts_scorers from scores
                  where user_id='dddddddd-0000-0000-0000-000000000001') - 20.0, 0.0::numeric,
                 'Marcatori non dichiarati non danno bonus');

-- TEST 4: primo sostituto = chi ESCE (P2 DF Casa esce, ord.3)
select pg_temp.assert_eq((select pts_sub from scores
                  where user_id='dddddddd-0000-0000-0000-000000000001'), 2::int,
                 'Primo sostituto (chi esce) = 2 punti');

-- TEST 5: primo ammonito = P4 GK Ospite (ord.2, prima del giallo al 90')
select pg_temp.assert_eq((select pts_yellow from scores
                  where user_id='dddddddd-0000-0000-0000-000000000001'), 2::int,
                 'Primo ammonito = 2 punti');

-- TEST 6: 1T errato ma 2T esatto = solo 6 punti (niente punti per segno)
select pg_temp.assert_eq((select pts_ht + pts_ht2 from scores
                  where user_id='dddddddd-0000-0000-0000-000000000002'), 6::int,
                 'Solo 2T esatto = 6 punti, nessun punto segno');

-- TEST 7: clean sheet negato se squadra ha subito gol
select pg_temp.assert_eq((select pts_clean_sheet from scores
                  where user_id='dddddddd-0000-0000-0000-000000000002'), 0.0::numeric,
                 'No clean sheet con gol subiti');

-- TEST 8: totale utente1 = 20 + 20 + 2 + 2 = 44
select pg_temp.assert_eq((select total from scores
                  where user_id='dddddddd-0000-0000-0000-000000000001'), 44.0::numeric,
                 'Totale utente1 = 44');

rollback;
