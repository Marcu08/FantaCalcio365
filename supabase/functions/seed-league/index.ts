// =============================================================
// FantaCalcio365 - Edge Function: seed-league
// Popola seasons, teams, players e matches con i dati reali della
// Serie A (league 135) dalla stagione corrente di API-Football.
//
// Protezione: richiede l'header 'x-seed-secret' uguale al secret
// SEED_SECRET (riservato all'operatore, non agli utenti).
// Uso: supabase functions invoke seed-league --no-verify-jwt
//      -H 'x-seed-secret: ...'
// È idempotente: può essere rilanciata senza duplicare dati.
// =============================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const LEAGUE_ID = 135; // Serie A
// Piano gratuito API-Football: solo stagioni 2022-2024. Per la stagione
// corrente serve il piano a pagamento: cambiare SEASON al passaggio in produzione.
const SEASON = 2023;   // stagione 2023/24

const POSITION_MAP: Record<string, string> = {
  "Goalkeeper": "GK", "Defender": "DF", "Midfielder": "MF", "Attacker": "FW",
};

const STATUS_MAP: Record<string, string> = {
  "NS": "SCHEDULED", "TBD": "SCHEDULED",
  "1H": "LIVE", "HT": "LIVE", "2H": "LIVE", "ET": "LIVE", "BT": "LIVE", "P": "LIVE",
  "FT": "FINISHED", "AET": "FINISHED", "PEN": "FINISHED",
  "PST": "POSTPONED", "CANC": "CANCELLED", "ABD": "POSTPONED", "SUSP": "POSTPONED",
};

Deno.serve(async (req) => {
  if (req.headers.get("x-seed-secret") !== Deno.env.get("SEED_SECRET")) {
    return new Response("Forbidden", { status: 403 });
  }
  // ?only=fixtures per evitare il rate limit: salta squadre e rose
  const only = new URL(req.url).searchParams.get("only");

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const key = Deno.env.get("API_FOOTBALL_KEY")!;
  const headers = { "x-apisports-key": key };
  const api = (path: string) =>
    fetch(`https://v3.football.api-sports.io/${path}`, { headers })
      .then(r => r.json());

  try {
    // 1. Stagione ------------------------------------------------
    const { data: season } = await admin.from("seasons")
      .upsert({ name: `Serie A ${SEASON}/${String(SEASON + 1).slice(2)}` },
              { onConflict: "name" })
      .select("id").single();

    // 2. Squadre (saltata con ?only=bonus) --------------------------
    let teamsRes: any = { response: [], errors: [] };
    if (only !== "bonus") {
      teamsRes = await api(`teams?league=${LEAGUE_ID}&season=${SEASON}`);
      const teamRows = (teamsRes.response ?? []).map((t: any) => ({
      provider_id: String(t.team.id),
      name: t.team.name,
      short_name: t.team.code ?? t.team.name.slice(0, 3).toUpperCase(),
      logo_url: t.team.logo,
    }));
    if (teamRows.length) {
      await admin.from("teams").upsert(teamRows, { onConflict: "provider_id" });
    }
    }
    const { data: teamMap } = await admin.from("teams").select("id, provider_id");
    const teamByProvider = new Map((teamMap ?? []).map((t: any) => [t.provider_id, t.id]));

    // 3. Rose giocatori (1 richiesta per squadra) -------------------
    let playersSeeded = 0;
    for (const [providerId, internalId] of only ? [] : teamByProvider) {
      const squadRes = await api(`players/squads?team=${providerId}`);
      const squad = squadRes.response?.[0]?.players ?? [];
      const rows = squad.map((p: any) => ({
        provider_id: String(p.id),
        team_id: internalId,
        name: p.name,
        position: POSITION_MAP[p.position] ?? "MF",
        is_active: true,
      }));
      if (rows.length) {
        await admin.from("players").upsert(rows, { onConflict: "provider_id" });
        playersSeeded += rows.length;
      }
      // rispetta i limiti del piano gratuito
      await new Promise(r => setTimeout(r, 350));
    }

    // 4. Calendario (saltato con ?only=bonus) -----------------------
    const FUTURE_FROM_MATCHDAY = 9;
    const SHIFT_MS = 1096 * 24 * 60 * 60 * 1000; // ~3 anni
    const fixRes = only === "bonus"
      ? { response: [], errors: [] }
      : await api(`fixtures?league=${LEAGUE_ID}&season=${SEASON}`);
    const matchRows = (fixRes.response ?? []).map((f: any) => {
      const round = parseInt(String(f.league.round).replace(/\D/g, "")) || 0;
      const ht = f.score?.halftime;
      const ft = f.score?.fulltime;
      const status = round >= FUTURE_FROM_MATCHDAY
        ? "SCHEDULED"
        : (STATUS_MAP[f.fixture.status?.short] ?? "SCHEDULED");
      const homeId = teamByProvider.get(String(f.teams.home.id));
      const awayId = teamByProvider.get(String(f.teams.away.id));
      if (!homeId || !awayId) return null;
    const bothPlayed = f.fixture.status?.short === "FT" && round < FUTURE_FROM_MATCHDAY;
    const isFuture = round >= FUTURE_FROM_MATCHDAY;
      const kickoff = isFuture
        ? new Date(new Date(f.fixture.date).getTime() + SHIFT_MS).toISOString()
        : f.fixture.date;
      return {
        provider_id: String(f.fixture.id),
        season_id: season!.id,
        matchday: round,
        home_team_id: homeId,
        away_team_id: awayId,
        kickoff_at: kickoff,
        status,
        ht_home_goals: bothPlayed ? ht?.home ?? null : null,
        ht_away_goals: bothPlayed ? ht?.away ?? null : null,
        // §4: il secondo tempo conta SOLO i gol della seconda frazione
        ht2_home_goals: bothPlayed && ht?.home != null && ft?.home != null
          ? ft.home - ht.home : null,
        ht2_away_goals: bothPlayed && ht?.away != null && ft?.away != null
          ? ft.away - ht.away : null,
        ft_home_goals: ft?.home ?? null,
        ft_away_goals: ft?.away ?? null,
        data_confirmed_at: bothPlayed ? new Date().toISOString() : null,
      };
    }).filter(Boolean);

    if (matchRows.length) {
      // in blocchi per evitare payload troppo grandi
      for (let i = 0; i < matchRows.length; i += 50) {
        await admin.from("matches").upsert(matchRows.slice(i, i + 50),
          { onConflict: "provider_id" });
      }
    }

    // 5. Bonus semplificati congelati per le partite FUTURE (demo).
    // In produzione il valore arriva dal modello statistico al momento
    // del blocco (freeze_matchday_bonuses); qui lo si approssima per ruolo:
    // gol: FW 10, MF 8, DF 6, GK 5 — porta inviolata: GK 10, DF 6.
    const { data: futureMatches } = await admin.from("matches")
      .select("id").eq("status", "SCHEDULED").gte("kickoff_at", new Date().toISOString());
    const { data: allPlayers } = await admin.from("players").select("id, position");
    if (futureMatches?.length && allPlayers?.length) {
      const golPts: Record<string, number> = { FW: 10, MF: 8, DF: 6, GK: 5 };
      const csPts: Record<string, number> = { GK: 10, DF: 6, MF: 0, FW: 0 };
      const stats = futureMatches.flatMap((m: any) =>
        allPlayers.map((p: any) => ({
          match_id: m.id,
          player_id: p.id,
          played_minutes: 0,
          goals: 0,
          conceded_goals: 0,
          gol_bonus_pts: golPts[p.position] ?? 6,
          clean_sheet_bonus_pts: csPts[p.position] ?? 0,
          frozen_at: new Date().toISOString(),
        }))
      );
      for (let i = 0; i < stats.length; i += 500) {
        await admin.from("player_match_stats").upsert(stats.slice(i, i + 500));
      }
    }

    return Response.json({
      ok: true,
      teams: (teamsRes.response ?? []).length,
      players: playersSeeded,
      matches: matchRows.length,
      future_matches: futureMatches?.length ?? 0,
      debug: {
        teams_errors: teamsRes.errors ?? null,
        fixtures_count: fixRes.response?.length ?? 0,
        fixtures_errors: fixRes.errors ?? null,
      },
    });
  } catch (e) {
    return Response.json({ error: String(e) }, { status: 500 });
  }
});
