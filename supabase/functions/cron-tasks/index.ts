// =============================================================
// FantaCalcio365 - Edge Function: cron-tasks
// Deploy: supabase functions deploy cron-tasks
// =============================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { apiFootballHeaders, apiFootballUrl } from "../_shared/api-football.ts";

const TTL_LIVE = parseInt(Deno.env.get("CACHE_TTL_LIVE_S") ?? "30");
const TTL_UNCONFIRMED = parseInt(Deno.env.get("CACHE_TTL_UNCONFIRMED_S") ?? "900");
const MAX_FETCH_PER_CYCLE = parseInt(Deno.env.get("CRON_MAX_FETCH_PER_CYCLE") ?? "8");

export async function handler(_req: Request): Promise<Response> {
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  await admin.rpc("lock_due_matchdays");

  const { data: live, error } = await admin
    .from("matches")
    .select("id, provider_id, status, manual_override")
    .in("status", ["LIVE", "FINISHED"])
    .eq("manual_override", false);
  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });

  const ordered = [...(live ?? [])].sort((a, b) => {
    if (a.status === b.status) return 0;
    return a.status === "LIVE" ? -1 : 1;
  });

  let providerDown = false;
  let skipped = 0;
  let fetched = 0;
  for (const match of ordered) {
    try {
      const ttl = match.status === "LIVE" ? TTL_LIVE : TTL_UNCONFIRMED;
      const { data: fresh } = await admin.rpc("cache_is_fresh", {
        p_provider_match_id: match.provider_id,
        p_max_age_seconds: ttl,
      });
      if (fresh === true) { skipped++; continue; }
      if (fetched >= MAX_FETCH_PER_CYCLE) { skipped++; continue; }

      const resp = await fetch(
        apiFootballUrl("fixtures", new URLSearchParams({ id: String(match.provider_id) })),
        { headers: apiFootballHeaders() },
      );
      fetched++;
      if (!resp.ok) { providerDown = true; continue; }
      const body = await resp.json();
      const fixture = body?.response?.[0];
      if (!fixture) {
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

      const events = (fixture.events ?? []).map((e: any, i: number) => {
        const type = e.type === "Goal" ? "GOAL"
          : e.type === "Card" && e.detail?.includes("Yellow") ? "YELLOW"
          : e.type === "Card" && e.detail?.includes("Red") ? "RED"
          : e.type === "subst" || e.type === "Subst" ? "SUB_OUT"
          : null;
        return {
          event_order: i,
          minute: e.time?.elapsed ?? null,
          type,
          player: e.player?.id != null ? String(e.player.id) : null,
          related_player: e.assist?.id != null ? String(e.assist.id) : null,
        };
      }).filter((e: { type: string | null }) => e.type != null);

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
            ? goalsFt.home - goalsHt.home : null,
          ht2_away: goalsFt?.away != null && goalsHt?.away != null
            ? goalsFt.away - goalsHt.away : null,
          ft_home: goalsFt?.home ?? null,
          ft_away: goalsFt?.away ?? null,
          events,
        },
      });
    } catch {
      providerDown = true;
    }
  }

  return Response.json({ ok: true, providerDown, skipped, fetched });
}

if (import.meta.main) Deno.serve(handler);
