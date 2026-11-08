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

/** Everything outside the estate, to shade it back. A world-sized ring with the estate as a hole. */
export function maskFeature(ring: LngLat[] | null) {
  if (!ring || ring.length < 3) return { type: "FeatureCollection" as const, features: [] };
  const world: LngLat[] = [
    [-179.9, -85],
    [179.9, -85],
    [179.9, 85],
    [-179.9, 85],
    [-179.9, -85],
  ];
  return {
    type: "FeatureCollection" as const,
    features: [
      { type: "Feature" as const, properties: {}, geometry: { type: "Polygon" as const, coordinates: [world, [...ring, ring[0]].reverse()] } },
    ],
  };
}

export const EMPTY = { type: "FeatureCollection" as const, features: [] as never[] };
