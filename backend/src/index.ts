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
// Humans + common domestics dominate occurrence density in populated areas and
// aren't wild "catches" — keep them out of the Regional Dex.
const EXCLUDED_TAXA = new Set<number>([
  2436436,  // Homo sapiens
  6164210,  // Canis lupus familiaris
  2435035,  // Felis catus
  2441022,  // Bos taurus
  2441176,  // Ovis aries
  2441119,  // Sus scrofa (incl. domestic pig)
  9761484,  // Gallus gallus domesticus
]);

type Rarity = "common" | "uncommon" | "rare" | "epic" | "legendary";

interface FactSheet {
  commonName: string | null;
  scientificName: string | null;
  kingdom: string | null;
  family: string | null;
  order: string | null;
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

type RateLimit = {
  limit(config: { key: string }): Promise<{ success: boolean }>;
};

interface Env {
  RATE_LIMITER?: RateLimit;
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/") {
      return json({ service: "livingdex-worker", ok: true });
    }

    const limited = await rateLimited(request, env).catch(() => null);
    if (limited) return limited;

    if (request.method === "GET" && url.pathname === "/v1/enrich") {
      return withCache(request, ctx, LOCATION_GRID_DECIMALS, () => enrich(url)).catch(errorResponse);
    }
    if (request.method === "GET" && url.pathname === "/v1/region") {
      return withCache(request, ctx, REGION_GRID_DECIMALS, () => region(url)).catch(errorResponse);
    }
    if (request.method === "GET" && url.pathname === "/v1/detail") {
      return withCache(request, ctx, LOCATION_GRID_DECIMALS, () => detail(url)).catch(errorResponse);
    }
    return json({ error: "not found" }, 404);
  },
};

const LOCATION_GRID_DECIMALS = 1;
const REGION_GRID_DECIMALS = 1;
const REGION_CONCURRENCY = 8;
const UPSTREAM_TIMEOUT_MS = 5000;

/**
 * Soft per-IP rate limit via the native Workers rate-limiting binding (no extra
 * paid infra). Absent in local dev / if unbound, so it degrades to a no-op.
 */
async function rateLimited(request: Request, env: Env): Promise<Response | null> {
  const limiter = env.RATE_LIMITER;
  if (!limiter) return null;
  const ip = request.headers.get("CF-Connecting-IP") ?? "anon";
  const { success } = await limiter.limit({ key: ip });
  return success ? null : json({ error: "rate limited" }, 429);
}

/**
 * Serve a 200 handler response from Cloudflare's Cache API keyed on a normalized
 * URL (lat/lng snapped to a grid, name lowercased) so first-hit/cross-device
 * requests reuse the aggregation instead of re-fanning every upstream. The edge
 * cache honors the response's own Cache-Control max-age for TTL.
 */
async function withCache(
  request: Request,
  ctx: ExecutionContext,
  gridDecimals: number,
  producer: () => Promise<Response>
): Promise<Response> {
  const cache = caches.default;
  const key = cacheKeyFor(request.url, gridDecimals);
  const hit = await cache.match(key);
  if (hit) return hit;
  const resp = await producer();
  if (resp.status === 200 && resp.headers.has("Cache-Control")) {
    ctx.waitUntil(cache.put(key, resp.clone()));
  }
  return resp;
}

function cacheKeyFor(rawUrl: string, gridDecimals: number): string {
  const src = new URL(rawUrl);
  const key = new URL("https://livingdex-cache.internal" + src.pathname);
  for (const name of [...src.searchParams.keys()].sort()) {
    let v = src.searchParams.get(name) ?? "";
    if (name === "lat" || name === "lng") {
      const n = Number(v);
      if (Number.isFinite(n)) v = snapToGrid(n, gridDecimals).toFixed(gridDecimals);
    } else if (name === "name") {
      v = v.trim().toLowerCase();
    }
    key.searchParams.append(name, v);
  }
  return key.toString();
}

function snapToGrid(n: number, decimals: number): number {
  const factor = 10 ** decimals;
  return Math.round(n * factor) / factor;
}

/** Generic 500 that hides upstream URLs / raw error strings; the real error is logged. */
function errorResponse(e: unknown): Response {
  console.error("livingdex-worker error:", e);
  return json({ error: "upstream unavailable" }, 500);
}

async function enrich(url: URL): Promise<Response> {
  const name = url.searchParams.get("name")?.trim() || null;
  const lat = numParam(url, "lat");
  const lng = numParam(url, "lng");
  let taxonKey = intParam(url, "taxonKey");

  let matched: any = null;
  if (taxonKey == null && name) {
    matched = await fetchJSON(`${GBIF}/species/match?name=${encodeURIComponent(name)}`);
    // Only trust a confident species-level match. A hallucinated/misspelled binomial
    // otherwise fuzzy- or higher-rank-matches to a neighbouring taxon and every fact
    // (name, rarity, IUCN, summary) resolves to the WRONG species.
    const speciesLevel = matched?.rank === "SPECIES" || matched?.rank === "SUBSPECIES";
    const ok = speciesLevel &&
      (matched?.matchType === "EXACT" ||
        (matched?.matchType === "FUZZY" && (matched?.confidence ?? 0) >= 95));
    taxonKey = ok ? matched?.usageKey ?? null : null;
  }
  if (taxonKey == null) {
    // 404 = "we can't confirm this species" (distinct from a 5xx upstream error);
    // the app treats it as unverified rather than a hard failure.
    return json({ error: "unresolved species", resolved: false }, 404);
  }

  // Every upstream is independently best-effort: a single GBIF hiccup (e.g. a
  // 429 on the occurrence search) must not sink the whole fact-sheet, so each
  // failure degrades to null and the response is still useful.
  const [species, iucn, localCount, globalCount, commonName] = await Promise.all([
    fetchJSON(`${GBIF}/species/${taxonKey}`).catch(() => null),
    fetchJSON(`${GBIF}/species/${taxonKey}/iucnRedListCategory`).catch(() => null),
    lat != null && lng != null ? occurrenceCount(taxonKey, lat, lng).catch(() => null) : Promise.resolve(null),
    occurrenceCount(taxonKey, null, null).catch(() => null),
    vernacularName(taxonKey),
  ]);

  const scientificName = species?.canonicalName ?? matched?.canonicalName ?? name;
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
      family: species?.family ?? null,
      order: species?.order ?? null,
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
    q += `&hasCoordinate=true&geoDistance=${lat},${lng},${LOCAL_RADIUS_KM}km&basisOfRecord=HUMAN_OBSERVATION`;
  }
  const data = await fetchJSON(q);
  return typeof data?.count === "number" ? data.count : null;
}

async function vernacularName(taxonKey: number): Promise<string | null> {
  const data = await fetchJSON(`${GBIF}/species/${taxonKey}/vernacularNames?limit=40`).catch(() => null);
  const eng: string[] = (data?.results ?? [])
    .filter((n: any) => n.language === "eng" && typeof n.vernacularName === "string")
    .map((n: any) => n.vernacularName.trim());
  // Skip banding codes ("GRTI") and acronyms — an all-caps token with no space.
  const proper = eng.find((n) => /\s/.test(n) || n !== n.toUpperCase());
  const name = proper ?? null;
  if (!name) return null;
  // Title-case an all-lowercase vernacular ("common buzzard" -> "Common Buzzard");
  // leave already-capitalized names alone so "Steller's Jay" isn't corrupted.
  return /[A-Z]/.test(name) ? name : name.replace(/\b\w/g, (c) => c.toUpperCase());
}

async function wikiSummary(title: string): Promise<string | null> {
  const data = await fetchJSON(
    `https://en.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(title)}`
  ).catch(() => null);
  // Drop disambiguation / no-extract stubs — only real article summaries ground well.
  if (data?.type && data.type !== "standard") return null;
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

  // No location: coarser global-density fallback. A missing count (lookup
  // failed) is *unknown*, not a jackpot — default to uncommon rather than
  // minting a legendary from a data gap. Legendary comes only from IUCN status.
  if (global == null) return "uncommon";
  if (global >= 100_000) return "common";
  if (global >= 10_000) return "uncommon";
  if (global >= 1_000) return "rare";
  return "epic";
}

/**
 * The species that plausibly occur near a point — the player's "Regional Dex".
 * Uses a GBIF facet on speciesKey within LOCAL_RADIUS_KM (ranked by how many
 * records exist locally), then resolves each to a name + realm + rarity. Cached
 * hard at the edge since a coarse area's species list is stable.
 */
async function region(url: URL): Promise<Response> {
  const lat = numParam(url, "lat");
  const lng = numParam(url, "lng");
  const limit = Math.min(120, intParam(url, "limit") ?? 80);
  if (lat == null || lng == null) return json({ error: "lat and lng required" }, 400);

  // Wild things only: HUMAN_OBSERVATION drops specimen/fossil noise; fetch extra
  // and trim, since humans + domestics are filtered out below.
  const facetUrl =
    `${GBIF}/occurrence/search?hasCoordinate=true&geoDistance=${lat},${lng},${LOCAL_RADIUS_KM}km` +
    `&basisOfRecord=HUMAN_OBSERVATION&facet=speciesKey&facetLimit=${limit + 20}&limit=0`;
  const data = await fetchJSON(facetUrl);
  const counts: Array<{ name: string; count: number }> = data?.facets?.[0]?.counts ?? [];

  // Bounded pool caps simultaneous GBIF subrequests; the two per-item lookups
  // run in parallel to halve per-item latency.
  const resolved = await mapPool(counts, REGION_CONCURRENCY, async (c) => {
    const key = Number(c.name);
    if (!Number.isFinite(key) || EXCLUDED_TAXA.has(key)) return null;
    const [sp, commonName] = await Promise.all([
      fetchJSON(`${GBIF}/species/${key}`).catch(() => null),
      vernacularName(key),
    ]);
    const scientificName = sp?.canonicalName ?? sp?.scientificName;
    if (!scientificName || sp?.rank !== "SPECIES") return null;
    return {
      taxonKey: key,
      commonName,
      scientificName,
      realm: kingdomToRealm(sp?.kingdom),
      rarity: computeRarity(c.count, null, null, true),
      localCount: c.count,
    };
  });
  const species = resolved.filter((s) => s !== null).slice(0, limit);

  return json({ count: species.length, species }, 200, 24 * 60 * 60);
}

/**
 * Card-detail extras, lazy-loaded when a card opens (kept out of the capture
 * loop): a playable "call" for the species from Xeno-canto, filtered to
 * commercial-safe (non-NonCommercial) Creative Commons licences.
 */
async function detail(url: URL): Promise<Response> {
  const name = url.searchParams.get("name")?.trim();
  if (!name) return json({ error: "name required" }, 400);
  // Prefer commercial-safe Wikimedia Commons audio; fall back to any non-NC
  // Xeno-canto recording. Best-effort — many species simply have no safe call.
  const call = (await commonsCall(name).catch(() => null)) ?? (await xenoCantoCall(name).catch(() => null));
  return json({ call }, 200, 7 * 24 * 60 * 60);
}

interface Call {
  url: string;
  recordist: string | null;
  license: string | null;
  source: string;
}

/** Wikimedia Commons audio (CC BY-SA / CC0 / public domain — commercial-safe). */
async function commonsCall(scientificName: string): Promise<Call | null> {
  const api =
    `https://commons.wikimedia.org/w/api.php?action=query&format=json&origin=*` +
    `&generator=search&gsrsearch=${encodeURIComponent(`filetype:audio ${scientificName}`)}` +
    `&gsrnamespace=6&gsrlimit=10&prop=imageinfo&iiprop=url|mime|extmetadata`;
  const data = await fetchJSON(api);
  const pages: any[] = Object.values(data?.query?.pages ?? {});
  for (const p of pages) {
    const info = p?.imageinfo?.[0];
    if (!info || typeof info.mime !== "string" || !info.mime.startsWith("audio")) continue;
    const lic = (info.extmetadata?.LicenseShortName?.value ?? "").toLowerCase();
    const safe = lic.includes("cc0") || lic.includes("public domain") ||
      ((lic.includes("cc by") || lic.includes("cc-by")) && !lic.includes("nc"));
    if (!safe || !info.url) continue;
    return {
      url: info.url,
      recordist: info.extmetadata?.Artist?.value?.replace(/<[^>]+>/g, "").trim() || null,
      license: info.extmetadata?.LicenseShortName?.value ?? null,
      source: "Wikimedia Commons",
    };
  }
  return null;
}

async function xenoCantoCall(scientificName: string): Promise<Call | null> {
  const q = encodeURIComponent(`${scientificName} q:A`);
  const data = await fetchJSON(`https://xeno-canto.org/api/2/recordings?query=${q}`);
  const recordings: any[] = data?.recordings ?? [];
  const rec = recordings.find(
    (r) => r.file && typeof r.lic === "string" && !r.lic.toLowerCase().includes("-nc-")
  );
  if (!rec) return null;
  const fileUrl = rec.file.startsWith("//") ? `https:${rec.file}` : rec.file;
  const license = typeof rec.lic === "string" ? (rec.lic.startsWith("//") ? `https:${rec.lic}` : rec.lic) : null;
  return { url: fileUrl, recordist: rec.rec ?? null, license, source: "Xeno-canto" };
}

function kingdomToRealm(kingdom: string | null | undefined): string {
  switch (kingdom) {
    case "Animalia": return "animals";
    case "Plantae": return "plants";
    case "Fungi": return "fungi";
    case "Protozoa":
    case "Chromista": return "protists";
    default: return "other";
  }
}

// MARK: helpers

/**
 * Run `fn` over `items` with at most `concurrency` in flight, preserving order.
 * Bounds the total simultaneous subrequests a single handler can launch.
 */
async function mapPool<T, R>(
  items: readonly T[],
  concurrency: number,
  fn: (item: T) => Promise<R>
): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let next = 0;
  async function worker(): Promise<void> {
    while (true) {
      const i = next++;
      if (i >= items.length) return;
      results[i] = await fn(items[i]);
    }
  }
  const size = Math.max(1, Math.min(concurrency, items.length));
  await Promise.all(Array.from({ length: size }, () => worker()));
  return results;
}

/** GET JSON from an upstream, aborting after UPSTREAM_TIMEOUT_MS so hung calls hit their .catch paths. */
async function fetchJSON(u: string): Promise<any> {
  const resp = await fetch(u, {
    headers: { "User-Agent": "livingdex-worker/1.0", Accept: "application/json" },
    signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
  });
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
