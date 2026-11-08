import { layers, namedFlavor } from "@protomaps/basemaps";
import type { LayerSpecification, StyleSpecification } from "maplibre-gl";
import type { Theme } from "./theme";
import { EMPTY } from "./geo";

// The map's style: the Protomaps light or dark basemap drawn from the estate's PMTiles
// extract, with fonts and icons served from /map (public/map), so nothing at runtime depends on
// a third-party server. Gatelog's own layers sit on top and keep the ids below, so they survive a
// switch between day and night.

export const TILES_URL = process.env.NEXT_PUBLIC_TILES_URL ?? "";
export const OSM_COPYRIGHT = "https://www.openstreetmap.org/copyright";

/** Overlay sources and layers drawn by the dashboard (gl-) and by the map editor (ed-). */
export const OWN_PREFIXES = ["gl-", "ed-"];

export const OVERLAY = {
  day: { line: "#0d2a52", mask: "rgba(243, 245, 248, 0.55)", trail: "#1e6b4f", home: "#4a5d78", homeRing: "#ffffff" },
  night: { line: "#9cc0ef", mask: "rgba(4, 11, 22, 0.5)", trail: "#8fd1ae", home: "#a9b8cc", homeRing: "#0b1626" },
} as const;

export function absolute(url: string) {
  if (!url) return "";
  return new URL(url, window.location.origin).href;
}

/** Layers the map editor replaces with its own while it is open. */
export const DISPLAY_ONLY = ["gl-mask", "gl-boundary-line", "gl-homes"];

function overlayLayers(theme: Theme, editing: boolean): LayerSpecification[] {
  const c = OVERLAY[theme];
  const visibility = editing ? "none" : "visible";
  return [
    { id: "gl-mask", type: "fill", source: "gl-mask", layout: { visibility }, paint: { "fill-color": c.mask } },
    {
      id: "gl-boundary-line",
      type: "line",
      source: "gl-boundary",
      layout: { visibility },
      paint: { "line-color": c.line, "line-width": 2.5, "line-opacity": 0.9 },
    },
    {
      id: "gl-homes",
      type: "circle",
      source: "gl-homes",
      minzoom: 15,
      layout: { visibility },
      paint: { "circle-radius": 3.5, "circle-color": c.home, "circle-stroke-color": c.homeRing, "circle-stroke-width": 1 },
    },
    {
      id: "gl-trails",
      type: "line",
      source: "gl-trails",
      layout: { "line-cap": "round", "line-join": "round" },
      paint: { "line-color": c.trail, "line-width": 3, "line-opacity": ["case", ["get", "stale"], 0.25, 0.65], "line-dasharray": [1, 1.5] },
    },
  ];
}

export function buildStyle(theme: Theme, editing = false): StyleSpecification {
  const flavor = namedFlavor(theme === "night" ? "dark" : "light");
  const base: LayerSpecification[] = TILES_URL
    ? layers("protomaps", flavor, { lang: "en" })
    : [{ id: "background", type: "background", paint: { "background-color": flavor.background } }];
  return {
    version: 8,
    // Built by hand: new URL() would escape the braces MapLibre fills in.
    glyphs: `${window.location.origin}/map/fonts/{fontstack}/{range}.pbf`,
    sprite: absolute(`/map/sprites/${theme === "night" ? "dark" : "light"}`),
    sources: {
      ...(TILES_URL
        ? {
            protomaps: {
              type: "vector",
              url: `pmtiles://${absolute(TILES_URL)}`,
              attribution: `<a href="${OSM_COPYRIGHT}">© OpenStreetMap contributors</a>`,
            },
          }
        : {}),
      "gl-mask": { type: "geojson", data: EMPTY },
      "gl-boundary": { type: "geojson", data: EMPTY },
      "gl-homes": { type: "geojson", data: EMPTY },
      "gl-trails": { type: "geojson", data: EMPTY },
    },
    layers: [...base, ...overlayLayers(theme, editing)],
  };
}

/** For setStyle: keep the data in our own sources and the editor's layers across a theme switch. */
export function carryOver(prev: StyleSpecification | undefined, next: StyleSpecification): StyleSpecification {
  if (!prev) return next;
  const own = (id: string) => OWN_PREFIXES.some((p) => id.startsWith(p));
  const sources = { ...next.sources };
  for (const [id, src] of Object.entries(prev.sources)) if (own(id)) sources[id] = src;
  const editorLayers = prev.layers.filter((l) => l.id.startsWith("ed-"));
  return { ...next, sources, layers: [...next.layers, ...editorLayers] };
}
