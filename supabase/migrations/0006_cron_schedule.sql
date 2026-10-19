-- =============================================================
-- FantaCalcio365 - 0006_cron_schedule.sql
-- Schedula cron-tasks ogni minuto: blocca le giornate scadute e
-- sincronizza risultati/eventi dal provider (§9, §11).
-- Richiede le estensioni pg_cron e pg_net.
-- =============================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- La funzione e' stata deployata con --no-verify-jwt: nessun header di auth.
select cron.schedule(
  'fantacalcio365-cron-tasks',
  '* * * * *',
  $$
  select net.http_post(
    url := 'https://efmpbykcqrdvnecdgasi.supabase.co/functions/v1/cron-tasks',
    headers := '{"Content-Type":"application/json"}'::jsonb
  );
  $$
);

-- Controllo: select * from cron.job;
-- Log esecuzioni: select * from cron.job_run_details order by start_time desc limit 10;
