-- =============================================================
-- FantaCalcio365 - 0008_cache_and_audit.sql
-- FASE 2/3: cache eventi provider, override manuale admin, audit trail,
-- privilegi minimi sulle funzioni interne.
-- Applicabile su database gia' popolato: solo ADD COLUMN / CREATE /
-- REPLACE di funzioni. NON ancora applicata a nessun DB persistente.
-- =============================================================

-- =============================================================
-- 0. is_admin() v2: security definer, search_path fissato con pg_temp,
--    legge SOLO auth.uid() (nessun input esterno).
--    (sostituisce la versione di 0002 che non includeva pg_temp)
-- =============================================================
create or replace function public.is_admin()
returns boolean
language sql stable security definer
set search_path = public, pg_temp as $$
  select coalesce((select is_admin from profiles where id = auth.uid()), false);
$$;

-- =============================================================
-- 0-bis. Privilegi minimi sulle funzioni interne (definizione qui,
--        GRANT/REVOKE aggregati in fondo al file per leggibilita')
-- =============================================================

-- =============================================================
-- 1. Cache grezza delle risposte provider ----------------------
-- =============================================================
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

-- Audit APPEND-ONLY: nessun update/delete dai ruoli client
revoke update, delete on admin_audit_log from authenticated, anon;

-- is_admin NON modificabile dal client (colonna)
revoke update (is_admin) on profiles from authenticated;

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

-- =============================================================
-- 5. Funzione interna condivisa: inserimento eventi + stats.
--    USATA SIA DA ingest_match_result CHE DA admin_override_match,
--    cosi' gli stessi eventi producono sempre le stesse stats/punteggi.
--
--    REGOLE STATS (colonne di player_match_stats):
--      match_id, player_id, played_minutes, is_starting, goals,
--      yellow_cards, conceded_goals, gol_bonus_pts,
--      clean_sheet_bonus_pts, frozen_at
--    Questa funzione aggiorna SOLO: goals (mai per autogol!),
--    yellow_cards. NON tocca: played_minutes, is_starting,
--    conceded_goals, gol_bonus_pts, clean_sheet_bonus_pts, frozen_at
--    (bonus congelati dal modello §6; minuti/gol subiti da sync dedicata).
-- =============================================================
create or replace function public.upsert_events_from_json(
  p_match_id uuid,
  p_events jsonb
) returns void
language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  ev jsonb;
  v_player uuid;
  v_related uuid;
begin
  -- Validazione: giocatori devono esistere (evita FK sospese a runtime)
  for ev in select * from jsonb_array_elements(p_events) loop
    if ev->>'player' is not null then
      select id into v_player from players where provider_id = ev->>'player';
      if v_player is null then
        raise exception 'Giocatore % inesistente', ev->>'player';
      end if;
    end if;
    if ev->>'related_player' is not null then
      select id into v_related from players where provider_id = ev->>'related_player';
      if v_related is null then
        raise exception 'related_player % inesistente', ev->>'related_player';
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

  for ev in select * from jsonb_array_elements(p_events) loop
    insert into match_events (match_id, event_order, minute, type, player_id,
                              related_player_id, is_own_goal, is_penalty, is_official)
    values (
      p_match_id,
      (ev->>'event_order')::int,
      (ev->>'minute')::int,
      ev->>'type',
      (select id from players where provider_id = ev->>'player'),
      (select id from players where provider_id = ev->>'related_player'),
      coalesce((ev->>'own_goal')::boolean, false),
      coalesce((ev->>'penalty')::boolean, false),
      true
    );

    -- Presenza in campo: qualsiasi evento di presenza (GOAL valido, giallo,
    -- SUB_OUT/SUB_IN) e' prova di campo → evidenza played_minutes.
    -- APPROSSIMAZIONE DOCUMENTATA: 90 minuti fintanto che non esiste la sync
    -- formazioni; il bonus marcatore resta legato a goals > 0.
    if ev->>'player' is not null and ev->>'type' in ('GOAL','YELLOW','SUB_OUT','SUB_IN')
       and coalesce((ev->>'own_goal')::boolean, false) = false then
      insert into player_match_stats (match_id, player_id, played_minutes)
      values (p_match_id, (select id from players where provider_id = ev->>'player'), 90)
      on conflict (match_id, player_id)
      do update set played_minutes = greatest(player_match_stats.played_minutes, 90);
    end if;

    -- GOAL: l'autogol NON assegna mai goal allo stat del giocatore
    -- (il bonus marcatore deriva da goals > 0, §5)
    if ev->>'type' = 'GOAL' and ev->>'player' is not null
       and coalesce((ev->>'own_goal')::boolean, false) = false then
      insert into player_match_stats (match_id, player_id, goals)
      values (p_match_id, (select id from players where provider_id = ev->>'player'), 1)
      on conflict (match_id, player_id) do update set goals = player_match_stats.goals + 1;
    elsif ev->>'type' = 'YELLOW' and ev->>'player' is not null then
      insert into player_match_stats (match_id, player_id, yellow_cards)
      values (p_match_id, (select id from players where provider_id = ev->>'player'), 1)
      on conflict (match_id, player_id) do update set yellow_cards = player_match_stats.yellow_cards + 1;
    end if;
  end loop;
end $$;

-- =============================================================
-- 6. score_match v2: upsert + audit aggregato -------------------
-- =============================================================

create or replace function public.score_match(p_match_id uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  m record;
  v_sum_old numeric;
  v_sum_new numeric;
  v_rows_old int;
begin
  -- Lock di riga: nessun override/cron concorrente sulla stessa partita
  select * into m from matches where id = p_match_id for update;
  if m.id is null then raise exception 'Partita % inesistente', p_match_id; end if;
  if m.status not in ('FINISHED','CONFIRMED') then
    raise exception 'Partita % non terminata', p_match_id;
  end if;

  -- conceded_goals calcolato DAL RISULTATO CORRENTE, per entrambi i percorsi
  -- (ingest e override): la casa subisce ft_away, l'ospite subisce ft_home.
  -- Idempotente: il ricalcolo riparte sempre dal risultato ufficiale.
  update player_match_stats ps
  set conceded_goals = case when pl.team_id = m.home_team_id
                            then m.ft_away_goals else m.ft_home_goals end
  from players pl
  where pl.id = ps.player_id and ps.match_id = m.id;

  select coalesce(sum(total), 0), count(*) into v_sum_old, v_rows_old
  from scores where match_id = p_match_id;

  drop table if exists tmp_pred;
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
  group by p.id, p.user_id, p.match_id, p.ht_home, p.ht_away, p.ht2_home, p.ht2_away,
           p.first_sub_out_player_id, p.first_yellow_player_id, p.submitted_at
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

  -- UNA riga di audit per partita, solo se qualcosa e' cambiato.
  -- Formato entity_id: uuid interno della partita (uniforme con
  -- ADMIN_OVERRIDE); provider_id incluso nei valori.
  if v_sum_new is distinct from v_sum_old
     or v_rows_old <> (select count(*) from scores where match_id = p_match_id) then
    insert into admin_audit_log (actor_id, action, entity, entity_id, old_value, new_value)
    values (auth.uid(), 'SCORE_RECALC', 'match', p_match_id::text,
            jsonb_build_object('match_provider_id', m.provider_id,
                               'sum', v_sum_old, 'rows', v_rows_old),
            jsonb_build_object('match_provider_id', m.provider_id,
                               'sum', v_sum_new, 'rows',
                               (select count(*) from scores where match_id = p_match_id)));
  end if;
end $$;

-- Primo giocatore che ESCE in una sostituzione (§8)
create or replace function public.first_sub_out(p_match_id uuid)
returns uuid language sql stable security definer set search_path = public, pg_temp as $$
  select player_id from match_events
  where match_id = p_match_id and type = 'SUB_OUT' and player_id is not null
  order by event_order asc
  limit 1;
$$;

-- Primo ammonito IN CAMPO (§8)
create or replace function public.first_yellow(p_match_id uuid)
returns uuid language sql stable security definer set search_path = public, pg_temp as $$
  select player_id from match_events
  where match_id = p_match_id and type = 'YELLOW' and player_id is not null
  order by event_order asc
  limit 1;
$$;

-- Correzione ufficiale: ricalcolo + log dei delta (§11)
create or replace function public.apply_official_correction(
  p_match_id uuid, p_reason text, p_source_event uuid default null
) returns void
language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  v_old_sum numeric;
  v_new_sum numeric;
begin
  select coalesce(sum(total), 0) into v_old_sum from scores where match_id = p_match_id;

  drop table if exists tmp_old_scores;
  create temp table tmp_old_scores as
    select user_id, total from scores where match_id = p_match_id;

  perform public.score_match(p_match_id);

  select coalesce(sum(total), 0) into v_new_sum from scores where match_id = p_match_id;

  if v_new_sum is distinct from v_old_sum then
    insert into score_corrections (match_id, user_id, old_total, new_total, reason, source_event_id)
    select p_match_id, o.user_id, o.total, s.total, p_reason, p_source_event
    from tmp_old_scores o join scores s
      on s.user_id = o.user_id
    where s.match_id = p_match_id and o.total <> s.total;
  end if;
end $$;

-- =============================================================
-- 7. ingest_match_result v3: lock + check override PRIMA,
--    validazioni di coerenza, helper condiviso -------------------
-- =============================================================

create or replace function public.ingest_match_result(
  p_provider_id text, p_result jsonb
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_match_id uuid;
  v_manual boolean;
  v_status text := p_result->>'status';
  v_ht int; v_away int; v_h2 int; v_a2 int; v_fh int; v_fa int;
begin
  -- Sequenza voluta: PRIMA il lock di riga, POI la lettura di manual_override
  select id, manual_override into v_match_id, v_manual
  from matches where provider_id = p_provider_id for update;
  if v_match_id is null then raise exception 'Partita % non trovata', p_provider_id; end if;

  -- Le correzioni manuali dell'admin prevalgono sul provider
  if v_manual then return; end if;

  -- Chiavi obbligatorie e in range (nessun null implicito)
  v_ht := (p_result->>'ht_home')::int;
  v_away := (p_result->>'ht_away')::int;
  v_h2 := (p_result->>'ht2_home')::int;
  v_a2 := (p_result->>'ht2_away')::int;
  v_fh := (p_result->>'ft_home')::int;
  v_fa := (p_result->>'ft_away')::int;
  if v_ht is null or v_away is null or v_h2 is null or v_a2 is null
     or v_fh is null or v_fa is null
     or v_ht < 0 or v_away < 0 or v_h2 < 0 or v_a2 < 0
     or v_fh < 0 or v_fa < 0 or v_fh > 20 or v_fa > 20 then
    raise exception 'Risultato incompleto o fuori range per %', p_provider_id;
  end if;

  -- Coerenza: ft = ht + ht2 (per entrambe le squadre)
  if v_fh <> v_ht + v_h2 or v_fa <> v_away + v_a2 then
    raise exception 'Risultato incoerente per %: ft <> ht + ht2', p_provider_id;
  end if;

  -- Coerenza eventi: numero gol (autogol INCLUSI) = ft
  if (select count(*) from jsonb_array_elements(p_result->'events')
      where value->>'type' = 'GOAL') <> (v_fh + v_fa) then
    raise exception 'Numero eventi GOAL incoerente col risultato per %', p_provider_id;
  end if;

  update matches set
    status = v_status,
    ht_home_goals = v_ht, ht_away_goals = v_away,
    ht2_home_goals = v_h2, ht2_away_goals = v_a2,
    ft_home_goals = v_fh, ft_away_goals = v_fa,
    data_confirmed_at = case when v_status = 'CONFIRMED' then now() else data_confirmed_at end
  where id = v_match_id;

  -- Sostituzione completa del set eventi/stats (helper condiviso)
  delete from match_events where match_id = v_match_id;
  update player_match_stats set goals = 0, yellow_cards = 0 where match_id = v_match_id;
  perform public.upsert_events_from_json(v_match_id, p_result->'events');

  if v_status in ('FINISHED','CONFIRMED') then
    perform public.score_match(v_match_id);
  end if;
end $$;

-- =============================================================
-- 8. admin_override_match: correzione manuale admin -------------
-- =============================================================

create or replace function public.admin_override_match(
  p_provider_id text,
  p_result jsonb,
  p_events jsonb,
  p_reason text
) returns void
language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  v_match_id uuid;
  v_old jsonb;
  v_status text := p_result->>'status';
  v_ht int; v_away int; v_h2 int; v_a2 int; v_fh int; v_fa int;
begin
  -- L'attore e' SEMPRE auth.uid() (il JWT con cui la RPC viene chiamata)
  if not public.is_admin() then
    raise exception 'Solo gli amministratori possono correggere una partita';
  end if;
  if auth.uid() is null then
    raise exception 'Chiamata senza JWT valido: attore non identificabile';
  end if;
  if p_reason is null or length(trim(p_reason)) < 5 then
    raise exception 'Motivazione obbligatoria (min 5 caratteri)';
  end if;

  select id into v_match_id from matches where provider_id = p_provider_id for update;
  if v_match_id is null then raise exception 'Partita % non trovata', p_provider_id; end if;

  v_ht := (p_result->>'ht_home')::int;
  v_away := (p_result->>'ht_away')::int;
  v_h2 := (p_result->>'ht2_home')::int;
  v_a2 := (p_result->>'ht2_away')::int;
  v_fh := (p_result->>'ft_home')::int;
  v_fa := (p_result->>'ft_away')::int;
  if v_ht is null or v_away is null or v_h2 is null or v_a2 is null
     or v_fh is null or v_fa is null
     or v_ht < 0 or v_away < 0 or v_h2 < 0 or v_a2 < 0
     or v_fh < 0 or v_fa < 0 or v_fh > 20 or v_fa > 20 then
    raise exception 'Risultato incompleto o fuori range';
  end if;
  if v_fh <> v_ht + v_h2 or v_fa <> v_away + v_a2 then
    raise exception 'Risultato incoerente: ft <> ht + ht2';
  end if;
  if (select count(*) from jsonb_array_elements(p_events)
      where value->>'type' = 'GOAL') <> (v_fh + v_fa) then
    raise exception 'Numero eventi GOAL incoerente col risultato';
  end if;

  select jsonb_build_object(
    'match_provider_id', provider_id,
    'status', status, 'ht', jsonb_build_array(ht_home_goals, ht_away_goals),
    'ht2', jsonb_build_array(ht2_home_goals, ht2_away_goals),
    'ft', jsonb_build_array(ft_home_goals, ft_away_goals),
    'events', (select coalesce(jsonb_agg(jsonb_build_object(
        'event_order', event_order, 'type', type,
        'player_id', player_id, 'related_player_id', related_player_id)), '[]')
      from match_events where match_id = matches.id)
  ) into v_old from matches where id = v_match_id;

  update matches set
    status = v_status,
    ht_home_goals = v_ht, ht_away_goals = v_away,
    ht2_home_goals = v_h2, ht2_away_goals = v_a2,
    ft_home_goals = v_fh, ft_away_goals = v_fa,
    data_confirmed_at = case when v_status = 'CONFIRMED' then now() else data_confirmed_at end,
    manual_override = true,
    override_by = auth.uid(),
    override_at = now()
  where id = v_match_id;

  -- Sostituzione completa del set eventi/stats (helper condiviso)
  delete from match_events where match_id = v_match_id;
  update player_match_stats set goals = 0, yellow_cards = 0 where match_id = v_match_id;
  perform public.upsert_events_from_json(v_match_id, p_events);

  perform public.apply_official_correction(v_match_id, p_reason);

  insert into admin_audit_log (actor_id, action, entity, entity_id, old_value, new_value, payload)
  values (
    auth.uid(), 'ADMIN_OVERRIDE', 'match', v_match_id::text,
    v_old,
    jsonb_build_object(
      'match_provider_id', p_provider_id,
      'status', v_status,
      'ht', jsonb_build_array(v_ht, v_away),
      'ht2', jsonb_build_array(v_h2, v_a2),
      'ft', jsonb_build_array(v_fh, v_fa),
      'events', p_events
    ),
    jsonb_build_object('reason', p_reason)
  );
end $$;

-- =============================================================
-- 9. admin_release_override: riporta la partita al controllo del
--    cron ( stessi controlli, con audit) ------------------------
-- =============================================================

create or replace function public.admin_release_override(
  p_provider_id text,
  p_reason text
) returns void
language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  v_match_id uuid;
  v_old jsonb;
begin
  if not public.is_admin() then
    raise exception 'Solo gli amministratori possono rilasciare un override';
  end if;
  if auth.uid() is null then
    raise exception 'Chiamata senza JWT valido: attore non identificabile';
  end if;
  if p_reason is null or length(trim(p_reason)) < 5 then
    raise exception 'Motivazione obbligatoria (min 5 caratteri)';
  end if;

  select id into v_match_id from matches where provider_id = p_provider_id for update;
  if v_match_id is null then raise exception 'Partita % non trovata', p_provider_id; end if;
  if not exists (select 1 from matches where id = v_match_id and manual_override) then
    raise exception 'Nessun override attivo sulla partita %', p_provider_id;
  end if;

  select jsonb_build_object('match_provider_id', provider_id, 'manual_override', manual_override,
    'override_by', override_by, 'override_at', override_at)
  into v_old from matches where id = v_match_id;

  update matches set
    manual_override = false,
    override_by = null,
    override_at = null
  where id = v_match_id;

  insert into admin_audit_log (actor_id, action, entity, entity_id, old_value, new_value, payload)
  values (
    auth.uid(), 'ADMIN_RELEASE_OVERRIDE', 'match', v_match_id::text,
    v_old,
    jsonb_build_object('match_provider_id', p_provider_id,
                       'manual_override', false, 'override_by', null, 'override_at', null),
    jsonb_build_object('reason', p_reason)
  );
end $$;

-- =============================================================
-- 10. Privilegi aggregati ---------------------------------------
-- =============================================================

-- Cache: SOLO service_role
revoke all on function public.cache_match_events(text, uuid, jsonb, jsonb, text, timestamptz)
  from public, anon, authenticated;
revoke all on function public.cache_is_fresh(text, int)
  from public, anon, authenticated;
grant execute on function public.cache_match_events(text, uuid, jsonb, jsonb, text, timestamptz)
  to service_role;
grant execute on function public.cache_is_fresh(text, int) to service_role;

-- Funzioni interne di scoring/sync: SOLO service_role
revoke all on function public.score_match(uuid)
  from public, anon, authenticated;
revoke all on function public.ingest_match_result(text, jsonb)
  from public, anon, authenticated;
revoke all on function public.apply_official_correction(uuid, text, uuid)
  from public, anon, authenticated;
revoke all on function public.first_sub_out(uuid) from public, anon, authenticated;
revoke all on function public.first_yellow(uuid) from public, anon, authenticated;
revoke all on function public.upsert_events_from_json(uuid, jsonb)
  from public, anon, authenticated;
revoke all on function public.freeze_matchday_bonuses(uuid, int)
  from public, anon, authenticated;
revoke all on function public.lock_matchday(uuid, int) from public, anon, authenticated;
revoke all on function public.lock_due_matchdays() from public, anon, authenticated;
revoke all on function public.validate_prediction()
  from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;

grant execute on function public.score_match(uuid) to service_role;
grant execute on function public.ingest_match_result(text, jsonb) to service_role;
grant execute on function public.apply_official_correction(uuid, text, uuid) to service_role;
grant execute on function public.first_sub_out(uuid) to service_role;
grant execute on function public.first_yellow(uuid) to service_role;
grant execute on function public.upsert_events_from_json(uuid, jsonb) to service_role;
grant execute on function public.freeze_matchday_bonuses(uuid, int) to service_role;
grant execute on function public.lock_matchday(uuid, int) to service_role;
grant execute on function public.lock_due_matchdays() to service_role;

-- Override/release: EXECUTE a authenticated (guard is_admin() interna)
revoke all on function public.admin_override_match(text, jsonb, jsonb, text)
  from public, anon;
revoke all on function public.admin_release_override(text, text)
  from public, anon;
grant execute on function public.admin_override_match(text, jsonb, jsonb, text) to authenticated;
grant execute on function public.admin_release_override(text, text) to authenticated;

-- is_admin e helper gruppi: usati dalle policy RLS → servono a authenticated
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_group_member(uuid) to authenticated;
grant execute on function public.is_group_owner(uuid) to authenticated;
