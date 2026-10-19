-- =============================================================
-- FantaCalcio365 - tests/populated_seed.sql
-- Dati di esempio realistici inseriti dopo 0001..0007, PRIMA di
-- applicare la 0008 nel workflow CI. I conteggi pre/post 0008 devono
-- coincidere (nessun dato perso).
-- =============================================================
insert into seasons (id, name) values ('11111111-1111-1111-1111-111111111111', 'Populated Season');
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
        now() - interval '2 hours','FINISHED', now() - interval '3 hours',
        1, 0,   1, 1,   2, 1);

insert into player_match_stats (match_id, player_id, played_minutes, goals, conceded_goals,
                                gol_bonus_pts, clean_sheet_bonus_pts, frozen_at) values
  ('cccccccc-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000002',90,2,1,10.0,0,now());

insert into match_events (match_id, event_order, minute, type, player_id) values
  ('cccccccc-0000-0000-0000-000000000001',1,20,'GOAL','bbbbbbbb-0000-0000-0000-000000000002'),
  ('cccccccc-0000-0000-0000-000000000001',2,80,'GOAL','bbbbbbbb-0000-0000-0000-000000000002');

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
                        created_at, updated_at, raw_user_meta_data) values
  ('dddddddd-0000-0000-0000-000000000001','authenticated','authenticated','u1@test.local','x',now(),now(),now(),'{"username":"pop1"}');

insert into predictions (id, user_id, match_id, ht_home, ht_away, ht2_home, ht2_away) values
  ('eeeeeeee-0000-0000-0000-000000000001','dddddddd-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000001',1,0,1,1);
insert into prediction_players values
  ('eeeeeeee-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000002',true),
  ('eeeeeeee-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001',false),
  ('eeeeeeee-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000003',false),
  ('eeeeeeee-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000004',false);

-- punteggio gia' calcolato con lo schema pre-0008
insert into scores (user_id, match_id, season_id, matchday, pts_ht, pts_ht2, pts_scorers,
                    pts_clean_sheet, pts_sub, pts_yellow, total, exact_ht, exact_ht2,
                    exact_scorers, first_submitted_at, is_provisional, is_official) values
  ('dddddddd-0000-0000-0000-000000000001','cccccccc-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',1, 4, 16, 20.0, 0, 0, 0, 40.0,
   true, true, 2, now(), false, false);
