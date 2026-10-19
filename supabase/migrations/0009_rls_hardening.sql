-- =============================================================
-- FantaCalcio365 - 0009_rls_hardening.sql
-- FASE 4: chiusura dei due gap trovati nell'audit RLS.
--  GAP 1 (ALTA): prediction_players con-check senza verifica blocco ->
--    si potevano aggiungere giocatori a una schedina bloccata via API.
--  GAP 2 (MEDIA): predictions update using senza verifica blocco ->
--    si poteva spostare una schedina bloccata su una partita aperta.
-- Sostituzione policy, nessun dato toccato.
-- =============================================================

drop policy if exists "pp via prediction" on prediction_players;

-- LETTURA: sempre permessa al proprietario (anche dopo il blocco: l'app
-- mostra la propria schedina compilata)
create policy "pp read own" on prediction_players for select to authenticated
  using (
    exists (
      select 1 from predictions p
      where p.id = prediction_id and p.user_id = auth.uid()
    )
  );

-- SCRITTURA (insert/update/delete): solo con partita non bloccata
-- (with-check verifica il blocco: chiude il GAP 1)
create policy "pp write own" on prediction_players for insert to authenticated
  with check (
    exists (
      select 1
      from predictions p
      join matches m on m.id = p.match_id
      where p.id = prediction_id
        and p.user_id = auth.uid()
        and (m.locked_at is null or now() < m.locked_at)
        and m.status in ('SCHEDULED','POSTPONED')
    )
  );

create policy "pp write own update" on prediction_players for update to authenticated
  using (
    exists (
      select 1
      from predictions p
      join matches m on m.id = p.match_id
      where p.id = prediction_id
        and p.user_id = auth.uid()
        and (m.locked_at is null or now() < m.locked_at)
        and m.status in ('SCHEDULED','POSTPONED')
    )
  ) with check (
    exists (
      select 1
      from predictions p
      join matches m on m.id = p.match_id
      where p.id = prediction_id
        and p.user_id = auth.uid()
        and (m.locked_at is null or now() < m.locked_at)
        and m.status in ('SCHEDULED','POSTPONED')
    )
  );

create policy "pp write own delete" on prediction_players for delete to authenticated
  using (
    exists (
      select 1
      from predictions p
      join matches m on m.id = p.match_id
      where p.id = prediction_id
        and p.user_id = auth.uid()
        and (m.locked_at is null or now() < m.locked_at)
        and m.status in ('SCHEDULED','POSTPONED')
    )
  );

drop policy if exists "own prediction update" on predictions;
create policy "own prediction update" on predictions for update to authenticated
  -- USING: anche la riga VECCHIA deve essere su una partita non bloccata
  -- (chiude il GAP 2: impossibile spostare una schedina bloccata)
  using (
    user_id = auth.uid()
    and exists (
      select 1 from matches m
      where m.id = match_id
        and (m.locked_at is null or now() < m.locked_at)
        and m.status in ('SCHEDULED','POSTPONED')
    )
  ) with check (
    user_id = auth.uid()
    and exists (
      select 1 from matches m
      where m.id = match_id
        and (m.locked_at is null or now() < m.locked_at)
        and m.status in ('SCHEDULED','POSTPONED')
    )
  );
