import type { RasterSourceSpecification } from "maplibre-gl";
import type { BBox } from "@/app/(dashboard)/_lib/types";

// The satellite imagery behind the dashboard map. Everything about the tile provider lives in
// this module (plus the session route for Google), so switching provider is a contained change.
// See apps/web/docs/map-tiles.md for the setup of each.
//
//   esri    the development default. Esri World Imagery, prototype use only, no key.
//   google  production. Google Map Tiles API, 2D satellite tiles, drawn by MapLibre. The server
//           creates the tile session (/dashboard/map-session, key GOOGLE_MAPS_SERVER_KEY); the
//           browser fetches tiles and the viewport credit with NEXT_PUBLIC_GOOGLE_MAPS_KEY,
//           which Google requires on every tile URL, so that key is restricted by HTTP referrer
//           and to the Map Tiles API only.
//   custom  any XYZ raster template (Mapbox Satellite, for instance), from the env below.
//
//   NEXT_PUBLIC_MAP_PROVIDER     esri | google | custom (default esri)
//   NEXT_PUBLIC_MAP_TILES_URL    custom only: an XYZ template with {z}/{x}/{y}
//   NEXT_PUBLIC_MAP_ATTRIBUTION  custom only: the credit line the provider requires
//   NEXT_PUBLIC_MAP_MAX_ZOOM     deepest zoom the provider serves (the map overzooms past it)
//   NEXT_PUBLIC_MAP_TILE_SIZE    custom only: 256 or 512
//   NEXT_PUBLIC_MAP_PROTOTYPE    "1" adds "prototype use only" to the credit

export type ProviderId = "esri" | "google" | "custom";

export type Imagery = {
  id: ProviderId;
  /** Static tile URLs, or empty when `prepare` must run first (Google). */
  tiles: string[];
  tileSize: 256 | 512;
  maxZoom: number;
  attribution: string;
  prototype: boolean;
  /** Show the provider's logo beside the credit (Google requires it). */
  logo: boolean;
  /** Per-session setup before tiles can be fetched. */
  prepare?: () => Promise<{ tiles: string[] }>;
  /** The credit for what is on screen now (Google varies it by area and zoom). */
  creditFor?: (box: BBox, zoom: number) => Promise<string | null>;
};

const num = (v: string | undefined, fallback: number) => {
  const n = Number(v);
  return v && Number.isFinite(n) ? n : fallback;
};

const ESRI: Imagery = {
  id: "esri",
  tiles: ["https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"],
  tileSize: 256,
  maxZoom: num(process.env.NEXT_PUBLIC_MAP_MAX_ZOOM, 19),
  attribution: "Imagery: Esri, Maxar, Earthstar Geographics",
  prototype: true,
  logo: false,
};

// --- Google Map Tiles API ------------------------------------------------------------------------

const GOOGLE_TILES = "https://tile.googleapis.com";
const GOOGLE_KEY = process.env.NEXT_PUBLIC_GOOGLE_MAPS_KEY ?? "";
let currentSession: string | null = null;

/** What /dashboard/map-session returns. */
export type GoogleSession = { session: string; expiry: number; tileWidth: number; imageFormat: string };

const GOOGLE: Imagery = {
  id: "google",
  tiles: [],
  // The session asks for high-DPI 512 px images; MapLibre draws them in 256 px slots, so they
  // stay sharp on phones and retina screens.
  tileSize: 256,
  maxZoom: num(process.env.NEXT_PUBLIC_MAP_MAX_ZOOM, 21),
  attribution: "Google",
  prototype: false,
  logo: true,
  async prepare() {
    if (!GOOGLE_KEY) throw new Error("NEXT_PUBLIC_GOOGLE_MAPS_KEY is not set");
    const res = await fetch("/dashboard/map-session", { cache: "no-store", headers: { Accept: "application/json" } });
    if (!res.ok) throw new Error(`map session: ${res.status}`);
    const s = (await res.json()) as GoogleSession;
    currentSession = s.session; // the viewport credit needs the same session the tiles use
    const q = new URLSearchParams({ session: s.session, key: GOOGLE_KEY });
    return { tiles: [`${GOOGLE_TILES}/v1/2dtiles/{z}/{x}/{y}?${q}`] };
  },
  async creditFor([w, s, e, n], zoom) {
    const session = currentSession;
    if (!session || !GOOGLE_KEY) return null;
    const q = new URLSearchParams({
      session,
      key: GOOGLE_KEY,
      zoom: String(Math.max(0, Math.round(zoom))),
      north: String(n),
      south: String(s),
      east: String(e),
      west: String(w),
    });
    const res = await fetch(`${GOOGLE_TILES}/tile/v1/viewport?${q}`).catch(() => null);
    if (!res?.ok) return null;
    const body = (await res.json().catch(() => null)) as { copyright?: string } | null;
    return body?.copyright ?? null;
  },
};


// --- any other XYZ raster (Mapbox Satellite and the like) -----------------------------------------

function custom(): Imagery {
  const size = num(process.env.NEXT_PUBLIC_MAP_TILE_SIZE, 256);
  return {
    id: "custom",
    tiles: process.env.NEXT_PUBLIC_MAP_TILES_URL ? [process.env.NEXT_PUBLIC_MAP_TILES_URL] : ESRI.tiles,
    tileSize: size === 512 ? 512 : 256,
    maxZoom: num(process.env.NEXT_PUBLIC_MAP_MAX_ZOOM, 19),
    attribution: process.env.NEXT_PUBLIC_MAP_ATTRIBUTION ?? "",
    prototype: process.env.NEXT_PUBLIC_MAP_PROTOTYPE === "1",
    logo: false,
  };
}

function pick(): Imagery {
  const id = process.env.NEXT_PUBLIC_MAP_PROVIDER as ProviderId | undefined;
  const base = id === "google" ? GOOGLE : id === "custom" ? custom() : ESRI;
  if (process.env.NEXT_PUBLIC_MAP_PROTOTYPE) return { ...base, prototype: process.env.NEXT_PUBLIC_MAP_PROTOTYPE === "1" };
  return base;
}

export const IMAGERY = pick();

/** The credit shown on every dashboard page that has the map. */
export function imageryCredit(text: string = IMAGERY.attribution, i: Imagery = IMAGERY) {
  return i.prototype ? `${text} · prototype use only` : text;
}

export function rasterSource(tiles: string[] = IMAGERY.tiles, i: Imagery = IMAGERY): RasterSourceSpecification {
  return { type: "raster", tiles, tileSize: i.tileSize, maxzoom: i.maxZoom, attribution: i.attribution };
}

/** Night is the same imagery, darkened and drained of colour (design/sat_night.jpg). */
export const RASTER_PAINT = {
  day: { "raster-brightness-max": 1, "raster-saturation": -0.12, "raster-contrast": 0.04 },
  night: { "raster-brightness-max": 0.42, "raster-saturation": -1, "raster-contrast": 0.08 },
} as const;
