// =============================================================
// FantaCalcio365 - Test admin-release-override (deno test, mock)
// Verifica: 401 senza token, 403 non admin, 200 + RPC senza p_actor,
// 400 con JSON/payload non valido.
// =============================================================
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { setMockFactory, resetMockFactory } from "./supabase_mock.ts";
import { importIndex } from "./mocks.ts";

const ADMIN_JWT = "Bearer admin.jwt.token";
const VALID_BODY = {
  provider_id: "M1",
  reason: "Dati provider confermati corretti",
};

function makeAdminClient() {
  const rpcCalls: any[] = [];
  return {
    rpcCalls,
    client: {
      auth: { getUser: async (_t?: string) => ({ data: { user: { id: "admin-uuid" } }, error: null }) },
      from: () => {
        const chain: any = { select: () => chain, eq: () => chain };
        chain.single = async () => ({ data: { is_admin: true }, error: null });
        return chain;
      },
      rpc: async (name: string, args: any) => { rpcCalls.push({ name, args }); return { data: null, error: null }; },
    },
  };
}

async function call(handler: any, body: string, headers: Record<string, string> = {}) {
  const res = await handler(new Request("http://x/", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body,
  }));
  return { status: res.status, json: await res.json().catch(() => null) };
}

Deno.test("401 se token assente", async () => {
  setMockFactory(() => ({ auth: { getUser: async () => ({ data: { user: null }, error: {} }) } }));
  const mod = await importIndex("../admin-release-override/index.ts");
  const { status } = await call(mod.handler, JSON.stringify(VALID_BODY));
  assertEquals(status, 401);
  resetMockFactory();
});

Deno.test("403 se non admin", async () => {
  setMockFactory(() => ({
    auth: { getUser: async () => ({ data: { user: { id: "u1" } }, error: null }) },
    from: () => {
      const chain: any = { select: () => chain, eq: () => chain };
      chain.single = async () => ({ data: { is_admin: false }, error: null });
      return chain;
    },
  }));
  const mod = await importIndex("../admin-release-override/index.ts");
  const { status } = await call(mod.handler, JSON.stringify(VALID_BODY), { Authorization: ADMIN_JWT });
  assertEquals(status, 403);
  resetMockFactory();
});

Deno.test("400 con JSON non valido (errore generico)", async () => {
  const adminClient = makeAdminClient();
  setMockFactory(() => adminClient.client);
  const mod = await importIndex("../admin-release-override/index.ts");
  const { status, json } = await call(mod.handler, "{broken", { Authorization: ADMIN_JWT });
  assertEquals(status, 400);
  assertEquals(json?.error, "Payload non valido");
  resetMockFactory();
});

Deno.test("200 e RPC senza p_actor se admin", async () => {
  const adminClient = makeAdminClient();
  setMockFactory(() => adminClient.client);
  const mod = await importIndex("../admin-release-override/index.ts");
  const { status } = await call(mod.handler, JSON.stringify(VALID_BODY), { Authorization: ADMIN_JWT });
  assertEquals(status, 200);
  const captured = adminClient.rpcCalls.find((r: any) => r.name === "admin_release_override");
  assertEquals(captured?.args?.p_provider_id, "M1");
  assertEquals(captured?.args?.p_actor, undefined);
  resetMockFactory();
});
