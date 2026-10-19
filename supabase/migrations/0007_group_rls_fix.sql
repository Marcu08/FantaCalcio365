-- =============================================================
-- FantaCalcio365 - 0007_group_rls_fix.sql
-- Correzione ricorsione infinita nelle policy di groups/group_members:
-- gli helper SECURITY DEFINER bypassano RLS e spezzano il ciclo.
-- =============================================================

create or replace function public.is_group_member(p_group_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from group_members where group_id = p_group_id and user_id = auth.uid());
$$;

create or replace function public.is_group_owner(p_group_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from groups where id = p_group_id and owner_id = auth.uid());
$$;

drop policy if exists "member read group" on groups;
drop policy if exists "owner update group" on groups;
drop policy if exists "member read membership" on group_members;
drop policy if exists "owner remove member" on group_members;

create policy "member read group" on groups for select to authenticated
  using (owner_id = auth.uid() or public.is_group_member(id));

create policy "owner update group" on groups for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy "member read membership" on group_members for select to authenticated
  using (user_id = auth.uid() or public.is_group_owner(group_id));

create policy "owner remove member" on group_members for delete to authenticated
  using (public.is_group_owner(group_id));
