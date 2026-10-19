-- =============================================================
-- FantaCalcio365 - 0008_cache_and_audit.sql
-- FASE 2: cache eventi provider, override manuale admin, audit trail.
-- Applicabile su database gia' popolato: solo ADD COLUMN / CREATE.
-- =============================================================

-- 1. Cache grezza delle risposte provider ----------------------
create table event_cache (
  provider_match_id text primary key,
  match_id uuid not null references matches(id) on delete cascade,
  fixture_payload jsonb not null,
  events_payload jsonb,
  fetched_at timestamptz not null default now(),
  source_updated_at timestamptz,
  fetch_status text not null default 'ok'   -- ok | provider_down | incomplete
);

-- RLS attiva ma senza policy: invisibile a utenti e chiavi anonime.
-- Solo service_role (bypass RLS) la scrive/legge.
alter table event_cache enable row level security;

-- 2. Override manuale su matches -------------------------------
alter table matches
  add column if not exists manual_override boolean not null default false,
  add column if not exists override_by uuid references auth.users(id),
  add column if not exists override_at timestamptz;

-- 3. Audit: colonne before/after sulla tabella esistente --------
alter table admin_audit_log
  add column if not exists old_value jsonb,
  add column if not exists new_value jsonb;

-- =============================================================
-- 4. Helper cache (solo service_role) ---------------------------
-- =============================================================

create or replace function public.cache_match_events(
  p_provider_match_id text,
  p_match_id uuid,
  p_fixture jsonb,
  p_events jsonb,
  p_status text,
  p_source_updated_at timestamptz default null
) returns void
language sql security definer
set search_path = public, pg_temp as $$
  insert into event_cache (provider_match_id, match_id, fixture_payload,
                           events_payload, fetched_at, source_updated_at, fetch_status)
  values (p_provider_match_id, p_match_id, p_fixture, p_events, now(),
          p_source_updated_at, p_status)
  on conflict (provider_match_id) do update set
    match_id = excluded.match_id,
    fixture_payload = excluded.fixture_payload,
    events_payload = excluded.events_payload,
    fetched_at = now(),
    source_updated_at = excluded.source_updated_at,
    fetch_status = excluded.fetch_status;
$$;

-- true se esiste una cache piu' recente di p_max_age secondi
create or replace function public.cache_is_fresh(
  p_provider_match_id text,
  p_max_age_seconds int
) returns boolean
language sql stable security definer
set search_path = public, pg_temp as $$
  select exists (
    select 1 from event_cache
    where provider_match_id = p_provider_match_id
      and fetch_status = 'ok'
      and fetched_at > now() - make_interval(secs => p_max_age_seconds)
  );
$$;

revoke all on function public.cache_match_events(text, uuid, jsonb, jsonb, text, timestamptz)
  from public, anon, authenticated;
revoke all on function public.cache_is_fresh(text, int)
  from public, anon, authenticated;
grant execute on function public.cache_match_events(text, uuid, jsonb, jsonb, text, timestamptz)
  to service_role;
grant execute on function public.cache_is_fresh(text, int) to service_role;

-- =============================================================
-- 5. score_match v2: upsert + audit aggregato -------------------
-- =============================================================

-- Sostituisce la versione di 0003. Cambi chiave:
--  * upsert (ON CONFLICT DO UPDATE ... WHERE total diverso) al posto di DELETE+INSERT
--  * UNA riga di audit per partita (non per utente), solo se almeno un totale e' cambiato
--  * ricerca del partita con lock di riga (FOR UPDATE) per concorrenza
create or replace function public.score_match(p_match_id uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  m record;
  v_sum_old numeric;
  v_sum_new numeric;
  v_changed int;
begin
  -- Lock di riga: nessun override/cron concorrente sulla stessa partita
  select * into m from matches where id = p_match_id for update;
  if m.id is null then raise exception 'Partita % inesistente', p_match_id; end if;
  if m.status not in ('FINISHED','CONFIRMED') then
    raise exception 'Partita % non terminata', p_match_id;
  end if;

  select coalesce(sum(total), 0), count(*) into v_sum_old, v_changed
  from scores where match_id = p_match_id;

  create temp table tmp_pred on commit drop as
    select pr.*, pr2.player_id, pr2.is_marked_scorer
    from predictions pr
    join prediction_players pr2 on pr2.prediction_id = pr.id
    where pr.match_id = p_match_id;

  insert into scores (user_id, match_id, season_id, matchday,
                      pts_ht, pts_ht2, pts_scorers, pts_clean_sheet,
                      pts_sub, pts_yellow, total, exact_ht, exact_ht2,
                      exact_scorers, first_submitted_at,
                      is_provisional, is_official)
  select
    p.user_id, p.match_id, m.season_id, m.matchday,
    case when p.ht_home = m.ht_home_goals and p.ht_away = m.ht_away_goals
          and p.ht2_home = m.ht2_home_goals and p.ht2_away = m.ht2_away_goals
         then 4 else 0 end,
    case when p.ht2_home = m.ht2_home_goals and p.ht2_away = m.ht2_away_goals
         then 6 else 0 end
    + case when p.ht_home = m.ht_home_goals and p.ht_away = m.ht_away_goals
            and p.ht2_home = m.ht2_home_goals and p.ht2_away = m.ht2_away_goals
           then 10 else 0 end,
    coalesce((
      select sum(ps.gol_bonus_pts * ps.goals)
      from tmp_pred t
      join player_match_stats ps on ps.match_id = p.match_id and ps.player_id = t.player_id
      where t.id = p.id and t.is_marked_scorer and ps.goals > 0
    ), 0),
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
    0,
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
  group by p.id, p.user_id, p.match_id
  on conflict (user_id, match_id) do update set
    pts_ht = excluded.pts_ht,
    pts_ht2 = excluded.pts_ht2,
    pts_scorers = excluded.pts_scorers,
    pts_clean_sheet = excluded.pts_clean_sheet,
    pts_sub = excluded.pts_sub,
    pts_yellow = excluded.pts_yellow,
    total = excluded.pts_ht + excluded.pts_ht2 + excluded.pts_scorers
          + excluded.pts_clean_sheet + excluded.pts_sub + excluded.pts_yellow,
    exact_ht = excluded.exact_ht,
    exact_ht2 = excluded.exact_ht2,
    exact_scorers = excluded.exact_scorers,
    first_submitted_at = excluded.first_submitted_at,
    is_provisional = excluded.is_provisional,
    is_official = excluded.is_official,
    corrected_at = case when scores.total is distinct from
      (excluded.pts_ht + excluded.pts_ht2 + excluded.pts_scorers
       + excluded.pts_clean_sheet + excluded.pts_sub + excluded.pts_yellow)
      then now() else scores.corrected_at end;

  update scores
  set total = pts_ht + pts_ht2 + pts_scorers + pts_clean_sheet + pts_sub + pts_yellow
  where match_id = p_match_id;

  select coalesce(sum(total), 0) into v_sum_new from scores where match_id = p_match_id;

  -- UNA riga di audit per partita, solo se qualcosa e' cambiato
  if v_sum_new is distinct from v_sum_old or v_changed <> (select count(*) from scores where match_id = p_match_id) then
    insert into admin_audit_log (actor_id, action, entity, entity_id, old_value, new_value)
    values (auth.uid(), 'SCORE_RECALC', 'match', p_match_id::text,
            jsonb_build_object('sum', v_sum_old, 'rows', v_changed),
            jsonb_build_object('sum', v_sum_new, 'rows',
                               (select count(*) from scores where match_id = p_match_id)));
  end if;
end $$;

-- =============================================================
-- 6. admin_override_match: correzione manuale admin -------------
-- =============================================================

create or replace function public.admin_override_match(
  p_provider_id text,
  p_result jsonb,
  p_events jsonb,
  p_reason text,
  p_actor uuid default null
) returns void
language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  v_match_id uuid;
  v_old jsonb;
  v_status text := p_result->>'status';
  ev jsonb;
  v_player uuid;
begin
  if not public.is_admin() then
    raise exception 'Solo gli amministratori possono correggere una partita';
  end if;
  if p_reason is null or length(trim(p_reason)) < 5 then
    raise exception 'Motivazione obbligatoria (min 5 caratteri)';
  end if;

  select id into v_match_id from matches where provider_id = p_provider_id for update;
  if v_match_id is null then raise exception 'Partita % non trovata', p_provider_id; end if;

  select jsonb_build_object(
    'status', status, 'ht', jsonb_build_array(ht_home_goals, ht_away_goals),
    'ht2', jsonb_build_array(ht2_home_goals, ht2_away_goals),
    'ft', jsonb_build_array(ft_home_goals, ft_away_goals),
    'events', (select coalesce(jsonb_agg(jsonb_build_object(
        'event_order', event_order, 'type', type,
        'player_id', player_id, 'related_player_id', related_player_id)), '[]')
      from match_events where match_id = matches.id)
  ) into v_old from matches where id = v_match_id;

  -- Validazione giocatori: tutti devono esistere
  for ev in select jsonb_array_elements(p_events) loop
    if ev->>'player' is not null then
      select id into v_player from players where provider_id = ev->>'player';
      if v_player is null then
        raise exception 'Giocatore % inesistente', ev->>'player';
      end if;
    end if;
  end loop;

  -- event_order univoco nell'insieme fornito
  if exists (
    select 1 from jsonb_array_elements(p_events) e(e)
    group by e->>'event_order'
    having count(*) > 1
  ) then
    raise exception 'event_order duplicati nel set eventi';
  end if;

  update matches set
    status = v_status,
    ht_home_goals = (p_result->>'ht_home')::int,
    ht_away_goals = (p_result->>'ht_away')::int,
    ht2_home_goals = (p_result->>'ht2_home')::int,
    ht2_away_goals = (p_result->>'ht2_away')::int,
    ft_home_goals = (p_result->>'ft_home')::int,
    ft_away_goals = (p_result->>'ft_away')::int,
    data_confirmed_at = case when v_status = 'CONFIRMED' then now() else data_confirmed_at end,
    -- protegge la correzione dal cron (§ cron-tasks salta manual_override = true)
    manual_override = true,
    override_by = coalesce(p_actor, auth.uid()),
    override_at = now()
  where id = v_match_id;

  -- Sostituzione completa del set eventi
  delete from match_events where match_id = v_match_id;
  for ev in select * from jsonb_array_elements(p_events) loop
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
      true
    );
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

  perform public.apply_official_correction(v_match_id, p_reason);

  insert into admin_audit_log (actor_id, action, entity, entity_id, old_value, new_value, payload)
  values (
    coalesce(p_actor, auth.uid()), 'ADMIN_OVERRIDE', 'match', v_match_id::text,
    v_old,
    jsonb_build_object(
      'status', v_status,
      'ht', jsonb_build_array((p_result->>'ht_home')::int, (p_result->>'ht_away')::int),
      'ht2', jsonb_build_array((p_result->>'ht2_home')::int, (p_result->>'ht2_away')::int),
      'ft', jsonb_build_array((p_result->>'ft_home')::int, (p_result->>'ft_away')::int),
      'events', p_events
    ),
    jsonb_build_object('reason', p_reason)
  );
end $$;

revoke all on function public.admin_override_match(text, jsonb, jsonb, text, uuid)
  from public, anon, authenticated;
grant execute on function public.admin_override_match(text, jsonb, jsonb, text, uuid) to service_role;

-- ingest_match_result v2: lock di riga + salto manual_override
create or replace function public.ingest_match_result(
  p_provider_id text, p_result jsonb
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_match_id uuid;
  v_status text := p_result->>'status';
  ev jsonb;
begin
  select id into v_match_id from matches where provider_id = p_provider_id for update;
  if v_match_id is null then raise exception 'Partita % non trovata', p_provider_id; end if;

  -- Le correzioni manuali dell'admin prevalgono sul provider
  if exists (select 1 from matches where id = v_match_id and manual_override) then
    return;
  end if;

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
