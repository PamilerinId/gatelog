import { NextResponse, type NextRequest } from "next/server";
import { apiRequest } from "@/app/(dashboard)/_lib/api";
import { SESSION_COOKIE } from "@/app/(dashboard)/_lib/session";

// "Find the estate" in the map editor: a place name or address to a point, so a first-time admin
// never has to know coordinates. OpenStreetMap's Nominatim, limited to Nigeria, called from the
// server (one identifying User-Agent, no key). Its usage policy allows about one search a second and
// no search-as-you-type, so the editor searches only when the admin presses Find, and answers are
// cached here. Only signed-in dashboard users can search.

const NO_STORE = { "Cache-Control": "no-store, private", "X-Content-Type-Options": "nosniff" };
const ENDPOINT = "https://nominatim.openstreetmap.org/search";
const UA = "Gatelog estate dashboard (https://gatelog.ng)";
const CACHE_MAX = 200;

export type GeocodeHit = { label: string; lat: number; lng: number; bbox: [number, number, number, number] | null };
type Raw = { display_name: string; lat: string; lon: string; boundingbox?: [string, string, string, string] };

const cache = new Map<string, GeocodeHit[]>();

function fail(message: string, status: number) {
  return NextResponse.json({ error: message }, { status, headers: NO_STORE });
}

async function search(q: string): Promise<GeocodeHit[] | null> {
  const url = `${ENDPOINT}?${new URLSearchParams({ q, format: "jsonv2", countrycodes: "ng", limit: "5", "accept-language": "en" })}`;
  // One retry on a network error or a 5xx; a 4xx (including 429) is not retried.
  for (let attempt = 1; attempt <= 2; attempt++) {
    try {
      const res = await fetch(url, { headers: { "User-Agent": UA, Accept: "application/json" }, cache: "no-store", signal: AbortSignal.timeout(6000) });
      if (res.ok) {
        // A long street comes back as several segments with the same name: keep the first of each.
        const seen = new Set<string>();
        const raw = ((await res.json()) as Raw[]).filter((r) => !seen.has(r.display_name) && !!seen.add(r.display_name));
        return raw.map((r) => {
          const b = r.boundingbox?.map(Number);
          return {
            label: r.display_name,
            lat: Number(r.lat),
            lng: Number(r.lon),
            // Nominatim's box is [south, north, west, east]; the map wants [west, south, east, north].
            bbox: b && b.every(Number.isFinite) ? [b[2], b[0], b[3], b[1]] : null,
          };
        });
      }
      console.error(`geocode: Nominatim ${res.status} (attempt ${attempt})`);
      if (res.status < 500) return null;
    } catch (e) {
      console.error(`geocode: Nominatim unreachable (attempt ${attempt}) ${e instanceof Error ? e.name : "error"}`);
    }
  }
  return null;
}

export async function GET(req: NextRequest) {
  const token = req.cookies.get(SESSION_COOKIE)?.value;
  if (!token) return fail("Please sign in again.", 401);
  const me = await apiRequest<unknown>("/v1/auth/me", { token, timeoutMs: 5000 });
  if (!me.ok) return fail("Please sign in again.", 401);

  const q = (req.nextUrl.searchParams.get("q") ?? "").trim().replace(/\s+/g, " ");
  if (q.length < 3 || q.length > 160) return fail("Type the estate's name or a nearby street, area or landmark.", 400);

  const key = q.toLowerCase();
  const hit = cache.get(key);
  if (hit) return NextResponse.json({ results: hit }, { headers: NO_STORE });

  const results = await search(q);
  if (results === null) return fail("The place search is not available right now. Move the map by hand, or use your location.", 502);
  if (cache.size >= CACHE_MAX) cache.delete(cache.keys().next().value!);
  cache.set(key, results);
  return NextResponse.json({ results }, { headers: NO_STORE });
}
