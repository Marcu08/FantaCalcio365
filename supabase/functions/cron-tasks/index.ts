// =============================================================
// FantaCalcio365 - Edge Function: cron-tasks
// Scheduler (cron Supabase, ogni minuto):
//  1. Blocca le giornate il cui kickoff della prima gara e' passato (§9)
//  2. Sincronizza risultati/eventi dal provider per le partite LIVE/FINISHED
//  3. Cache eventi in event_cache con TTL differenziati (FASE 2):
//       LIVE         → CACHE_TTL_LIVE_S        (default 30s)
//       FINISHED     → CACHE_TTL_UNCONFIRMED_S (default 900s)
//       CONFIRMED    → mai richiamato automaticamente (solo admin-override)
//  4. Salta le partite con manual_override = true (correzioni admin)
//  5. Provider offline: fetch_status='provider_down', retry al ciclo successivo
// Deploy: supabase functions deploy cron-tasks
// =============================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const TTL_LIVE = parseInt(Deno.env.get("CACHE_TTL_LIVE_S") ?? "30");
const TTL_UNCONFIRMED = parseInt(Deno.env.get("CACHE_TTL_UNCONFIRMED_S") ?? "900");

export async function handler(_req: Request): Promise<Response> {
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // 1. Blocco giornate scadute
  await admin.rpc("lock_due_matchdays");

  // 2. Sync risultati: solo partite LIVE o FINISHED non ancora confermate.
  //    Le CONFIRMED non vengono mai richiamate automaticamente (FASE 2).
  //    manual_override = true → la correzione admin prevale, mai toccata dal cron.
  const { data: live, error } = await admin
    .from("matches")
    .select("id, provider_id, status, manual_override")
    .in("status", ["LIVE", "FINISHED"])
    .eq("manual_override", false);
  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });

  let providerDown = false;
  let skipped = 0;
  for (const match of live ?? []) {
    try {
      // 2a. Cache: TTL differenziato per stato (FASE 2)
      const ttl = match.status === "LIVE" ? TTL_LIVE : TTL_UNCONFIRMED;
      const { data: fresh } = await admin.rpc("cache_is_fresh", {
        p_provider_match_id: match.provider_id,
        p_max_age_seconds: ttl,
      });
      if (fresh === true) { skipped++; continue; }

      const resp = await fetch(
        `https://v3.football.api-sports.io/v3/fixtures?id=${match.provider_id}`,
        { headers: { "x-apisports-key": Deno.env.get("API_FOOTBALL_KEY")! } },
      );
      if (!resp.ok) { providerDown = true; continue; }
      const body = await resp.json();
      const fixture = body?.response?.[0];
      if (!fixture) {
        // dati incompleti: si registra e si riprova al ciclo successivo (§11)
        await admin.rpc("cache_match_events", {
          p_provider_match_id: match.provider_id,
          p_match_id: match.id,
          p_fixture: {},
          p_events: [],
          p_status: "incomplete",
          p_source_updated_at: null,
        });
        continue;
      }

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
        event_order: i,
        minute: e.time?.elapsed ?? null,
        type: e.type === "Goal" ? "GOAL"
            : e.type === "Card" && e.detail?.includes("Yellow") ? "YELLOW" : "OTHER",
        player: e.player?.id != null ? String(e.player.id) : null,
        related_player: e.assist?.id != null ? String(e.assist.id) : null,
      }));

      // 2b. Cache della risposta grezza prima di toccare i dati ufficiali
      await admin.rpc("cache_match_events", {
        p_provider_match_id: match.provider_id,
        p_match_id: match.id,
        p_fixture: fixture,
        p_events: fixture.events ?? [],
        p_status: "ok",
        p_source_updated_at: fixture.fixture?.updated ?? null,
      });

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

  return Response.json({ ok: true, providerDown, skipped });
}

// Serve solo quando eseguita direttamente (non nei test)
if (import.meta.main) Deno.serve(handler);
