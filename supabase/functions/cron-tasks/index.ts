// =============================================================
// FantaCalcio365 - Edge Function: cron-tasks
// Scheduler (cron Supabase, ogni minuto):
//  1. Blocca le giornate il cui kickoff della prima gara e' passato (§9)
//  2. Sincronizza risultati/eventi dal provider per le partite LIVE/FINISHED
//  3. Gestisce provider offline: se il provider non risponde, riprova al
//     ciclo successivo senza mai calcolare punteggi su dati incompleti (§11)
// Deploy: supabase functions deploy cron-tasks
// Secret richiesti: API_FOOTBALL_KEY, (service role fornito da Supabase)
// =============================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SEASON_PROVIDER_ID = 135; // Serie A su API-Football (da confermare in POC)
const CURRENT_YEAR = 2026;

Deno.serve(async () => {
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // 1. Blocco giornate scadute
  await admin.rpc("lock_due_matchdays");

  // 2. Sync risultati: solo partite LIVE o FINISHED non ancora confermate
  const { data: live, error } = await admin
    .from("matches")
    .select("id, provider_id, status")
    .in("status", ["LIVE", "FINISHED"]);
  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });

  let providerDown = false;
  for (const match of live ?? []) {
    try {
      const resp = await fetch(
        `https://v3.football.api-sports.io/v3/fixtures?id=${match.provider_id}`,
        { headers: { "x-apisports-key": Deno.env.get("API_FOOTBALL_KEY")! } },
      );
      if (!resp.ok) { providerDown = true; continue; }
      const body = await resp.json();
      const fixture = body?.response?.[0];
      if (!fixture) continue; // dati incompleti: si riprova al ciclo successivo

      const goalsHt = fixture.score?.halftime;
      const goalsFt = fixture.score?.fulltime;
      const mapStatus: Record<string, string> = {
        "Match Finished": "FINISHED", "1H": "LIVE", "2H": "LIVE", "HT": "LIVE",
      };
      const status = mapStatus[fixture.fixture?.status?.long] ?? "LIVE";
      const confirmed = fixture.fixture?.status?.long === "Match Finished"
        && fixture.fixture?.status?.short === "FT";

      // Gli eventi arrivano gia' ordinati; si usa l'indice come event_order (A6)
      const events = (fixture.events ?? []).map((e: any, i: number) => ({
        event_order: e.time?.elapsed != null ? i : i,
        minute: e.time?.elapsed ?? null,
        type: e.type === "Goal" ? (e.detail === "Own Goal" ? "GOAL" : "GOAL")
            : e.type === "Card" && e.detail?.includes("Yellow") ? "YELLOW" : "OTHER",
        player: e.player?.id != null ? String(e.player.id) : null,
        related_player: e.assist?.id != null ? String(e.assist.id) : null,
      }));

      await admin.rpc("ingest_match_result", {
        p_provider_id: match.provider_id,
        p_result: {
          status: confirmed ? "CONFIRMED" : status,
          ht_home: goalsHt?.home ?? null,
          ht_away: goalsHt?.away ?? null,
          ht2_home: goalsFt?.home != null && goalsHt?.home != null
            ? goalsFt.home - goalsHt.home : null,   // solo gol 2T (§4)
          ht2_away: goalsFt?.away != null && goalsHt?.away != null
            ? goalsFt.away - goalsHt.away : null,
          ft_home: goalsFt?.home ?? null,
          ft_away: goalsFt?.away ?? null,
          events,
        },
      });
    } catch {
      providerDown = true; // provider offline: retry al prossimo ciclo
    }
  }

  return Response.json({ ok: true, providerDown });
});
