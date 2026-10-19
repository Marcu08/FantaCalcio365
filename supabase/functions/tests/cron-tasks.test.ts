// =============================================================
// FantaCalcio365 - Test cron-tasks (deno test, mock Supabase + fetch)
// Verifica: salta manual_override, rispetta i TTL (live/finizione/confermata),
// non interroga le partite CONFIRMED, gestisce provider offline.
// =============================================================
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { setMockFactory, resetMockFactory } from "./supabase_mock.ts";
import { importIndex } from "./mocks.ts";

type RpcCall = { name: string; args: any };

function makeMockClient(opts: { matches: any[]; fresh?: boolean }) {
  const rpcCalls: RpcCall[] = [];
  const selectCalls: any[] = [];
  const client = {
    rpc: async (name: string, args?: any) => {
      rpcCalls.push({ name, args });
      return { data: name === "cache_is_fresh" ? (opts.fresh ?? false) : null, error: null };
    },
    from: (_t: string) => {
      const selectCallsLocal = selectCalls;
      const chain: any = {
        select: (..._a: any[]) => { selectCallsLocal.push({ select: true }); return chain; },
        in: (col: string, vals: string[]) => { selectCallsLocal.push({ in: [col, vals] }); return chain; },
        eq: (col: string, val: any) => { selectCallsLocal.push({ eq: [col, val] }); return chain; },
      };
      (chain as any).then = (res: any, rej: any) =>
        Promise.resolve({ data: opts.matches, error: null }).then(res, rej);
      return chain;
    },
  };
  return { client, rpcCalls, selectCalls };
}

const MATCH_LIVE = { id: "m-live", provider_id: "PLIVE", status: "LIVE", manual_override: false };
const MATCH_FIN = { id: "m-fin", provider_id: "PFIN", status: "FINISHED", manual_override: false };
const MATCH_OVR = { id: "m-ovr", provider_id: "POVR", status: "LIVE", manual_override: true };

const FIXTURE_OK = {
  response: [{
    fixture: { id: 1, status: { long: "Match Finished", short: "FT" }, date: "2026-10-19T15:00:00Z" },
    score: { halftime: { home: 1, away: 0 }, fulltime: { home: 2, away: 1 } },
    events: [{ type: "Goal", time: { elapsed: 20 }, player: { id: 9 }, detail: "Normal Goal" }],
  }],
};

function setup(opts: { matches: any[]; fresh?: boolean }) {
  const mc = makeMockClient({ matches: opts.matches, fresh: opts.fresh });
  setMockFactory(() => mc.client);
  const fetchCalls: string[] = [];
  const origFetch = globalThis.fetch;
  globalThis.fetch = (input: any, init?: any) => {
    const url = typeof input === "string" ? input : input.url;
    fetchCalls.push(url);
    if (String(url).includes("football")) {
      return Promise.resolve(new Response(JSON.stringify(FIXTURE_OK), { status: 200 }));
    }
    return origFetch(input, init);
  };
  return {
    rpcCalls: mc.rpcCalls, selectCalls: mc.selectCalls, fetchCalls,
    cleanup: () => { globalThis.fetch = origFetch; resetMockFactory(); },
  };
}

Deno.test("cron: salta partite con manual_override e non interroga CONFIRMED", async () => {
  const h = setup({ matches: [MATCH_LIVE, MATCH_OVR], fresh: false });
  const mod = await importIndex("../cron-tasks/index.ts");
  await mod.handler(new Request("http://x/cron")).json();
  const hasIn = h.selectCalls.some((c: any) => c.in?.[0] === "status" && c.in?.[1].join() === "LIVE,FINISHED");
  const hasOvr = h.selectCalls.some((c: any) => c.eq?.[0] === "manual_override" && c.eq?.[1] === false);
  assertEquals(hasIn, true, "deve interrogare solo LIVE/FINISHED");
  assertEquals(hasOvr, true, "deve escludere manual_override = true");
  assertEquals(h.fetchCalls.some((u) => String(u).includes("POVR")), false,
    "il provider NON deve essere interrogato per partite override");
  h.cleanup();
});

Deno.test("cron: TTL - cache fresh = skip provider", async () => {
  const h = setup({ matches: [MATCH_LIVE], fresh: true });
  const mod = await importIndex("../cron-tasks/index.ts");
  const body = await mod.handler(new Request("http://x/cron")).json();
  assertEquals(body.skipped, 1, "cache fresh: partita saltata");
  assertEquals(h.fetchCalls.some((u) => u.includes("football")), false,
    "provider NON interrogato con cache fresh");
  h.cleanup();
});

Deno.test("cron: cache scaduta - chiama provider, scrive cache e ingesta", async () => {
  const h = setup({ matches: [MATCH_FIN], fresh: false });
  const mod = await importIndex("../cron-tasks/index.ts");
  await mod.handler(new Request("http://x/cron")).json();
  assertEquals(h.fetchCalls.some((u) => u.includes("PFIN")), true, "provider interrogato");
  assertEquals(h.rpcCalls.some((r: any) => r.name === "cache_match_events"), true, "cache scritta");
  const ingest = h.rpcCalls.find((r: any) => r.name === "ingest_match_result");
  assertEquals(ingest != null, true, "ingest_match_result chiamata");
  if (ingest != null) {
    // §4: il 2T e' la differenza ft - ht (solo gol seconda frazione)
    assertEquals(ingest.args.p_result.ht2_home, 1);
    assertEquals(ingest.args.p_result.ht2_away, 1);
    assertEquals(ingest.args.p_result.status, "CONFIRMED");
  }
  h.cleanup();
});

Deno.test("cron: mai interroga CONFIRMED (solo LIVE/FINISHED)", async () => {
  const h = setup({ matches: [] });
  const mod = await importIndex("../cron-tasks/index.ts");
  await mod.handler(new Request("http://x/cron")).json();
  const inCall = h.selectCalls.find((c: any) => c.in?.[0] === "status");
  assertEquals(inCall?.in?.[1]?.includes("CONFIRMED"), false,
    "CONFIRMED non deve mai essere richiesto al provider dal cron");
  h.cleanup();
});
