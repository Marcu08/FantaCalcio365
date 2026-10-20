import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { apiFootballUrl, normalizeEndpoint } from "../_shared/api-football.ts";

Deno.test("path fixtures senza /v3/ duplicato", () => {
  const url = apiFootballUrl("fixtures", new URLSearchParams({ id: "PFIN" }));
  assertEquals(url, "https://v3.football.api-sports.io/fixtures?id=PFIN");
  assertEquals(url.includes("/v3/fixtures"), false);
});

Deno.test("normalizza endpoint con prefisso v3/", () => {
  assertEquals(normalizeEndpoint("v3/fixtures"), "fixtures");
  const url = apiFootballUrl("v3/fixtures", new URLSearchParams({ id: "1" }));
  assertEquals(url, "https://v3.football.api-sports.io/fixtures?id=1");
});

Deno.test("rifiuta endpoint fuori allowlist", () => {
  assertThrows(() => apiFootballUrl("https://evil.example/x"));
  assertThrows(() => apiFootballUrl("fixtures/../secrets"));
});
