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

export default {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/") {
      return json({ service: "livingdex-worker", ok: true });
    }
    if (request.method === "GET" && url.pathname === "/v1/enrich") {
      return enrich(url).catch((e) => json({ error: String(e) }, 500));
    }
    if (request.method === "GET" && url.pathname === "/v1/region") {
      return region(url).catch((e) => json({ error: String(e) }, 500));
    }
    if (request.method === "GET" && url.pathname === "/v1/detail") {
      return detail(url).catch((e) => json({ error: String(e) }, 500));
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

  // Every upstream is independently best-effort: a single GBIF hiccup (e.g. a
  // 429 on the occurrence search) must not sink the whole fact-sheet, so each
  // failure degrades to null and the response is still useful.
  const [species, iucn, localCount, globalCount] = await Promise.all([
    fetchJSON(`${GBIF}/species/${taxonKey}`).catch(() => null),
    fetchJSON(`${GBIF}/species/${taxonKey}/iucnRedListCategory`).catch(() => null),
    lat != null && lng != null ? occurrenceCount(taxonKey, lat, lng).catch(() => null) : Promise.resolve(null),
    occurrenceCount(taxonKey, null, null).catch(() => null),
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

  const facetUrl =
    `${GBIF}/occurrence/search?hasCoordinate=true&geoDistance=${lat},${lng},${LOCAL_RADIUS_KM}km` +
    `&facet=speciesKey&facetLimit=${limit}&limit=0`;
  const data = await fetchJSON(facetUrl);
  const counts: Array<{ name: string; count: number }> = data?.facets?.[0]?.counts ?? [];

  const species = (
    await Promise.all(
      counts.map(async (c) => {
        const key = Number(c.name);
        if (!Number.isFinite(key)) return null;
        const sp = await fetchJSON(`${GBIF}/species/${key}`).catch(() => null);
        const scientificName = sp?.canonicalName ?? sp?.scientificName;
        if (!scientificName || sp?.rank !== "SPECIES") return null;
        return {
          taxonKey: key,
          commonName: sp?.vernacularName ?? null,
          scientificName,
          realm: kingdomToRealm(sp?.kingdom),
          rarity: computeRarity(c.count, null, null, true),
          localCount: c.count,
        };
      })
    )
  ).filter((s) => s !== null);

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
