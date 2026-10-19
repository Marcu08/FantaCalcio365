-- Chiamato dal cron: blocca tutte le giornate con prima gara gia' iniziata
create or replace function public.lock_due_matchdays()
returns void language plpgsql security definer set search_path = public as $$
declare
  r record;
begin
  for r in
    select distinct season_id, matchday
    from matches
    where locked_at is null
      and status in ('SCHEDULED','LIVE')
      and kickoff_at <= now()
  loop
    perform public.lock_matchday(r.season_id, r.matchday);
  end loop;
end $$;
