// =============================================================
// FantaCalcio365 - Test admin-override (deno test, mock Supabase)
// Verifica: zod (body malformati/64KB), 401 senza JWT, 403 non-admin,
// 200 + RPC con p_actor per admin.
// =============================================================
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { makeMockClient, mockSupabaseModule, callHandler, importIndex } from "./mocks.ts";

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
  const { client } = makeMockClient({ user: null });
  const undo = mockSupabaseModule(() => client);
  const mod = await importIndex("../admin-override/index.ts");
  const res = await mod.handler(new Request("http://x/", {
    method: "POST", body: JSON.stringify(VALID_BODY),
  }));
  assertEquals(res.status, 401);
  undo();
});

Deno.test("403 se utente non admin", async () => {
  const { client } = makeMockClient({ user: { id: "u1" }, isAdmin: false });
  const undo = mockSupabaseModule(() => client);
  const mod = await importIndex("../admin-override/index.ts");
  const { status } = await callHandler(mod.handler, VALID_BODY, { Authorization: ADMIN_JWT });
  assertEquals(status, 403);
  undo();
});

Deno.test("403 se profilo assente", async () => {
  const { client } = makeMockClient({ user: { id: "u2" }, profileError: true });
  const undo = mockSupabaseModule(() => client);
  const mod = await importIndex("../admin-override/index.ts");
  const { status } = await callHandler(mod.handler, VALID_BODY, { Authorization: ADMIN_JWT });
  assertEquals(status, 403);
  undo();
});

Deno.test("400 con body malformato (zod)", async () => {
  const { client } = makeMockClient({ user: { id: "admin" }, isAdmin: true });
  const undo = mockSupabaseModule(() => client);
  const mod = await importIndex("../admin-override/index.ts");
  const bad = { ...VALID_BODY, result: { ...VALID_BODY.result, ht_home: "molti" } };
  const { status, json } = await callHandler(mod.handler, bad, { Authorization: ADMIN_JWT });
  assertEquals(status, 400);
  assertEquals(json?.error, "Payload non valido");
  undo();
});

Deno.test("400 con reason troppo corta", async () => {
  const { client } = makeMockClient({ user: { id: "admin" }, isAdmin: true });
  const undo = mockSupabaseModule(() => client);
  const mod = await importIndex("../admin-override/index.ts");
  const { status } = await callHandler(
    mod.handler, { ...VALID_BODY, reason: "no" }, { Authorization: ADMIN_JWT });
  assertEquals(status, 400);
  undo();
});

Deno.test("413 con body oltre 64KB", async () => {
  const { client } = makeMockClient({ user: { id: "admin" }, isAdmin: true });
  const undo = mockSupabaseModule(() => client);
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
  undo();
});

Deno.test("200 e RPC chiamata con p_actor se admin", async () => {
  let captured: any = null;
  const { client } = makeMockClient({
    user: { id: "admin-uuid" }, isAdmin: true,
    onRpc: (c) => { if (c.name === "admin_override_match") captured = c.args; },
  });
  const undo = mockSupabaseModule(() => client);
  const mod = await importIndex("../admin-override/index.ts");
  const { status } = await callHandler(mod.handler, VALID_BODY, { Authorization: ADMIN_JWT });
  assertEquals(status, 200);
  assertEquals(captured?.p_actor, "admin-uuid");
  assertEquals(captured?.p_provider_id, "M1");
  assertEquals(captured?.p_result.ft_home, 2);
  undo();
});
