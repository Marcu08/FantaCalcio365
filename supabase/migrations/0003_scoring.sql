-- =============================================================
-- FantaCalcio365 - 0003_scoring.sql
-- Motore di scoring server-side. REGOLAMENTO APPROVATO:
--   * Modalita' combinata prevale: 1T esatto (4) + 2T esatto (6) + combo (10) = 20
--   * Nessun punto per 1T o 2T da soli fuori dal combo... tranne:
--     - 2T esatto da solo = 6 punti (regola §4 approvata)
--     - 1T esatto da solo = 4 punti SOLO se abbinato al 2T esatto (combo)
--   * Nessuna regola speciale per 1T 0-0 (scelta A1 approvata)
--   * Bonus gol: solo giocatori is_marked_scorer, per OGNI rete, range 5..15
--   * Porta inviolata: GK/DF che hanno giocato, 0 gol subiti; somma al bonus gol;
--     valore del modello congelato (tetto 10 applicato ai soli GK)
--   * Primo sostituto (chi ESCE) = 2 punti; primo ammonito = 2 punti
-- =============================================================

-- Congela i bonus del modello per tutte le partite di una giornata.
-- Chiamata SOLO da service_role subito prima del blocco (§6).
create or replace function public.freeze_matchday_bonuses(p_season_id uuid, p_matchday int)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_locked timestamptz;
begin
  select min(kickoff_at) into v_locked
  from matches where season_id = p_season_id and matchday = p_matchday;

  if v_locked is null then
    raise exception 'Nessuna partita per la giornata %', p_matchday;
  end if;

  -- Il congelamento avviene al momento del blocco; mai retroattivamente
  update player_match_stats ps
  set frozen_at = now()
  from matches m
  where m.id = ps.match_id
    and m.season_id = p_season_id
    and m.matchday = p_matchday
    and ps.frozen_at is null;

  -- Audit
  insert into admin_audit_log (actor_id, action, entity, entity_id, payload)
  values (auth.uid(), 'FREEZE_BONUSES', 'matchday', p_matchday::text,
          jsonb_build_object('season', p_season_id, 'locked_at', v_locked));
end $$;

-- Calcola i punteggi di una partita per tutti i pronostici.
-- Eseguita al passaggio a FINISHED e rieseguita (idempotente) alle correzioni.
create or replace function public.score_match(p_match_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  m record;
begin
  select * into m from matches where id = p_match_id;
  if m.id is null then raise exception 'Partita % inesistente', p_match_id; end if;
  if m.status not in ('FINISHED','CONFIRMED') then
    raise exception 'Partita % non terminata', p_match_id;
  end if;

  create temp table tmp_pred on commit drop as
    select pr.*, pr2.player_id, pr2.is_marked_scorer
    from predictions pr
    join prediction_players pr2 on pr2.prediction_id = pr.id
    where pr.match_id = p_match_id;

  delete from scores where match_id = p_match_id;

  insert into scores (user_id, match_id, season_id, matchday,
                      pts_ht, pts_ht2, pts_scorers, pts_clean_sheet,
                      pts_sub, pts_yellow, total, exact_ht, exact_ht2,
                      exact_scorers, first_submitted_at,
                      is_provisional, is_official)
  select
    p.user_id, p.match_id, m.season_id, m.matchday,
    -- 1T esatto conta solo nel combo (A1): valga 4 quando anche il 2T e' esatto
    case when p.ht_home = m.ht_home_goals and p.ht_away = m.ht_away_goals
          and p.ht2_home = m.ht2_home_goals and p.ht2_away = m.ht2_away_goals
         then 4 else 0 end,
    -- 2T esatto: 6 sempre (anche senza combo)
    case when p.ht2_home = m.ht2_home_goals and p.ht2_away = m.ht2_away_goals
         then 6 else 0 end
    -- Bonus combo se entrambi esatti: +10 qui (4 del 1T gia' sopra)
    + case when p.ht_home = m.ht_home_goals and p.ht_away = m.ht_away_goals
            and p.ht2_home = m.ht2_home_goals and p.ht2_away = m.ht2_away_goals
           then 10 else 0 end,
    -- Bonus gol: solo marcatori dichiarati, una volta per ogni rete
    coalesce((
      select sum(ps.gol_bonus_pts * ps.goals)
      from tmp_pred t
      join player_match_stats ps on ps.match_id = p.match_id and ps.player_id = t.player_id
      where t.id = p.id and t.is_marked_scorer and ps.goals > 0
    ), 0),
    -- Porta inviolata: GK/DF scesi in campo, 0 gol subiti; valore congelato
    coalesce((
      select sum(ps.clean_sheet_bonus_pts)
      from tmp_pred t
      join player_match_stats ps on ps.match_id = p.match_id and ps.player_id = t.player_id
      join players pl on pl.id = t.player_id
      where t.id = p.id and ps.played_minutes > 0 and ps.conceded_goals = 0
        and pl.position in ('GK','DF')
    ), 0),
    case when p.first_sub_out_player_id = public.first_sub_out(p_match_id) then 2 else 0 end,
    case when p.first_yellow_player_id = public.first_yellow(p_match_id) then 2 else 0 end,
    0, -- total, aggiornato subito dopo
    (p.ht_home = m.ht_home_goals and p.ht_away = m.ht_away_goals
      and p.ht2_home = m.ht2_home_goals and p.ht2_away = m.ht2_away_goals),
    (p.ht2_home = m.ht2_home_goals and p.ht2_away = m.ht2_away_goals),
    coalesce((
      select count(*)
      from tmp_pred t
      join player_match_stats ps on ps.match_id = p.match_id and ps.player_id = t.player_id
      where t.id = p.id and t.is_marked_scorer and ps.goals > 0
    ), 0),
    p.submitted_at,
    m.status = 'FINISHED',
    m.status = 'CONFIRMED'
  from tmp_pred p
  where p.match_id = p_match_id
  group by p.id, p.user_id, p.match_id;

  -- total = somma delle componenti + bonus porta inviolata incluso
  update scores
  set total = pts_ht + pts_ht2 + pts_scorers + pts_clean_sheet + pts_sub + pts_yellow
  where match_id = p_match_id;

  -- Log correzione se la partita era gia' stata punteggiata
  if exists (select 1 from score_corrections where match_id = p_match_id
             group by match_id, user_id having count(*) > 0) then
    null; -- le righe di correzione vengono scritte dal caller con i delta
  end if;
end $$;

-- Primo giocatore che ESCE in una sostituzione (§8): ordinamento
-- autorevole event_order; parita' risolta con la prima occorrenza.
create or replace function public.first_sub_out(p_match_id uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select player_id from match_events
  where match_id = p_match_id and type = 'SUB_OUT' and player_id is not null
  order by event_order asc
  limit 1;
$$;

-- Primo ammonito IN CAMPO (§8)
create or replace function public.first_yellow(p_match_id uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select player_id from match_events
  where match_id = p_match_id and type = 'YELLOW' and player_id is not null
  order by event_order asc
  limit 1;
$$;

-- Ricalcolo dopo correzione ufficiale (§11): registra il delta
create or replace function public.apply_official_correction(
  p_match_id uuid, p_reason text, p_source_event uuid default null
) returns void language plpgsql security definer set search_path = public as $$
declare
  changed record;
begin
  -- Snapshot dei totali prima del ricalcolo
  create temp table tmp_old on commit drop as
    select user_id, total from scores where match_id = p_match_id;

  perform public.score_match(p_match_id);

  insert into score_corrections (match_id, user_id, old_total, new_total, reason, source_event_id)
  select p_match_id, o.user_id, o.total, n.total, p_reason, p_source_event
  from tmp_old o join scores n on n.match_id = p_match_id and n.user_id = o.user_id
  where o.total <> n.total;
end $$;

-- Validazione schedina: esattamente 4 giocatori, >=1 casa, >=1 ospite,
-- almeno 1 marcatore dichiarato (§5, decisione approvata)
create or replace function public.validate_prediction()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  n int; n_home int; n_away int; n_scorers int;
  v_match_id uuid;
  v_home uuid; v_away uuid;
begin
  v_match_id := new.match_id;
  select home_team_id, away_team_id into v_home, v_away
  from matches where id = v_match_id;

  select count(*),
         count(*) filter (where pl.team_id = v_home),
         count(*) filter (where pl.team_id = v_away),
         count(*) filter (where pp.is_marked_scorer)
  into n, n_home, n_away, n_scorers
  from prediction_players pp join players pl on pl.id = pp.player_id
  where pp.prediction_id = new.id;

  if n <> 4 then
    raise exception 'La schedina richiede esattamente 4 giocatori (trovati %)', n;
  end if;
  if n_home < 1 then raise exception 'Almeno 1 giocatore della squadra di casa'; end if;
  if n_away < 1 then raise exception 'Almeno 1 giocatore della squadra ospite'; end if;
  if n_scorers < 1 then raise exception 'Dichiarare almeno 1 marcatore'; end if;
  return new;
end $$;

create constraint trigger trg_validate_prediction
  after insert on predictions
  deferrable initially deferred
  for each row execute function public.validate_prediction();
