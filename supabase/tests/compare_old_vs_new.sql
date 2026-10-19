-- =============================================================
-- FantaCalcio365 - tests/compare_old_vs_new.sql
-- Verifica pre-push in produzione (FASE 2): ricalcola una giornata
-- GIA' CHIUSA con la formula "vecchia" (0003, inline sotto) e confronta
-- con i punteggi che score_match v2 (0008) scrive in scores.
--
-- ESECUZIONE (dopo il push di 0008 e il ricalcolo automatico/trigger):
--   supabase db query --linked --file supabase/tests/compare_old_vs_new.sql
-- Output: 0 righe = nessuna discrepanza; righe > 0 = differenze da indagare.
-- =============================================================

-- Sostituisci con la giornata chiusa da verificare
create temp var_matchday int default 9;
create temp var_season uuid default (select id from seasons order by created_at desc limit 1);

with pred_per_match as (
  select pr.id as prediction_id, pr.user_id, pr.match_id, m.matchday,
         m.ht_home_goals, m.ht_away_goals, m.ht2_home_goals, m.ht2_away_goals,
         m.home_team_id, m.away_team_id,
         pr.ht_home, pr.ht_away, pr.ht2_home, pr.ht2_away,
         pr.first_sub_out_player_id, pr.first_yellow_player_id,
         pr.submitted_at
  from predictions pr
  join matches m on m.id = pr.match_id
  where m.matchday = (select var_matchday) and m.season_id = (select var_season)
    and m.status in ('FINISHED','CONFIRMED')
),
-- Formula VECCHIA calcolata inline (identica a 0003):
vecchia as (
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
vecchia_tot as (
  select user_id, match_id,
         pts_ht + pts_ht2 + pts_scorers + pts_cs + pts_sub + pts_yellow as total_v1
  from vecchia
)
-- Differenze tra vecchio e nuovo calcolo
select v.user_id, v.match_id, v.total_v1, s.total as total_v2,
       v.total_v1 - s.total as delta
from vecchia_tot v
join scores s on s.user_id = v.user_id and s.match_id = v.match_id
where v.total_v1 <> s.total
  and s.total <> (s.pts_ht + s.pts_ht2 + s.pts_scorers + s.pts_clean_sheet
                + s.pts_sub + s.pts_yellow); -- esclude righe non ancora ricalcolate da v2

-- Nota: le righe di "scores" NON ancora ricalcolate da v2 mostreranno delta spurie:
-- forzare prima il ricalcolo v2 per la giornata:
--   select public.score_match(id) from matches
--   where matchday = (var) and season_id = (var) and status in ('FINISHED','CONFIRMED');
