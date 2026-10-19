// =============================================================
// FantaCalcio365 - Edge Function: admin-override
// Correzione manuale di una partita da parte di un admin (FASE 2).
//  - richiede JWT valido e profiles.is_admin = true (verificato qui e in SQL)
//  - validazione zod dello schema, body max 64KB
//  - chiama admin_override_match (RPC) con il JWT dell'admin:
//    cosi' auth.uid() e is_admin() funzionano dentro la funzione SQL,
//    e actor_id dell'audit e' l'admin stesso.
// Deploy: supabase functions deploy admin-override
// =============================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { z } from "https://esm.sh/zod@3.23.8";

const MAX_BODY_BYTES = 64 * 1024;

const EventSchema = z.object({
  event_order: z.number().int().min(0),
  minute: z.number().int().min(0).max(130).nullable().optional(),
  type: z.enum(["GOAL", "YELLOW", "RED", "SUB_OUT", "SUB_IN"]),
  player: z.string().min(1).nullable().optional(),
  related_player: z.string().min(1).nullable().optional(),
  own_goal: z.boolean().optional(),
  penalty: z.boolean().optional(),
});

const OverrideSchema = z.object({
  provider_id: z.string().min(1),
  reason: z.string().min(5).max(500),
  result: z.object({
    status: z.enum(["FINISHED", "CONFIRMED"]),
    ht_home: z.number().int().min(0).max(20),
    ht_away: z.number().int().min(0).max(20),
    ht2_home: z.number().int().min(0).max(20),
    ht2_away: z.number().int().min(0).max(20),
    ft_home: z.number().int().min(0).max(20),
    ft_away: z.number().int().min(0).max(20),
  }),
  events: z.array(EventSchema).max(100),
});

export async function handler(req: Request): Promise<Response> {
  try {
    if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

    const raw = await req.text();
    if (new TextEncoder().encode(raw).byteLength > MAX_BODY_BYTES) {
      return Response.json({ error: "Body troppo grande (max 64KB)" }, { status: 413 });
    }

    const parsed = OverrideSchema.safeParse(JSON.parse(raw));
    if (!parsed.success) {
      return Response.json(
        { error: "Payload non valido", issues: parsed.error.issues },
        { status: 400 },
      );
    }
    const input = parsed.data;

    // JWT dell'admin: necessario perche' auth.uid() sia valorizzato
    // dentro admin_override_match (RPC eseguita con le sue credenziali)
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
    );
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return new Response("Unauthorized", { status: 401 });

    const { data: profile, error: profErr } = await supabase
      .from("profiles").select("is_admin").eq("id", user.id).single();
    if (profErr || profile?.is_admin !== true) {
      return new Response("Forbidden: solo admin", { status: 403 });
    }

    const { error: rpcErr } = await supabase.rpc("admin_override_match", {
      p_provider_id: input.provider_id,
      p_result: input.result,
      p_events: input.events,
      p_reason: input.reason,
      // Niente p_actor: dentro admin_override_match l'attore e' SEMPRE
      // auth.uid(), cioe' l'utente identificato da QUESTO JWT
    });
    if (rpcErr) {
      return Response.json({ error: rpcErr.message }, { status: 400 });
    }

    return Response.json({ ok: true, overridden: input.provider_id });
  } catch (e) {
    return Response.json({ error: String(e) }, { status: 500 });
  }
}

// Serve solo quando eseguita direttamente (non nei test)
if (import.meta.main) Deno.serve(handler);
