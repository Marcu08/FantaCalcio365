-- =============================================================
-- FantaCalcio365 - tests/compare_old_vs_new.sql
-- Verifica contro la formula (FASE 2): ricalcola una giornata GIA'
-- CHIUSA applicando il regolamento in forma inline e confronta con i
-- punteggi scritti da score_match (0008). La "v1" (0003) non ha mai
-- girato su dati reali: questo script e' il confronto con LA FORMULA.
--
-- PROCEDURA (post `supabase db push` in produzione o su staging):
--   1) forzare il ricalcolo della giornata:
--      select public.score_match(id) from matches
--      where matchday = 9 and season_id = (select id from seasons
--            order by created_at desc limit 1)
--        and status in ('FINISHED','CONFIRMED');
--   2) eseguire questo script:
--      supabase db query --linked --file supabase/tests/compare_old_vs_new.sql
-- Output atteso: 0 righe = punteggi coincidenti con la formula.
-- =============================================================

with pred_per_match as (
  select pr.id as prediction_id, pr.user_id, pr.match_id,
         m.ht_home_goals, m.ht_away_goals, m.ht2_home_goals, m.ht2_away_goals,
         pr.ht_home, pr.ht_away, pr.ht2_home, pr.ht2_away,
         pr.first_sub_out_player_id, pr.first_yellow_player_id
  from predictions pr
  join matches m on m.id = pr.match_id
  where m.matchday = 9     -- ← giornata chiusa da verificare
    and m.season_id = (select id from seasons order by created_at desc limit 1)
    and m.status in ('FINISHED','CONFIRMED')
),
-- REGOLAMENTO applicato in forma esplicita:
--   combo esatto = 4 + 6 + 10; solo 2T = 6; solo marcatori dichiarati;
--   porta inviolata solo GK/DF con minuti > 0 e 0 gol subiti;
--   primo sostituto / primo ammonito = 2.
formula as (
  select
    p.user_id, p.match_id,
    case when p.ht_home = p.ht_home_goals and p.ht_away = p.ht_away_goals
          and p.ht2_home = p.ht2_home_goals and p.ht2_away = p.ht2_away_goals
         then 4 else 0 end as pts_ht,
    case when p.ht2_home = p.ht2_home_goals and p.ht2_away = p.ht2_away_goals
         then 6 else 0 end
    + case when p.ht_home = p.ht_home_goals and p.ht_away = p.ht_away_goals
            and p.ht2_home = p.ht2_home_goals and p.ht2_away = p.ht2_away_goals
           then 10 else 0 end as pts_ht2,
    coalesce((
      select sum(ps.gol_bonus_pts * ps.goals)
      from prediction_players pp
      join player_match_stats ps on ps.match_id = p.match_id and ps.player_id = pp.player_id
      where pp.prediction_id = p.prediction_id and pp.is_marked_scorer and ps.goals > 0
    ), 0) as pts_scorers,
    coalesce((
      select sum(ps.clean_sheet_bonus_pts)
      from prediction_players pp
      join player_match_stats ps on ps.match_id = p.match_id and ps.player_id = pp.player_id
      join players pl on pl.id = pp.player_id
      where pp.prediction_id = p.prediction_id and ps.played_minutes > 0
        and ps.conceded_goals = 0 and pl.position in ('GK','DF')
    ), 0) as pts_cs,
    case when p.first_sub_out_player_id = public.first_sub_out(p.match_id) then 2 else 0 end as pts_sub,
    case when p.first_yellow_player_id = public.first_yellow(p.match_id) then 2 else 0 end as pts_yellow
  from pred_per_match p
),
formula_tot as (
  select user_id, match_id,
         pts_ht + pts_ht2 + pts_scorers + pts_cs + pts_sub + pts_yellow as total_formula
  from formula
)
select s.user_id, s.match_id, f.total_formula, s.total as total_score_match,
       f.total_formula - s.total as delta
from formula_tot f
join scores s on s.user_id = f.user_id and s.match_id = f.match_id
where f.total_formula <> s.total;
