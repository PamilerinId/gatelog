import type { LayerSpecification, StyleSpecification } from "maplibre-gl";
import { EMPTY } from "./geo";
import { IMAGERY, RASTER_PAINT, rasterSource } from "./provider";
import type { Theme } from "./theme";

// The map's style: satellite imagery (see provider.ts) with Gatelog's own layers on top.
// Day and night change paint properties only, so nothing is rebuilt when the sun sets.

/** Colours from docs/gatelog-handoff/design (Main.dc.html). */
export const OVERLAY = {
  night: {
    bg: "#111111",
    grid: "rgba(244,244,242,0.07)",
    inside: "rgba(244,244,242,0.03)",
    boundary: "rgba(244,244,242,0.85)",
    trail: "#5AA9FF",
    home: "rgba(244,244,242,0.55)",
  },
  day: {
    bg: "#F2F2F0",
    grid: "rgba(255,255,255,0.22)",
    inside: "rgba(255,255,255,0.06)",
    boundary: "#FFFFFF",
    trail: "#1D63C9",
    home: "rgba(255,255,255,0.8)",
  },
} as const;

/** Layers the map editor replaces with its own while it is open. */
export const DISPLAY_ONLY = ["gl-inside", "gl-boundary-line", "gl-homes"];

export function themePaint(theme: Theme): [string, string, unknown][] {
  const c = OVERLAY[theme];
  return [
    ["background", "background-color", c.bg],
    ...Object.entries(RASTER_PAINT[theme]).map(([k, v]) => ["imagery", k, v] as [string, string, unknown]),
    ["gl-grid", "line-color", c.grid],
    ["gl-inside", "fill-color", c.inside],
    ["gl-boundary-line", "line-color", c.boundary],
    ["gl-homes", "circle-color", c.home],
    ["gl-trails", "line-color", c.trail],
  ];
}

/** The imagery layer. Providers that need a session first (Google) add it once they have one. */
export function imageryLayer(theme: Theme): LayerSpecification {
  return { id: "imagery", type: "raster", source: "imagery", paint: { ...RASTER_PAINT[theme], "raster-fade-duration": 0 } };
}

export function buildStyle(theme: Theme, editing = false): StyleSpecification {
  const c = OVERLAY[theme];
  const ready = IMAGERY.tiles.length > 0;
  const visibility = editing ? "none" : "visible";
  const layers: LayerSpecification[] = [
    { id: "background", type: "background", paint: { "background-color": c.bg } },
    ...(ready ? [imageryLayer(theme)] : []),
    { id: "gl-grid", type: "line", source: "gl-grid", paint: { "line-color": c.grid, "line-width": 1 } },
    { id: "gl-inside", type: "fill", source: "gl-boundary", layout: { visibility }, paint: { "fill-color": c.inside } },
    {
      id: "gl-boundary-line",
      type: "line",
      source: "gl-boundary",
      layout: { visibility, "line-join": "round" },
      paint: { "line-color": c.boundary, "line-width": 1.5, "line-dasharray": [4, 4] },
    },
    {
      id: "gl-homes",
      type: "circle",
      source: "gl-homes",
      minzoom: 15,
      layout: { visibility },
      paint: { "circle-radius": 2.5, "circle-color": c.home },
    },
    {
      id: "gl-trails",
      type: "line",
      source: "gl-trails",
      layout: { "line-cap": "round", "line-join": "round" },
      paint: { "line-color": c.trail, "line-width": 2, "line-opacity": ["case", ["get", "stale"], 0.25, 0.7], "line-dasharray": [1, 2] },
    },
  ];
  return {
    version: 8,
    sources: {
      ...(ready ? { imagery: rasterSource() } : {}),
      "gl-grid": { type: "geojson", data: EMPTY },
      "gl-boundary": { type: "geojson", data: EMPTY },
      "gl-homes": { type: "geojson", data: EMPTY },
      "gl-trails": { type: "geojson", data: EMPTY },
    },
    layers,
  };
}
