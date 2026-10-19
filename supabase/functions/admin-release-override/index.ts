// =============================================================
// FantaCalcio365 - Edge Function: admin-release-override
// Rilascia l'override manuale di una partita: il cron riprende la
// sincronizzazione dal provider e ricalcola i punteggi (FASE 3).
// Stessa catena di sicurezza di admin-override:
//  - chiave anon + JWT dell'utente (mai service role)
//  - 401 senza token, 403 se non admin
//  - la RPC admin_release_override riverifica is_admin() con auth.uid()
// Deploy: supabase functions deploy admin-release-override
// =============================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { z } from "https://esm.sh/zod@3.23.8";

const ReleaseSchema = z.object({
  provider_id: z.string().min(1),
  reason: z.string().min(5).max(500),
});

export async function handler(req: Request): Promise<Response> {
  try {
    if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

    const raw = await req.text();
    let parsedJson: unknown;
    try {
      parsedJson = JSON.parse(raw);
    } catch {
      return Response.json({ error: "Payload non valido" }, { status: 400 });
    }

    const parsed = ReleaseSchema.safeParse(parsedJson);
    if (!parsed.success) {
      return Response.json({ error: "Payload non valido", issues: parsed.error.issues }, { status: 400 });
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : null;
    if (!token) return new Response("Unauthorized", { status: 401 });

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
    );
    const { data: { user } } = await supabase.auth.getUser(token);
    if (!user) return new Response("Unauthorized", { status: 401 });

    const { data: profile, error: profErr } = await supabase
      .from("profiles").select("is_admin").eq("id", user.id).single();
    if (profErr || profile?.is_admin !== true) {
      return new Response("Forbidden: solo admin", { status: 403 });
    }

    const { error: rpcErr } = await supabase.rpc("admin_release_override", {
      p_provider_id: parsed.data.provider_id,
      p_reason: parsed.data.reason,
    });
    if (rpcErr) {
      return Response.json({ error: rpcErr.message }, { status: 400 });
    }

    return Response.json({ ok: true, released: parsed.data.provider_id });
  } catch (e) {
    return Response.json({ error: String(e) }, { status: 500 });
  }
}

// Serve solo quando eseguita direttamente (non nei test)
if (import.meta.main) Deno.serve(handler);
