// =============================================================
// FantaCalcio365 - Edge Function: provider-proxy
// Unico punto di accesso all'API calcistica. Allowlist di path.
// Deploy: supabase functions deploy provider-proxy
// =============================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { apiFootballHeaders, apiFootballUrl } from "../_shared/api-football.ts";

Deno.serve(async (req) => {
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return new Response("Unauthorized", { status: 401 });

    const { data: profile } = await supabase
      .from("profiles").select("is_admin").eq("id", user.id).single();
    const isAdmin = profile?.is_admin === true;
    const url = new URL(req.url);
    const mode = url.searchParams.get("mode") ?? "fixtures";

    if (mode === "ingest" && !isAdmin) {
      return new Response("Forbidden", { status: 403 });
    }

    const endpoint = url.searchParams.get("endpoint") ?? "fixtures";
    const params = new URLSearchParams(url.searchParams);
    params.delete("mode");
    params.delete("endpoint");

    let target: string;
    try {
      target = apiFootballUrl(endpoint, params);
    } catch (e) {
      return Response.json({ error: String(e) }, { status: 400 });
    }

    const resp = await fetch(target, { headers: apiFootballHeaders() });
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
