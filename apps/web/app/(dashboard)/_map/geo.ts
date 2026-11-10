import type { BBox, LngLat } from "@/app/(dashboard)/_lib/types";

// Small Web Mercator helpers for locking the map to the estate.

const TILE = 512; // MapLibre's world is 512 px wide at zoom 0

function mercX(lng: number) {
  return (lng + 180) / 360;
}
function mercY(lat: number) {
  const r = (lat * Math.PI) / 180;
  return (1 - Math.log(Math.tan(r) + 1 / Math.cos(r)) / Math.PI) / 2;
}

/** The estate's box with a margin, so the boundary line is not hard against the edge. */
export function padBBox([w, s, e, n]: BBox, ratio = 0.08, minDeg = 0.0015): BBox {
  const px = Math.max((e - w) * ratio, minDeg);
  const py = Math.max((n - s) * ratio, minDeg);
  return [w - px, s - py, e + px, n + py];
}

/** The zoom at which the box just covers a view of this size: zooming out further would show
 * land outside the box. */
export function coverZoom([w, s, e, n]: BBox, width: number, height: number) {
  const dx = Math.max(mercX(e) - mercX(w), 1e-9);
  const dy = Math.max(mercY(s) - mercY(n), 1e-9);
  const zx = Math.log2(width / (TILE * dx));
  const zy = Math.log2(height / (TILE * dy));
  return Math.max(zx, zy);
}

export function ringBBox(ring: LngLat[]): BBox | null {
  if (ring.length === 0) return null;
  const lngs = ring.map((p) => p[0]);
  const lats = ring.map((p) => p[1]);
  return [Math.min(...lngs), Math.min(...lats), Math.max(...lngs), Math.max(...lats)];
}

export function bboxCenter([w, s, e, n]: BBox): LngLat {
  return [(w + e) / 2, (s + n) / 2];
}

/** GeoJSON for the estate outline, closed. */
export function ringFeature(ring: LngLat[] | null) {
  const closed = ring && ring.length >= 3 ? [...ring, ring[0]] : null;
  return {
    type: "FeatureCollection" as const,
    features: closed ? [{ type: "Feature" as const, properties: {}, geometry: { type: "Polygon" as const, coordinates: [closed] } }] : [],
  };
}

export const EMPTY = { type: "FeatureCollection" as const, features: [] as never[] };

const STEPS = [0.0005, 0.001, 0.002, 0.0025, 0.005, 0.01, 0.02, 0.05];

/** A round grid spacing that gives about `lines` lines across the box. */
export function gridStep([w, s, e, n]: BBox, lines = 6) {
  const span = Math.max(e - w, n - s) / lines;
  return STEPS.find((x) => x >= span) ?? STEPS[STEPS.length - 1];
}

export function gridValues(min: number, max: number, step: number) {
  const out: number[] = [];
  for (let v = Math.ceil(min / step) * step; v <= max + 1e-12; v += step) out.push(Math.round(v / step) * step);
  return out;
}

/** The faint coordinate grid over the lock box. */
export function gridFeature(box: BBox, step = gridStep(box)) {
  const [w, s, e, n] = box;
  const lines: LngLat[][] = [
    ...gridValues(w, e, step).map((x): LngLat[] => [
      [x, s],
      [x, n],
    ]),
    ...gridValues(s, n, step).map((y): LngLat[] => [
      [w, y],
      [e, y],
    ]),
  ];
  return {
    type: "FeatureCollection" as const,
    features: lines.map((c) => ({ type: "Feature" as const, properties: {}, geometry: { type: "LineString" as const, coordinates: c } })),
  };
}

export function fmtLat(v: number) {
  return `${Math.abs(v).toFixed(4)}°${v >= 0 ? "N" : "S"}`;
}
export function fmtLng(v: number) {
  return `${Math.abs(v).toFixed(4)}°${v >= 0 ? "E" : "W"}`;
}
