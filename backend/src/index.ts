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

    if (request.method === "GET" && url.pathname === "/v1/enrich") {
      return withCache(request, env, ctx, LOCATION_GRID_DECIMALS, () => enrich(url)).catch(errorResponse);
    }
    if (request.method === "GET" && url.pathname === "/v1/region") {
      return withCache(request, env, ctx, REGION_GRID_DECIMALS, () => region(url)).catch(errorResponse);
    }
    if (request.method === "GET" && url.pathname === "/v1/detail") {
      return withCache(request, env, ctx, LOCATION_GRID_DECIMALS, () => detail(url)).catch(errorResponse);
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
 *
 * The per-IP rate limit is charged only on a cache MISS: cached serves touch no
 * upstream, so they must not consume the budget that exists to protect the GBIF
 * fan-out.
 */
async function withCache(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
  gridDecimals: number,
  producer: () => Promise<Response>
): Promise<Response> {
  const cache = caches.default;
  const key = cacheKeyFor(request.url, gridDecimals);
  const hit = await cache.match(key);
  if (hit) return hit;
  const limited = await rateLimited(request, env).catch(() => null);
  if (limited) return limited;
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
  // Local and global counts must share a basis to be comparable in computeRarity:
  // both filter to HUMAN_OBSERVATION so global density isn't inflated by fossils,
  // preserved specimens, or machine/literature records that the local count omits.
  let q = `${GBIF}/occurrence/search?taxonKey=${taxonKey}&limit=0&basisOfRecord=HUMAN_OBSERVATION`;
  if (lat != null && lng != null) {
    q += `&hasCoordinate=true&geoDistance=${lat},${lng},${LOCAL_RADIUS_KM}km`;
  }
  const data = await fetchJSON(q);
  return typeof data?.count === "number" ? data.count : null;
}

async function vernacularName(taxonKey: number): Promise<string | null> {
  const data = await fetchJSONRetry(`${GBIF}/species/${taxonKey}/vernacularNames?limit=40`).catch(() => null);
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
 * A single occurrence-density facet is dominated by birds/animals (that is what
 * HUMAN_OBSERVATION density overwhelmingly records), which collapses the dex into
 * an all-animals list. So we facet each kingdom separately within
 * LOCAL_RADIUS_KM and round-robin interleave them, giving a balanced mix of
 * animals, plants, and fungi ranked by local abundance within each realm. Cached
 * hard at the edge since a coarse area's species list is stable.
 */
async function region(url: URL): Promise<Response> {
  const lat = numParam(url, "lat");
  const lng = numParam(url, "lng");
  const limit = Math.min(120, intParam(url, "limit") ?? 80);
  if (lat == null || lng == null) return json({ error: "lat and lng required" }, 400);

  // Per-realm resolve budgets: animals genuinely dominate local observation, but
  // plants and fungi get guaranteed representation so the dex reads as a living
  // cross-section rather than a bird list. Protists (Chromista/Protozoa) are
  // sparse in citizen-science data — a small slice, best-effort.
  const REALM_FACETS: Array<{ kingdomKey: number; realm: string; budget: number }> = [
    { kingdomKey: 1, realm: "animals", budget: Math.ceil(limit * 0.42) }, // Animalia
    { kingdomKey: 6, realm: "plants", budget: Math.ceil(limit * 0.34) }, //  Plantae
    { kingdomKey: 5, realm: "fungi", budget: Math.ceil(limit * 0.2) }, //    Fungi
    { kingdomKey: 4, realm: "protists", budget: 1 }, //                       Chromista
    { kingdomKey: 7, realm: "protists", budget: 1 }, //                       Protozoa
  ];

  // Facet each kingdom (cheap, count-only) — the realm is known from the query,
  // so the per-species lookup never needs the kingdom back.
  const perRealm = await Promise.all(
    REALM_FACETS.map(async (f) => {
      const counts = await facetSpeciesKeys(lat, lng, f.kingdomKey, f.budget);
      return counts.map((c) => ({ key: Number(c.name), count: c.count, realm: f.realm }));
    }),
  );

  // Resolve every candidate through ONE bounded pool so the GBIF concurrency
  // profile matches the old single-facet path (five separate pools fan out to
  // 5×N concurrent requests and get rate-limited). Candidates are round-robined
  // across realms *before* resolving, so if GBIF rate-limits the tail, the
  // species that do resolve are still a balanced mix rather than all-animals.
  const candidates = roundRobinByRealm(
    perRealm.flat().filter((c) => Number.isFinite(c.key) && !EXCLUDED_TAXA.has(c.key)),
    (c) => c.key,
  );

  // One GBIF call per species (not two): `species/{key}` carries the English
  // vernacular inline, so the separate vernacularNames lookup is dropped —
  // halving subrequests and roughly doubling how many species fit under the
  // Worker's per-request subrequest budget, common names intact.
  const resolved = await mapPool(candidates, REGION_CONCURRENCY, async (c) => {
    const sp = await fetchJSON(`${GBIF}/species/${c.key}`).catch(() => null);
    const scientificName = sp?.canonicalName ?? sp?.scientificName;
    if (!scientificName || sp?.rank !== "SPECIES") return null;
    return {
      taxonKey: c.key,
      commonName: cleanVernacular(sp?.vernacularName),
      scientificName,
      realm: c.realm,
      rarity: computeRarity(c.count, null, null, true),
      localCount: c.count,
    } satisfies RegionItem;
  });

  const species = roundRobinByRealm(
    resolved.filter((s): s is RegionItem => s !== null),
    (s) => s.taxonKey,
  ).slice(0, limit);
  return json({ count: species.length, species }, 200, 24 * 60 * 60);
}

interface RegionItem {
  taxonKey: number;
  commonName: string | null;
  scientificName: string;
  realm: string;
  rarity: Rarity;
  localCount: number;
}

/**
 * Normalizes the inline vernacular from `species/{key}`: trims, drops empty or
 * banding-code names (all-caps, no space — "GRTI"), and title-cases an
 * all-lowercase name, leaving proper names ("Steller's Jay") untouched.
 */
function cleanVernacular(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const name = raw.trim();
  if (!name) return null;
  if (name === name.toUpperCase() && !/\s/.test(name)) return null;
  return /[A-Z]/.test(name) ? name : name.replace(/\b\w/g, (ch) => ch.toUpperCase());
}

/** Top `budget` most-locally-observed species keys of one kingdom (count-only). */
async function facetSpeciesKeys(
  lat: number,
  lng: number,
  kingdomKey: number,
  budget: number,
): Promise<Array<{ name: string; count: number }>> {
  const facetUrl =
    `${GBIF}/occurrence/search?hasCoordinate=true&geoDistance=${lat},${lng},${LOCAL_RADIUS_KM}km` +
    `&basisOfRecord=HUMAN_OBSERVATION&kingdomKey=${kingdomKey}` +
    `&facet=speciesKey&facetLimit=${budget + 4}&limit=0`;
  const data = await fetchJSON(facetUrl).catch(() => null);
  const counts: Array<{ name: string; count: number }> = data?.facets?.[0]?.counts ?? [];
  // Slice to the realm's budget (small headroom for resolution dropout) so the
  // per-realm candidate counts actually control the dex's realm mix.
  return counts.slice(0, budget + 2);
}

/**
 * Round-robin merge across realms: take the top item of each realm, then the
 * next, and so on (within-realm order is preserved), deduping by `keyOf`. Keeps
 * the dex balanced instead of letting animals crowd everything out.
 */
function roundRobinByRealm<T extends { realm: string }>(items: T[], keyOf: (item: T) => number): T[] {
  const byRealm = new Map<string, T[]>();
  for (const item of items) {
    const list = byRealm.get(item.realm);
    if (list) list.push(item);
    else byRealm.set(item.realm, [item]);
  }
  const lists = [...byRealm.values()];
  const out: T[] = [];
  const seen = new Set<number>();
  const depth = Math.max(0, ...lists.map((l) => l.length));
  for (let i = 0; i < depth; i++) {
    for (const list of lists) {
      const item = list[i];
      if (item && !seen.has(keyOf(item))) {
        seen.add(keyOf(item));
        out.push(item);
      }
    }
  }
  return out;
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

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/**
 * `fetchJSON` with jittered backoff retries. GBIF rate-limits the Worker's shared
 * egress IP under the Regional-Dex burst (~250 calls); one or two spaced retries
 * recover most of the 429s, taking the dex from a couple-dozen species to a full
 * list. The result is edge-cached 24h, so the extra cold-fill latency is paid
 * once per area.
 */
async function fetchJSONRetry(u: string, retries = 2): Promise<any> {
  for (let attempt = 0; ; attempt++) {
    try {
      return await fetchJSON(u);
    } catch (e) {
      if (attempt >= retries) throw e;
      await sleep(300 * (attempt + 1) + Math.random() * 250);
    }
  }
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
