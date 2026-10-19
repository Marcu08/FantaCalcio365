// =============================================================
// FantaCalcio365 - Edge Function: provider-proxy
// Unico punto di accesso all'API calcistica. La chiave API vive
// SOLO qui come secret di Supabase: mai nell'app (§12).
// Deploy: supabase functions deploy provider-proxy
// =============================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const API_FOOTBALL_HOST = "v3.football.api-sports.io";

Deno.serve(async (req) => {
  try {
    // Verifica il JWT dell'utente: la funzione non è pubblica
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } }
    );
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return new Response("Unauthorized", { status: 401 });

    // Admin-only per l'ingestione risultati
    const { data: profile } = await supabase
      .from("profiles").select("is_admin").eq("id", user.id).single();
    const isAdmin = profile?.is_admin === true;
    const url = new URL(req.url);
    const mode = url.searchParams.get("mode") ?? "fixtures";

    // Lettura calendario/formazioni: permessa a tutti gli autenticati
    // Ingestione risultati/eventi: solo admin
    if (mode === "ingest" && !isAdmin) {
      return new Response("Forbidden", { status: 403 });
    }

    const endpoint = url.searchParams.get("endpoint") ?? "fixtures";
    const params = new URLSearchParams(url.searchParams);
    params.delete("mode"); params.delete("endpoint");

    const resp = await fetch(
      `https://${API_FOOTBALL_HOST}/v3/${endpoint}?${params}`,
      { headers: { "x-apisports-key": Deno.env.get("API_FOOTBALL_KEY")! } }
    );
    if (!resp.ok) {
      return new Response(JSON.stringify({ error: `Provider ${resp.status}` }), { status: 502 });
    }
    return Response.json(await resp.json(), {
      headers: { "Cache-Control": "public, max-age=60" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
