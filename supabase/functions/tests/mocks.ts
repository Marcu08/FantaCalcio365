// =============================================================
// FantaCalcio365 - Edge Function tests (deno test, client mockato)
// Esecuzione: deno test --allow-all --import-map supabase/functions/tests/import_map.json supabase/functions/tests/
// Il mock del modulo supabase-js vive in supabase_mock.ts (rimappato
// dall'import map, senza librerie di mocking esterne).
// =============================================================

// Cache-busting: ogni test re-importa la funzione per riprendere il suo mock
let importCounter = 0;
export async function importIndex(path: string) {
  return await import(`${path}?case=${++importCounter}`);
}
