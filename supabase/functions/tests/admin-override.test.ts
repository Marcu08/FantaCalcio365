// =============================================================
// FantaCalcio365 - Test admin-override (deno test, mock Supabase)
// Verifica: zod (body malformati/64KB), 401 senza JWT, 403 non-admin,
// 200 + RPC con p_actor per admin.
// =============================================================
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { setMockFactory, resetMockFactory } from "./supabase_mock.ts";
import { importIndex } from "./mocks.ts";

const ADMIN_JWT = "Bearer admin.jwt.token";
const VALID_BODY = {
  provider_id: "M1",
  reason: "Correzione ufficiale lega serie A",
  result: {
    status: "CONFIRMED", ht_home: 1, ht_away: 0,
    ht2_home: 1, ht2_away: 1, ft_home: 2, ft_away: 1,
  },
  events: [{ event_order: 1, minute: 30, type: "GOAL", player: "P2" }],
};

Deno.test("401 se JWT assente/non valido", async () => {
  setMockFactory(() => ({
    auth: { getUser: async () => ({ data: { user: null }, error: { message: "bad jwt" } }) },
  }));
  const mod = await importIndex("../admin-override/index.ts");
  const res = await mod.handler(new Request("http://x/", {
    method: "POST", body: JSON.stringify(VALID_BODY),
  }));
  assertEquals(res.status, 401);
  resetMockFactory();
});

Deno.test("403 se utente non admin", async () => {
  setMockFactory(() => ({
    auth: { getUser: async () => ({ data: { user: { id: "u1" } }, error: null }) },
    from: () => {
      const chain: any = { select: () => chain, eq: () => chain };
      chain.single = async () => ({ data: { is_admin: false }, error: null });
      return chain;
    },
  }));
  const mod = await importIndex("../admin-override/index.ts");
  const { status } = await callHandlerDirect(mod.handler, VALID_BODY);
  assertEquals(status, 403);
  resetMockFactory();
});

Deno.test("403 se profilo assente", async () => {
  setMockFactory(() => ({
    auth: { getUser: async () => ({ data: { user: { id: "u2" } }, error: null }) },
    from: () => {
      const chain: any = { select: () => chain, eq: () => chain };
      chain.single = async () => ({ data: null, error: { message: "no profile" } });
      return chain;
    },
  }));
  const mod = await importIndex("../admin-override/index.ts");
  const { status } = await callHandlerDirect(mod.handler, VALID_BODY);
  assertEquals(status, 403);
  resetMockFactory();
});

Deno.test("400 con body malformato (zod)", async () => {
  const adminClient = makeAdminClient();
  setMockFactory(() => adminClient.client);
  const mod = await importIndex("../admin-override/index.ts");
  const bad = { ...VALID_BODY, result: { ...VALID_BODY.result, ht_home: "molti" } };
  const { status, json } = await callHandlerDirect(mod.handler, bad);
  assertEquals(status, 400);
  assertEquals(json?.error, "Payload non valido");
  resetMockFactory();
});

Deno.test("400 con reason troppo corta", async () => {
  const adminClient = makeAdminClient();
  setMockFactory(() => adminClient.client);
  const mod = await importIndex("../admin-override/index.ts");
  const { status } = await callHandlerDirect(mod.handler, { ...VALID_BODY, reason: "no" });
  assertEquals(status, 400);
  resetMockFactory();
});

Deno.test("413 con body oltre 64KB", async () => {
  const adminClient = makeAdminClient();
  setMockFactory(() => adminClient.client);
  const mod = await importIndex("../admin-override/index.ts");
  const bigBody = JSON.stringify({
    ...VALID_BODY, events: Array(9000).fill(VALID_BODY.events[0]),
  });
  const res = await mod.handler(new Request("http://x/", {
    method: "POST",
    headers: { Authorization: ADMIN_JWT, "Content-Type": "application/json" },
    body: bigBody,
  }));
  assertEquals(res.status, 413);
  resetMockFactory();
});

Deno.test("200 e RPC chiamata senza p_actor (attore = auth.uid() lato SQL)", async () => {
  const adminClient = makeAdminClient();
  setMockFactory(() => adminClient.client);
  const mod = await importIndex("../admin-override/index.ts");
  const { status } = await callHandlerDirect(mod.handler, VALID_BODY);
  assertEquals(status, 200);
  const captured = adminClient.rpcCalls.find((r: any) => r.name === "admin_override_match");
  assertEquals(captured?.args?.p_provider_id, "M1");
  assertEquals(captured?.args?.p_result.ft_home, 2);
  assertEquals(captured?.args?.p_actor, undefined, "p_actor non deve essere passato");
  resetMockFactory();
});

// ---- helper ----
function makeAdminClient() {
  const rpcCalls: any[] = [];
  return {
    rpcCalls,
    client: {
      auth: { getUser: async () => ({ data: { user: { id: "admin-uuid" } }, error: null }) },
      from: () => {
        const chain: any = { select: () => chain, eq: () => chain };
        chain.single = async () => ({ data: { is_admin: true }, error: null });
        return chain;
      },
      rpc: async (name: string, args: any) => { rpcCalls.push({ name, args }); return { data: null, error: null }; },
    },
  };
}

async function callHandlerDirect(handler: (r: Request) => Promise<Response>, body: any) {
  const res = await handler(new Request("http://x/", {
    method: "POST",
    headers: { Authorization: ADMIN_JWT, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  }));
  return { status: res.status, json: await res.json().catch(() => null) };
}
