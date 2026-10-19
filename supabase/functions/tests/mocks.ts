// =============================================================
// FantaCalcio365 - Edge Function tests (deno test, client mockato)
// Esecuzione: deno test --allow-all supabase/functions/tests/
// =============================================================
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { mock } from "jsr:@std/mock@1";

// ---- helper: mock client Supabase -----------------------------
export type RpcCall = { name: string; args: any };

export function makeMockClient(opts: {
  user?: { id: string } | null;        // null → getUser fallisce
  isAdmin?: boolean;
  profileError?: boolean;
  onRpc?: (call: RpcCall) => void;
}) {
  const rpcCalls: RpcCall[] = [];
  const client = {
    auth: {
      getUser: async () =>
        opts.user
          ? { data: { user: opts.user }, error: null }
          : { data: { user: null }, error: { message: "bad jwt" } },
    },
    from: (_table: string) => {
      const chain: any = {
        select: () => chain,
        eq: () => chain,
        single: async () =>
          opts.profileError
            ? { data: null, error: { message: "no profile" } }
            : { data: { is_admin: opts.isAdmin === true }, error: null },
      };
      return chain;
    },
    rpc: async (name: string, args: any) => {
      const call = { name, args };
      rpcCalls.push(call);
      opts.onRpc?.(call);
      return { data: null, error: null };
    },
  };
  return { client, rpcCalls };
}

// Mock del modulo supabase-js PRIMA dell'import della funzione testata
export function mockSupabaseModule(clientFactory: () => any) {
  const m: any = mock.module("https://esm.sh/@supabase/supabase-js@2", () => ({
    createClient: (_u: string, _k: string, _o?: any) => clientFactory(),
  }));
  // std mock.module restituisce un oggetto con restore() oppure una funzione
  return typeof m === "function" ? m : () => m?.restore?.();
}

export async function callHandler(handler: any, body: any, extraHeaders: Record<string, string> = {}) {
  const req = new Request("http://x/", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...extraHeaders },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
  const res = await handler(req);
  return { status: res.status, json: await res.json().catch(() => null) };
}

// Cache-busting: ogni test re-importa la funzione per riprendere il suo mock
let importCounter = 0;
export async function importIndex(path: string) {
  return await import(`${path}?case=${++importCounter}`);
}

export { assert, assertEquals, assertStringIncludes };
