/**
 * Living Dex domain Worker.
 *
 * `GET /v1/enrich?taxonKey=&name=&lat=&lng=` returns real, grounded context for
 * a captured species: a rarity tier computed from GBIF occurrence density near
 * the sighting, plus a fact-sheet (taxonomy, IUCN status, a Wikipedia summary)
 * used to ground the Pokédex-entry narration. All upstreams are free/keyless.
 *
 * Rarity is deliberately grounded in real scarcity — never gacha'd — so the game
 * rewards genuine finds. Per the ethics guardrails, promoting an IUCN-threatened
 * taxon to "legendary" is display-only and never used to *target* the species;
 * that gating lives in the app.
 */

const GBIF = "https://api.gbif.org/v1";
const LOCAL_RADIUS_KM = 150;

type Rarity = "common" | "uncommon" | "rare" | "epic" | "legendary";

interface FactSheet {
  commonName: string | null;
  scientificName: string | null;
  kingdom: string | null;
  rank: string | null;
  iucnCategory: string | null;
  summary: string | null;
  localCount: number | null;
  globalCount: number | null;
}

interface EnrichResponse {
  taxonKey: number | null;
  rarity: Rarity;
  factSheet: FactSheet;
}

export default {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/") {
      return json({ service: "livingdex-worker", ok: true });
    }
    if (request.method === "GET" && url.pathname === "/v1/enrich") {
      return enrich(url).catch((e) => json({ error: String(e) }, 500));
    }
    return json({ error: "not found" }, 404);
  },
};

async function enrich(url: URL): Promise<Response> {
  const name = url.searchParams.get("name")?.trim() || null;
  const lat = numParam(url, "lat");
  const lng = numParam(url, "lng");
  let taxonKey = intParam(url, "taxonKey");

  let matched: any = null;
  if (taxonKey == null && name) {
    matched = await fetchJSON(`${GBIF}/species/match?name=${encodeURIComponent(name)}`);
    taxonKey = matched?.usageKey ?? null;
  }
  if (taxonKey == null) {
    return json({ error: "provide taxonKey or a resolvable name" }, 400);
  }

  const [species, iucn, localCount, globalCount] = await Promise.all([
    fetchJSON(`${GBIF}/species/${taxonKey}`),
    fetchJSON(`${GBIF}/species/${taxonKey}/iucnRedListCategory`).catch(() => null),
    lat != null && lng != null ? occurrenceCount(taxonKey, lat, lng) : Promise.resolve(null),
    occurrenceCount(taxonKey, null, null),
  ]);

  const scientificName = species?.canonicalName ?? matched?.canonicalName ?? name;
  const commonName = await vernacularName(taxonKey);
  const summary = scientificName ? await wikiSummary(scientificName) : null;
  const iucnCategory: string | null = iucn?.category ?? null;

  const rarity = computeRarity(localCount, globalCount, iucnCategory, lat != null);

  const body: EnrichResponse = {
    taxonKey,
    rarity,
    factSheet: {
      commonName,
      scientificName,
      kingdom: species?.kingdom ?? null,
      rank: species?.rank ?? null,
      iucnCategory,
      summary,
      localCount,
      globalCount,
    },
  };
  return json(body, 200, 60 * 60); // cache 1h at the edge
}

/** GBIF occurrence count within a radius of a point, or globally if no point. */
async function occurrenceCount(taxonKey: number, lat: number | null, lng: number | null): Promise<number | null> {
  let q = `${GBIF}/occurrence/search?taxonKey=${taxonKey}&limit=0`;
  if (lat != null && lng != null) {
    q += `&hasCoordinate=true&geoDistance=${lat},${lng},${LOCAL_RADIUS_KM}km`;
  }
  const data = await fetchJSON(q);
  return typeof data?.count === "number" ? data.count : null;
}

async function vernacularName(taxonKey: number): Promise<string | null> {
  const data = await fetchJSON(`${GBIF}/species/${taxonKey}/vernacularNames?limit=40`).catch(() => null);
  const names: any[] = data?.results ?? [];
  const english = names.find((n) => n.language === "eng" && n.vernacularName);
  return english?.vernacularName ?? names[0]?.vernacularName ?? null;
}

async function wikiSummary(title: string): Promise<string | null> {
  const data = await fetchJSON(
    `https://en.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(title)}`
  ).catch(() => null);
  const extract: string | undefined = data?.extract;
  if (!extract) return null;
  // First 2 sentences, so the fact-sheet stays tight for the narrator.
  const sentences = extract.match(/[^.!?]+[.!?]+/g) ?? [extract];
  return sentences.slice(0, 2).join(" ").trim();
}

/**
 * Rarity from real scarcity. With a location we use local occurrence density
 * within LOCAL_RADIUS_KM; without one we fall back to coarser global density.
 * An IUCN-threatened category promotes to legendary (display-only, app-gated).
 */
function computeRarity(
  local: number | null,
  global: number | null,
  iucn: string | null,
  hasLocation: boolean
): Rarity {
  // GBIF returns full category strings, e.g. "CRITICALLY_ENDANGERED".
  const threatened = new Set([
    "VULNERABLE", "ENDANGERED", "CRITICALLY_ENDANGERED", "EXTINCT_IN_THE_WILD", "EXTINCT",
  ]);
  if (iucn && threatened.has(iucn)) return "legendary";

  if (hasLocation && local != null) {
    if (local === 0) return global && global > 0 ? "epic" : "rare"; // out of local range = a vagrant
    if (local >= 1000) return "common";
    if (local >= 200) return "uncommon";
    if (local >= 20) return "rare";
    return "epic";
  }

  const count = global ?? 0;
  if (count >= 100_000) return "common";
  if (count >= 10_000) return "uncommon";
  if (count >= 1_000) return "rare";
  if (count >= 1) return "epic";
  return "legendary";
}

// MARK: helpers

async function fetchJSON(u: string): Promise<any> {
  const resp = await fetch(u, { headers: { "User-Agent": "livingdex-worker/1.0", Accept: "application/json" } });
  if (!resp.ok) throw new Error(`upstream ${resp.status} for ${u}`);
  return resp.json();
}

function numParam(url: URL, key: string): number | null {
  const v = url.searchParams.get(key);
  if (v == null || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function intParam(url: URL, key: string): number | null {
  const n = numParam(url, key);
  return n == null ? null : Math.trunc(n);
}

function json(body: unknown, status = 200, cacheSeconds = 0): Response {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (cacheSeconds > 0) headers["Cache-Control"] = `public, max-age=${cacheSeconds}`;
  return new Response(JSON.stringify(body), { status, headers });
}
