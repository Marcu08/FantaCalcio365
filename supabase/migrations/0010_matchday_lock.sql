-- =============================================================
-- FantaCalcio365 - 0010_matchday_lock.sql
-- FASE 4 (P0): il blocco pronostici deve valere a livello GIORNATA,
-- non per singola partita. Una gara aggiunta DOPO il blocco (rinviata,
-- recuperata, nuova) con locked_at null accettava pronostici tardivi.
-- Fix: le policy di scrittura confrontano now() con il kickoff della
-- PRIMA gara della giornata, calcolato dal server sui dati ufficiali.
-- Il campo locked_at resta per la visualizzazione (countdown app).
-- =============================================================

-- Helper: kickoff della prima gara della giornata (esclusi annullate)
create or replace function public.matchday_first_kickoff(p_season_id uuid, p_matchday int)
returns timestamptz
language sql stable security definer
set search_path = public, pg_temp as $$
  select min(kickoff_at) from matches
  where season_id = p_season_id and matchday = p_matchday and status <> 'CANCELLED';
$$;

revoke all on function public.matchday_first_kickoff(uuid, int) from public, anon;
grant execute on function public.matchday_first_kickoff(uuid, int) to authenticated, service_role;

-- ---- predictions: insert --------------------------------------
drop policy if exists "own prediction insert" on predictions;
create policy "own prediction insert" on predictions for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from matches m
      where m.id = match_id
        and m.status in ('SCHEDULED','POSTPONED')
        and now() < public.matchday_first_kickoff(m.season_id, m.matchday)
    )
  );

-- ---- predictions: update --------------------------------------
drop policy if exists "own prediction update" on predictions;
create policy "own prediction update" on predictions for update to authenticated
  using (
    user_id = auth.uid()
    and exists (
      select 1 from matches m
      where m.id = match_id
        and m.status in ('SCHEDULED','POSTPONED')
        and now() < public.matchday_first_kickoff(m.season_id, m.matchday)
    )
  ) with check (
    user_id = auth.uid()
    and exists (
      select 1 from matches m
      where m.id = match_id
        and m.status in ('SCHEDULED','POSTPONED')
        and now() < public.matchday_first_kickoff(m.season_id, m.matchday)
    )
  );

-- ---- predictions: delete --------------------------------------
drop policy if exists "own prediction delete" on predictions;
create policy "own prediction delete" on predictions for delete to authenticated
  using (
    user_id = auth.uid()
    and exists (
      select 1 from matches m
      where m.id = match_id
        and m.status in ('SCHEDULED','POSTPONED')
        and now() < public.matchday_first_kickoff(m.season_id, m.matchday)
    )
  );

-- ---- prediction_players: insert -------------------------------
drop policy if exists "pp write own" on prediction_players;
create policy "pp write own" on prediction_players for insert to authenticated
  with check (
    exists (
      select 1
      from predictions p
      join matches m on m.id = p.match_id
      where p.id = prediction_id
        and p.user_id = auth.uid()
        and m.status in ('SCHEDULED','POSTPONED')
        and now() < public.matchday_first_kickoff(m.season_id, m.matchday)
    )
  );

-- ---- prediction_players: update -------------------------------
drop policy if exists "pp write own update" on prediction_players;
create policy "pp write own update" on prediction_players for update to authenticated
  using (
    exists (
      select 1
      from predictions p
      join matches m on m.id = p.match_id
      where p.id = prediction_id
        and p.user_id = auth.uid()
        and m.status in ('SCHEDULED','POSTPONED')
        and now() < public.matchday_first_kickoff(m.season_id, m.matchday)
    )
  ) with check (
    exists (
      select 1
      from predictions p
      join matches m on m.id = p.match_id
      where p.id = prediction_id
        and p.user_id = auth.uid()
        and m.status in ('SCHEDULED','POSTPONED')
        and now() < public.matchday_first_kickoff(m.season_id, m.matchday)
    )
  );

-- ---- prediction_players: delete -------------------------------
drop policy if exists "pp write own delete" on prediction_players;
create policy "pp write own delete" on prediction_players for delete to authenticated
  using (
    exists (
      select 1
      from predictions p
      join matches m on m.id = p.match_id
      where p.id = prediction_id
        and p.user_id = auth.uid()
        and m.status in ('SCHEDULED','POSTPONED')
        and now() < public.matchday_first_kickoff(m.season_id, m.matchday)
    )
  );
