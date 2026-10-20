// Client unico API-Football. Host v3.football.api-sports.io, path senza /v3/.
export const API_FOOTBALL_BASE = "https://v3.football.api-sports.io";

export const ALLOWED_ENDPOINTS = new Set([
  "fixtures",
  "fixtures/events",
  "fixtures/lineups",
  "fixtures/statistics",
  "players/squads",
  "players",
  "teams",
  "standings",
]);

export function normalizeEndpoint(raw: string): string {
  return raw.replace(/^\/+/, "").replace(/^v3\//, "");
}

export function apiFootballUrl(endpoint: string, params: URLSearchParams = new URLSearchParams()): string {
  const path = normalizeEndpoint(endpoint);
  if (!ALLOWED_ENDPOINTS.has(path)) {
    throw new Error(`Endpoint non consentito: ${path}`);
  }
  const qs = params.toString();
  return qs ? `${API_FOOTBALL_BASE}/${path}?${qs}` : `${API_FOOTBALL_BASE}/${path}`;
}

export function apiFootballHeaders(): HeadersInit {
  const key = Deno.env.get("API_FOOTBALL_KEY");
  if (!key) throw new Error("API_FOOTBALL_KEY mancante");
  return { "x-apisports-key": key };
}
