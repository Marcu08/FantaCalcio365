// =============================================================
// FantaCalcio365 - Mock del modulo supabase-js per i test Deno.
// L'import map (tests/import_map.json) rimappa
//   https://esm.sh/@supabase/supabase-js@2 → questo file,
// cosi' le Edge Functions ricevono un client mockato senza librerie esterne.
// =============================================================

type ClientFactory = () => any;

let factory: ClientFactory = () => ({
  auth: { getUser: async () => ({ data: { user: null }, error: null }) },
  from: () => { throw new Error("client supabase non configurato nel test"); },
  rpc: async () => ({ data: null, error: null }),
});

export function setMockFactory(f: ClientFactory) {
  factory = f;
}

export function resetMockFactory() {
  factory = () => ({
    auth: { getUser: async () => ({ data: { user: null }, error: null }) },
    from: () => { throw new Error("client supabase non configurato nel test"); },
    rpc: async () => ({ data: null, error: null }),
  });
}

// Firma compatibile con supabase-js@2 (url, key, options)
export function createClient(_url: string, _key: string, _opts?: any) {
  return factory();
}
