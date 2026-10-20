-- =============================================================
-- FantaCalcio365 - 0011_groups_prediction_rpc.sql
-- Join gruppi per codice (RPC security definer), chiusura self-join,
-- salvataggio schedina atomico, validazione 4 giocatori per squadra,
-- classifica security_invoker=false, cron URL da app_config.
-- =============================================================

-- ---- Config runtime (URL functions, senza hardcoded nel job) ----
create table if not exists public.app_config (
  key text primary key,
  value text not null
);

insert into public.app_config(key, value) values
  ('functions_base_url', 'https://efmpbykcqrdvnecdgasi.supabase.co')
on conflict (key) do nothing;

alter table public.app_config enable row level security;

-- ---- Owner automaticamente membro del gruppo ----
create or replace function public.add_owner_as_member()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.group_members(group_id, user_id)
  values (new.id, new.owner_id)
  on conflict do nothing;
  return new;
end $$;

drop trigger if exists trg_add_owner_as_member on public.groups;
create trigger trg_add_owner_as_member
  after insert on public.groups
  for each row execute function public.add_owner_as_member();

-- ---- Join per codice invito ----
create or replace function public.join_group_by_code(p_code text)
returns public.groups
language plpgsql
security definer
set search_path = public
as $$
declare
  g public.groups;
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Non autenticato';
  end if;
  if p_code is null or length(trim(p_code)) < 4 then
    raise exception 'Codice invito non valido';
  end if;

  select * into g
  from public.groups
  where lower(invite_code) = lower(trim(p_code));

  if not found then
    raise exception 'Codice invito non valido';
  end if;

  insert into public.group_members(group_id, user_id)
  values (g.id, uid)
  on conflict do nothing;

  return g;
end $$;

revoke all on function public.join_group_by_code(text) from public, anon;
grant execute on function public.join_group_by_code(text) to authenticated;

drop policy if exists "self join" on public.group_members;

-- ---- Validazione schedina (casa/ospite, 4 giocatori, 1 marcatore) ----
create or replace function public.validate_prediction_row(p_prediction_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  n int; n_home int; n_away int; n_scorers int;
  v_match_id uuid;
  v_home uuid; v_away uuid;
begin
  select match_id into v_match_id from public.predictions where id = p_prediction_id;
  if v_match_id is null then
    return;
  end if;
  select home_team_id, away_team_id into v_home, v_away
  from public.matches where id = v_match_id;

  select count(*),
         count(*) filter (where pl.team_id = v_home),
         count(*) filter (where pl.team_id = v_away),
         count(*) filter (where pp.is_marked_scorer)
  into n, n_home, n_away, n_scorers
  from public.prediction_players pp
  join public.players pl on pl.id = pp.player_id
  where pp.prediction_id = p_prediction_id;

  if n <> 4 then
    raise exception 'La schedina richiede esattamente 4 giocatori (trovati %)', n;
  end if;
  if n_home < 1 then raise exception 'Almeno 1 giocatore della squadra di casa'; end if;
  if n_away < 1 then raise exception 'Almeno 1 giocatore della squadra ospite'; end if;
  if n_scorers < 1 then raise exception 'Dichiarare almeno 1 marcatore'; end if;
end $$;

create or replace function public.validate_prediction()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.validate_prediction_row(coalesce(new.id, old.id));
  return coalesce(new, old);
end $$;

create or replace function public.validate_prediction_from_player()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.validate_prediction_row(coalesce(new.prediction_id, old.prediction_id));
  return coalesce(new, old);
end $$;

drop trigger if exists trg_validate_prediction on public.predictions;
create constraint trigger trg_validate_prediction
  after insert or update on public.predictions
  deferrable initially deferred
  for each row execute function public.validate_prediction();

drop trigger if exists trg_validate_prediction_players on public.prediction_players;
create constraint trigger trg_validate_prediction_players
  after insert or update or delete on public.prediction_players
  deferrable initially deferred
  for each row execute function public.validate_prediction_from_player();

-- ---- Salvataggio atomico della schedina ----
create or replace function public.save_prediction(
  p_match_id uuid,
  p_ht_home int,
  p_ht_away int,
  p_ht2_home int,
  p_ht2_away int,
  p_first_sub_out uuid,
  p_first_yellow uuid,
  p_players jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  v_id uuid;
  m record;
begin
  if uid is null then
    raise exception 'Non autenticato';
  end if;

  select * into m from public.matches where id = p_match_id;
  if m.id is null then
    raise exception 'Partita inesistente';
  end if;
  if m.status not in ('SCHEDULED','POSTPONED') then
    raise exception 'Pronostici chiusi per questa partita';
  end if;
  if now() >= public.matchday_first_kickoff(m.season_id, m.matchday) then
    raise exception 'Giornata bloccata';
  end if;

  insert into public.predictions (
    user_id, match_id, ht_home, ht_away, ht2_home, ht2_away,
    first_sub_out_player_id, first_yellow_player_id, updated_at
  ) values (
    uid, p_match_id, p_ht_home, p_ht_away, p_ht2_home, p_ht2_away,
    p_first_sub_out, p_first_yellow, now()
  )
  on conflict (user_id, match_id) do update set
    ht_home = excluded.ht_home,
    ht_away = excluded.ht_away,
    ht2_home = excluded.ht2_home,
    ht2_away = excluded.ht2_away,
    first_sub_out_player_id = excluded.first_sub_out_player_id,
    first_yellow_player_id = excluded.first_yellow_player_id,
    updated_at = now()
  returning id into v_id;

  delete from public.prediction_players where prediction_id = v_id;

  insert into public.prediction_players (prediction_id, player_id, is_marked_scorer)
  select v_id,
         (elem->>'player_id')::uuid,
         coalesce((elem->>'is_marked_scorer')::boolean, false)
  from jsonb_array_elements(coalesce(p_players, '[]'::jsonb)) elem;

  perform public.validate_prediction_row(v_id);
  return v_id;
end $$;

revoke all on function public.save_prediction(uuid, int, int, int, int, uuid, uuid, jsonb)
  from public, anon;
grant execute on function public.save_prediction(uuid, int, int, int, int, uuid, uuid, jsonb)
  to authenticated;

-- ---- Admin: blocco giornata ----
create or replace function public.admin_lock_matchday(p_season_id uuid, p_matchday int)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Solo amministratori';
  end if;
  perform public.lock_matchday(p_season_id, p_matchday);
end $$;

revoke all on function public.admin_lock_matchday(uuid, int) from public, anon;
grant execute on function public.admin_lock_matchday(uuid, int) to authenticated;

revoke all on function public.validate_prediction_row(uuid) from public, anon, authenticated;
revoke all on function public.validate_prediction_from_player() from public, anon, authenticated;
revoke all on function public.add_owner_as_member() from public, anon, authenticated;

-- ---- Classifica: owner della view bypassa RLS sui profili ----
drop view if exists public.leaderboard;
create view public.leaderboard
  with (security_invoker = false)
as
select
  s.user_id,
  p.username,
  s.season_id,
  sum(s.total)::numeric as total,
  sum(case when s.exact_ht and s.exact_ht2 then 1 else 0 end) as exact_results,
  sum(s.exact_scorers) as exact_scorers,
  min(s.first_submitted_at) as first_submission
from public.scores s
join public.profiles p on p.id = s.user_id
group by s.user_id, p.username, s.season_id;

grant select on public.leaderboard to authenticated;

-- ---- Cron: URL da app_config ----
do $$
begin
  if exists (select 1 from cron.job where jobname = 'fantacalcio365-cron-tasks') then
    perform cron.unschedule('fantacalcio365-cron-tasks');
  end if;
  perform cron.schedule(
    'fantacalcio365-cron-tasks',
    '* * * * *',
    $job$
    select net.http_post(
      url := (select value from public.app_config where key = 'functions_base_url')
             || '/functions/v1/cron-tasks',
      headers := '{"Content-Type":"application/json"}'::jsonb
    );
    $job$
  );
exception
  when undefined_table then null;
  when undefined_object then null;
  when invalid_schema_name then null;
end $$;
