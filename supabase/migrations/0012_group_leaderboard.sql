-- =============================================================
-- FantaCalcio365 - 0012_group_leaderboard.sql
-- Classifica isolata per gruppo privato (§10): ogni membro vede solo
-- i punteggi dei membri del proprio gruppo. La classifica GENERALE
-- resta la vista leaderboard, invariata.
-- (join_group_by_code e admin_lock_matchday sono gia' in 0011)
-- =============================================================

create or replace function public.group_leaderboard(p_group_id uuid)
returns table (user_id uuid, username text, total numeric)
language plpgsql stable security definer
set search_path = public, pg_temp as $$
begin
  -- Accesso riservato ai membri del gruppo (o al owner)
  -- (colonne sempre qualificate: i nomi user_id/username/total sono
  --  anche parametri OUT della tabella di ritorno)
  if not exists (
    select 1 from group_members gm
    where gm.group_id = p_group_id and gm.user_id = auth.uid()
  ) and not exists (
    select 1 from groups g
    where g.id = p_group_id and g.owner_id = auth.uid()
  ) then
    raise exception 'Non sei membro di questo gruppo';
  end if;

  return query
    select s.user_id, p.username, sum(s.total)::numeric
    from group_members gm
    join profiles p on p.id = gm.user_id
    left join scores s on s.user_id = gm.user_id
    where gm.group_id = p_group_id
    group by s.user_id, p.username
    order by sum(s.total) desc nulls last;
end $$;

revoke all on function public.group_leaderboard(uuid) from public, anon;
grant execute on function public.group_leaderboard(uuid) to authenticated;
