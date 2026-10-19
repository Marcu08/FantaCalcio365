-- =============================================================
-- FantaCalcio365 - 0002_rls.sql
-- Row Level Security. Regole chiave (§12):
--  - pronostici leggibili/modificabili SOLO dal proprietario
--  - nessuna modifica dopo il blocco della partita
--  - nessuna lettura anticipata dei pronostici altrui
--  - dati ufficiali: sola lettura per gli utenti, scrittura solo service_role
-- =============================================================

alter table seasons enable row level security;
alter table teams enable row level security;
alter table players enable row level security;
alter table matches enable row level security;
alter table match_events enable row level security;
alter table player_match_stats enable row level security;
alter table predictions enable row level security;
alter table prediction_players enable row level security;
alter table scores enable row level security;
alter table groups enable row level security;
alter table group_members enable row level security;
alter table profiles enable row level security;
alter table admin_audit_log enable row level security;
alter table score_corrections enable row level security;

-- Helper: utente admin ----------------------------------------
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from profiles where id = auth.uid()), false);
$$;

-- Catalogo pubblico (autenticati) ------------------------------
create policy "auth read seasons" on seasons for select to authenticated using (true);
create policy "auth read teams" on teams for select to authenticated using (true);
create policy "auth read players" on players for select to authenticated using (true);
create policy "auth read matches" on matches for select to authenticated using (true);
create policy "auth read events" on match_events for select to authenticated using (true);
create policy "auth read stats" on player_match_stats for select to authenticated using (true);

-- Profili: ciascuno vede il proprio; gli admin vedono tutto ----
create policy "own profile" on profiles for select to authenticated
  using (id = auth.uid() or public.is_admin());
create policy "own profile update" on profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid() and is_admin = (select is_admin from profiles where id = auth.uid()));

-- Pronostici: SOLO il proprietario. La modifica e' bloccata dopo
-- locked_at (verifica server-side, non client) ------------------
create policy "own prediction select" on predictions for select to authenticated
  using (user_id = auth.uid());
create policy "own prediction insert" on predictions for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from matches m
      where m.id = match_id
        and (m.locked_at is null or now() < m.locked_at)
        and m.status in ('SCHEDULED','POSTPONED')
    )
  );
create policy "own prediction update" on predictions for update to authenticated
  using (user_id = auth.uid()) with check (
    user_id = auth.uid()
    and exists (
      select 1 from matches m
      where m.id = match_id
        and (m.locked_at is null or now() < m.locked_at)
        and m.status in ('SCHEDULED','POSTPONED')
    )
  );
create policy "own prediction delete" on predictions for delete to authenticated
  using (
    user_id = auth.uid()
    and exists (
      select 1 from matches m
      where m.id = match_id
        and (m.locked_at is null or now() < m.locked_at)
        and m.status in ('SCHEDULED','POSTPONED')
    )
  );

-- Selezione giocatori: segue il permesso della schedina padre
create policy "pp via prediction" on prediction_players for all to authenticated
  using (
    exists (
      select 1 from predictions p
      where p.id = prediction_id
        and p.user_id = auth.uid()
        and exists (
          select 1 from matches m
          where m.id = p.match_id
            and (m.locked_at is null or now() < m.locked_at)
            and m.status in ('SCHEDULED','POSTPONED')
        )
    )
  ) with check (
    exists (
      select 1 from predictions p
      where p.id = prediction_id
        and p.user_id = auth.uid()
    )
  );

-- Punteggi: solo il proprietario vede i propri; la classifica usa
-- una vista con esposizione controllata ------------------------
create policy "own scores" on scores for select to authenticated
  using (user_id = auth.uid());

-- Gruppi -------------------------------------------------------
create policy "member read group" on groups for select to authenticated
  using (
    owner_id = auth.uid()
    or exists (select 1 from group_members gm where gm.group_id = id and gm.user_id = auth.uid())
  );
create policy "owner update group" on groups for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "auth create group" on groups for insert to authenticated
  with check (owner_id = auth.uid());

create policy "member read membership" on group_members for select to authenticated
  using (
    user_id = auth.uid()
    or exists (select 1 from groups g where g.id = group_id and g.owner_id = auth.uid())
  );
create policy "self join" on group_members for insert to authenticated
  with check (
    -- il codice invito è verificato dall'app cercando il gruppo per invite_code
    user_id = auth.uid()
  );
create policy "owner remove member" on group_members for delete to authenticated
  using (
    exists (select 1 from groups g where g.id = group_id and g.owner_id = auth.uid())
  );

-- Audit e correzioni: lettura solo admin, scrittura solo service_role
create policy "admin read audit" on admin_audit_log for select to authenticated
  using (public.is_admin());
create policy "admin read corrections" on score_corrections for select to authenticated
  using (public.is_admin());

-- Vista classifica generale: usa solo dati UFFICIALI + provvisori
-- marcati (nessun dato personale sensibile esposto)
create or replace view leaderboard as
select
  s.user_id,
  p.username,
  s.season_id,
  sum(s.total)::numeric as total,
  sum(case when s.exact_ht and s.exact_ht2 then 1 else 0 end) as exact_results,
  sum(s.exact_scorers) as exact_scorers,
  min(s.first_submitted_at) as first_submission
from scores s
join profiles p on p.id = s.user_id
group by s.user_id, p.username, s.season_id;

--Ordinamento: total desc, exact_results desc, exact_scorers desc, first_submission asc (A4)
