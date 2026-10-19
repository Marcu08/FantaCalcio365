-- =============================================================
-- FantaCalcio365 - 0004_admin.sql
-- Operazioni riservate (service_role / Edge Functions): blocco
-- giornata, ingestione risultati, correzioni ufficiali (§9, §11).
-- =============================================================

-- Blocca la giornata: locked_at = kickoff della prima gara (§9).
-- Idempotente: se gia' bloccata non fa nulla (mai riaperture).
create or replace function public.lock_matchday(p_season_id uuid, p_matchday int)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_locked timestamptz;
begin
  select min(kickoff_at) into v_locked
  from matches
  where season_id = p_season_id and matchday = p_matchday and status <> 'CANCELLED';

  update matches
  set locked_at = v_locked
  where season_id = p_season_id and matchday = p_matchday
    and locked_at is null;

  perform public.freeze_matchday_bonuses(p_season_id, p_matchday);
end $$;

-- Ingestione risultato + eventi dal provider (chiamata da Edge Function).
-- match_data: jsonb con ht/ft goals e array eventi ordinati per event_order.
create or replace function public.ingest_match_result(
  p_provider_id text, p_result jsonb
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_match_id uuid;
  v_status text := p_result->>'status';
  ev jsonb;
begin
  select id into v_match_id from matches where provider_id = p_provider_id;
  if v_match_id is null then raise exception 'Partita % non trovata', p_provider_id; end if;

  update matches set
    status = v_status,
    ht_home_goals = (p_result->>'ht_home')::int,
    ht_away_goals = (p_result->>'ht_away')::int,
    ht2_home_goals = (p_result->>'ht2_home')::int,
    ht2_away_goals = (p_result->>'ht2_away')::int,
    ft_home_goals = (p_result->>'ft_home')::int,
    ft_away_goals = (p_result->>'ft_away')::int,
    data_confirmed_at = case when v_status = 'CONFIRMED' then now() else data_confirmed_at end
  where id = v_match_id;

  -- Eventi: upsert anti-duplicato su (match_id, event_order, type)
  for ev in select * from jsonb_array_elements(p_result->'events')
  loop
    insert into match_events (match_id, event_order, minute, type, player_id,
                              related_player_id, is_own_goal, is_penalty, is_official)
    values (
      v_match_id,
      (ev->>'event_order')::int,
      (ev->>'minute')::int,
      ev->>'type',
      (select id from players where provider_id = ev->>'player'),
      (select id from players where provider_id = ev->>'related_player'),
      coalesce((ev->>'own_goal')::boolean, false),
      coalesce((ev->>'penalty')::boolean, false),
      v_status = 'CONFIRMED'
    )
    on conflict (match_id, event_order, type) do update set
      minute = excluded.minute,
      player_id = excluded.player_id,
      is_official = excluded.is_official;

    -- Aggiorna statistiche individuali
    if ev->>'type' = 'GOAL' and ev->>'player' is not null then
      insert into player_match_stats (match_id, player_id, goals)
      values (v_match_id, (select id from players where provider_id = ev->>'player'), 1)
      on conflict (match_id, player_id) do update set goals = player_match_stats.goals + 1;
    elsif ev->>'type' = 'YELLOW' and ev->>'player' is not null then
      insert into player_match_stats (match_id, player_id, yellow_cards)
      values (v_match_id, (select id from players where provider_id = ev->>'player'), 1)
      on conflict (match_id, player_id) do update set yellow_cards = player_match_stats.yellow_cards + 1;
    end if;
  end loop;

  if v_status in ('FINISHED','CONFIRMED') then
    perform public.score_match(v_match_id);
  end if;
end $$;
