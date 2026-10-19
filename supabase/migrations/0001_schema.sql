-- =============================================================
-- FantaCalcio365 - 0001_schema.sql
-- Schema tabelle principali. Tutte le scritture dei dati ufficiali
-- avvengono solo tramite service_role (backend / Edge Functions).
-- =============================================================

create extension if not exists "uuid-ossp";

-- Stagioni -----------------------------------------------------
create table seasons (
  id uuid primary key default uuid_generate_v4(),
  name text not null unique,           -- es. 'Serie A 2026/27'
  current_matchday int not null default 1,
  created_at timestamptz not null default now()
);

create table teams (
  id uuid primary key default uuid_generate_v4(),
  provider_id text not null unique,    -- id nel provider calcistico
  name text not null,
  short_name text not null,
  logo_url text
);

create table players (
  id uuid primary key default uuid_generate_v4(),
  team_id uuid not null references teams(id) on delete cascade,
  provider_id text not null unique,
  name text not null,
  -- Classificazione ufficiale del provider; fonte univoca del ruolo (decisione A7)
  position text not null check (position in ('GK','DF','MF','FW')),
  is_active boolean not null default true
);
create index players_team_idx on players(team_id);

-- Partite ------------------------------------------------------
create table matches (
  id uuid primary key default uuid_generate_v4(),
  season_id uuid not null references seasons(id),
  matchday int not null,
  provider_id text not null unique,
  home_team_id uuid not null references teams(id),
  away_team_id uuid not null references teams(id),
  kickoff_at timestamptz not null,
  -- SCHEDULED | LIVE | FINISHED (provvisorio) | CONFIRMED (ufficiale) | POSTPONED | CANCELLED
  status text not null default 'SCHEDULED',
  ht_home_goals int, ht_away_goals int,          -- primo tempo
  ht2_home_goals int, ht2_away_goals int,        -- solo gol seconda frazione
  ft_home_goals int, ft_away_goals int,
  locked_at timestamptz,                         -- inizio 1a gara della giornata
  data_confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (season_id, matchday, home_team_id)
);
create index matches_matchday_idx on matches(season_id, matchday);

-- Eventi ufficiali (dopo congelamento non si toccano, solo correzioni loggate)
create table match_events (
  id uuid primary key default uuid_generate_v4(),
  match_id uuid not null references matches(id) on delete cascade,
  event_order int not null,            -- ordinamento autorevole del provider (decisione A6)
  minute int,
  extra_minute int,
  type text not null check (type in ('GOAL','YELLOW','RED','SUB_OUT','SUB_IN')),
  player_id uuid references players(id),
  related_player_id uuid references players(id), -- SUB: nuovo entrato
  is_own_goal boolean not null default false,
  is_penalty boolean not null default false,
  is_official boolean not null default false,    -- conferma ufficiale provider
  unique (match_id, event_order, type)           -- anti-duplicazione (§11)
);
create index match_events_match_idx on match_events(match_id);

-- Statistiche individuali con bonus CONGELATI ------------------
create table player_match_stats (
  match_id uuid not null references matches(id) on delete cascade,
  player_id uuid not null references players(id) on delete cascade,
  played_minutes int not null default 0,
  is_starting boolean not null default false,
  goals int not null default 0,
  yellow_cards int not null default 0,
  conceded_goals int not null default 0,
  -- Bonus calcolati dal modello e congelati PRIMA del blocco (§6, §7)
  gol_bonus_pts numeric not null default 0,        -- per rete, range 5..15
  clean_sheet_bonus_pts numeric not null default 0,-- 0 se non applicabile
  frozen_at timestamptz,
  primary key (match_id, player_id)
);

-- Pronostici ---------------------------------------------------
create table predictions (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  match_id uuid not null references matches(id) on delete cascade,
  ht_home int not null check (ht_home between 0 and 9),
  ht_away int not null check (ht_away between 0 and 9),
  ht2_home int not null check (ht2_home between 0 and 9),  -- solo gol 2T (§4)
  ht2_away int not null check (ht2_away between 0 and 9),
  first_sub_out_player_id uuid references players(id),     -- primo che ESCE (§8)
  first_yellow_player_id uuid references players(id),      -- primo ammonito (§8)
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, match_id)
);

-- Selezione dei 4 giocatori: ogni riga è un giocatore scelto,
-- is_marked_scorer = dichiarazione esplicita del marcatore (§5)
create table prediction_players (
  prediction_id uuid not null references predictions(id) on delete cascade,
  player_id uuid not null references players(id),
  is_marked_scorer boolean not null default false,
  primary key (prediction_id, player_id)
);

-- Punteggi calcolati dal server -------------------------------
create table scores (
  user_id uuid not null references auth.users(id) on delete cascade,
  match_id uuid not null references matches(id) on delete cascade,
  season_id uuid not null references seasons(id),
  matchday int not null,
  pts_ht int not null default 0,          -- 1T esatto nel combo
  pts_ht2 int not null default 0,         -- 2T esatto + bonus combo
  pts_scorers numeric not null default 0, -- bonus gol dichiarati
  pts_clean_sheet numeric not null default 0,
  pts_sub int not null default 0,
  pts_yellow int not null default 0,
  total numeric not null default 0,
  exact_ht boolean not null default false,
  exact_ht2 boolean not null default false,
  exact_scorers int not null default 0,   -- n. marcatori esatti (tiebreak)
  first_submitted_at timestamptz,         -- per tiebreak orario (A4)
  is_provisional boolean not null default true,
  is_official boolean not null default false,
  corrected_at timestamptz,
  primary key (user_id, match_id)
);
create index scores_season_idx on scores(season_id, user_id);
create index scores_user_idx on scores(user_id, matchday);

-- Gruppi privati ----------------------------------------------
create table groups (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  owner_id uuid not null references auth.users(id),
  invite_code text not null unique default encode(gen_random_bytes(4),'hex'),
  created_at timestamptz not null default now()
);

create table group_members (
  group_id uuid not null references groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

-- Audit e correzioni (§11, §12) --------------------------------
create table admin_audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id),
  action text not null,
  entity text not null,
  entity_id text,
  payload jsonb,
  created_at timestamptz not null default now()
);

create table score_corrections (
  id bigint generated always as identity primary key,
  match_id uuid not null references matches(id),
  user_id uuid not null references auth.users(id),
  old_total numeric not null,
  new_total numeric not null,
  reason text not null,
  source_event_id uuid,
  created_at timestamptz not null default now()
);

-- Profili utente ----------------------------------------------
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

-- Trigger: creazione profilo automatica alla registrazione
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username)
  values (new.id, coalesce(new.raw_user_meta_data->>'username', 'utente' || left(new.id::text, 8)))
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
