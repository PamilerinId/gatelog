"use client";

import "maplibre-gl/dist/maplibre-gl.css";
import * as maplibregl from "maplibre-gl";
import { useEffect, useRef, useState } from "react";
import { ENTRY_METHOD, PLACE_KIND, fmtTime } from "@/app/(dashboard)/_lib/format";
import type { BBox, GateEntry, LiveGate, LiveShuttle, MapGate, MapPlace, RideBrief } from "@/app/(dashboard)/_lib/types";
import { useEstateMap, type MapMode } from "./context";
import { EMPTY, bboxCenter, coverZoom, fmtLat, fmtLng, gridFeature, gridStep, gridValues, padBBox, ringFeature } from "./geo";
import { IMAGERY, rasterSource } from "./provider";
import { DISPLAY_ONLY, buildStyle, imageryLayer, themePaint } from "./style";
import { DEFAULT_CENTER, absolute, minutesSince, shortName, waitLabel } from "./util";

// The one map behind the dashboard. Created once, when the dashboard first needs it, and kept
// while the user moves between pages; each page only changes its mode (live, edit or still).

const RECENT_MS = 30 * 60_000; // an entry shows as a ring on its home for half an hour

function lockBox(mode: MapMode, bbox: BBox | null): BBox | null {
  if (!bbox) return null; // the editor before a boundary exists: free to find the estate
  return mode === "edit" ? padBBox(bbox, 0.6, 0.01) : padBBox(bbox);
}

type Entry = { marker: maplibregl.Marker; el: HTMLElement; pos: [number, number]; raf?: number };

function span(cls: string, text = "") {
  const s = document.createElement("span");
  s.className = cls;
  if (text) s.textContent = text;
  return s;
}
function setText(el: Element, selector: string, text: string) {
  const t = el.querySelector(selector);
  if (t && t.textContent !== text) t.textContent = text;
}
function marker(kind: string, parts: HTMLElement[]) {
  const el = document.createElement("div");
  el.className = `gl-m gl-m--${kind}`;
  el.setAttribute("aria-hidden", "true");
  el.append(...parts);
  return el;
}

// --- gates: a dot (black by day, white at night) with a guard dot beside it when someone is on duty
type GateLike = MapGate & Partial<Pick<LiveGate, "quiet" | "on_duty" | "phones" | "phone_last_sync_at">>;
function gateEl(g: GateLike) {
  const card = span("gl-m__card");
  card.append(span("gl-m__name"), span("gl-m__sub"));
  const el = marker("gate", [span("gl-m__ring"), span("gl-m__dot"), span("gl-m__guard"), card]);
  updateGateEl(el, g);
  return el;
}
function updateGateEl(el: HTMLElement, g: GateLike) {
  setText(el, ".gl-m__name", g.name.toUpperCase());
  const off = !!g.quiet;
  let sub = "";
  if (g.on_duty !== undefined) {
    const who = g.on_duty.length ? g.on_duty.map((d) => shortName(d.guard)).join(", ") : "NOBODY ON DUTY";
    if (g.phones === 0) sub = `NO PHONE · ${who}`;
    else if (off) sub = g.phone_last_sync_at ? `OFFLINE · SYNC ${minutesSince(g.phone_last_sync_at)}` : "OFFLINE · NEVER SYNCED";
    else sub = `ONLINE · ${who}`;
  }
  setText(el, ".gl-m__sub", sub);
  el.classList.toggle("is-off", off);
  el.classList.toggle("has-guard", !!g.on_duty?.length);
  el.title = [g.name, sub.toLowerCase()].filter(Boolean).join(": ");
}

function placeEl(p: MapPlace) {
  const el = marker("place", [span("gl-m__dot"), span("gl-m__tag")]);
  updatePlaceEl(el, p);
  return el;
}
function updatePlaceEl(el: HTMLElement, p: MapPlace) {
  setText(el, ".gl-m__tag", p.name.toUpperCase());
  el.dataset.kind = p.kind;
  el.title = `${p.name} (${PLACE_KIND[p.kind]})`;
}

// --- shuttles: the guard style, with the motorcycle and rider, and a notch for the heading
function shuttleEl(s: LiveShuttle) {
  const el = marker("bike", [span("gl-m__ring"), span("gl-m__dot"), span("gl-m__heading"), span("gl-m__tag")]);
  updateShuttleEl(el, s);
  return el;
}
function updateShuttleEl(el: HTMLElement, s: LiveShuttle) {
  setText(el, ".gl-m__tag", `${s.shuttle ? `SHUTTLE · ${s.shuttle.toUpperCase()}` : "SHUTTLE"} · ${shortName(s.rider)}`);
  el.classList.toggle("is-stale", s.stale);
  el.classList.toggle("has-heading", s.heading != null && !s.stale);
  el.style.setProperty("--heading", `${s.heading ?? 0}deg`);
  el.title = `${s.rider}${s.shuttle ? ` on ${s.shuttle}` : ""}${s.stale ? ", no recent position" : ""}`;
}

function rideEl(r: RideBrief) {
  const el = marker("ride", [span("gl-m__ring"), span("gl-m__dot"), span("gl-m__tag")]);
  updateRideEl(el, r);
  return el;
}
function updateRideEl(el: HTMLElement, r: RideBrief) {
  const future = Date.parse(r.wanted_at) > Date.now();
  setText(el, ".gl-m__tag", future ? `PICKUP · DUE ${fmtTime(r.wanted_at)}` : `PICKUP · ${waitLabel(r.waiting_minutes)}`);
  el.title = `Waiting for the shuttle: ${r.from} to ${r.to}`;
}

function entryEl(e: GateEntry) {
  const el = marker("entry", [span("gl-m__ring")]);
  el.title = `Entry ${fmtTime(e.at)}, ${ENTRY_METHOD[e.method].toLowerCase()}`;
  return el;
}

type Label = { key: string; text: string; x: number; y: number; axis: "lat" | "lng" };

export default function EstateMap() {
  const { mode, data, live, theme, setEngine, setCredit } = useEstateMap();
  const holder = useRef<HTMLDivElement>(null);
  const mapRef = useRef<maplibregl.Map | null>(null);
  const [ready, setReady] = useState(false);
  const markers = useRef(new Map<string, Entry>());
  const reduced = useRef(false);
  const coarse = useRef(false);
  const first = useRef({ theme, mode });
  const lastBoxKey = useRef("");
  const [labels, setLabels] = useState<Label[]>([]);

  // --- create the map once ----------------------------------------------------------------------
  useEffect(() => {
    if (!holder.current) return;
    reduced.current = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    coarse.current = window.matchMedia("(pointer: coarse)").matches;
    // The bundler cannot follow MapLibre's worker file: it is copied to public/map before dev and build.
    maplibregl.setWorkerUrl(absolute("/map/maplibre-gl-worker.mjs"));
    const map = new maplibregl.Map({
      container: holder.current,
      style: buildStyle(first.current.theme, first.current.mode === "edit"),
      center: DEFAULT_CENTER,
      zoom: 15,
      attributionControl: false, // the shell shows the imagery credit on every page
      dragRotate: false,
      pitchWithRotate: false,
      touchPitch: false,
      maxPitch: 0,
      renderWorldCopies: false,
      maxZoom: 19.5,
      fadeDuration: 0,
    });
    map.touchZoomRotate.disableRotation();
    map.keyboard.disableRotation();
    map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "bottom-right");
    map.getCanvas().setAttribute("aria-label", "Satellite map of the estate. Use the arrow keys to move and plus or minus to zoom.");
    map.on("load", () => setReady(true));
    mapRef.current = map;
    setEngine(map, maplibregl);
    const store = markers.current;
    return () => {
      store.forEach((e) => {
        if (e.raf) cancelAnimationFrame(e.raf);
        e.marker.remove();
      });
      store.clear();
      setEngine(null, null);
      map.remove();
      mapRef.current = null;
    };
  }, [setEngine]);

  // --- day and night: the same imagery, darkened and desaturated at night ------------------------
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !ready) return;
    for (const [layer, prop, value] of themePaint(theme)) if (map.getLayer(layer)) map.setPaintProperty(layer, prop as never, value as never);
  }, [theme, ready]);

  // --- imagery that needs a session first (Google), and its credit for the current view -------
  const themeRef = useRef(theme);
  themeRef.current = theme;
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !ready || !IMAGERY.prepare || map.getSource("imagery")) return;
    let cancelled = false;
    IMAGERY.prepare()
      .then(({ tiles }) => {
        if (cancelled || map.getSource("imagery")) return;
        map.addSource("imagery", rasterSource(tiles));
        map.addLayer(imageryLayer(themeRef.current), "gl-grid");
      })
      .catch((err: unknown) => {
        console.error("satellite imagery:", err instanceof Error ? err.message : err);
        if (!cancelled) setCredit("Satellite imagery is not available right now");
      });
    return () => {
      cancelled = true;
    };
  }, [ready, setCredit]);

  useEffect(() => {
    const map = mapRef.current;
    const creditFor = IMAGERY.creditFor;
    if (!map || !ready || !creditFor) return;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const update = () => {
      clearTimeout(timer);
      timer = setTimeout(async () => {
        const b = map.getBounds();
        const text = await creditFor([b.getWest(), b.getSouth(), b.getEast(), b.getNorth()], map.getZoom());
        if (text) setCredit(text);
      }, 400);
    };
    // Once when the imagery source arrives, then after every move.
    const onSource = (e: maplibregl.MapSourceDataEvent) => e.sourceId === "imagery" && e.sourceDataType === "metadata" && update();
    update();
    map.on("moveend", update);
    map.on("sourcedata", onSource);
    return () => {
      clearTimeout(timer);
      map.off("moveend", update);
      map.off("sourcedata", onSource);
    };
  }, [ready, setCredit]);

  // --- mode: interaction, layers the editor replaces --------------------------------------------
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    const interactive = mode === "live" || mode === "edit";
    for (const h of [map.scrollZoom, map.boxZoom, map.dragPan, map.keyboard, map.doubleClickZoom, map.touchZoomRotate]) {
      if (interactive) h.enable();
      else h.disable();
    }
    map.touchZoomRotate.disableRotation();
    map.keyboard.disableRotation();
    // On phones the live map sits above a page that scrolls: one finger scrolls, two move the map.
    if (interactive && coarse.current && mode === "live") map.cooperativeGestures.enable();
    else map.cooperativeGestures.disable();
    map.getCanvas().tabIndex = interactive ? 0 : -1;
    map.getContainer().setAttribute("aria-hidden", interactive ? "false" : "true");
    if (ready) for (const id of DISPLAY_ONLY) if (map.getLayer(id)) map.setLayoutProperty(id, "visibility", mode === "edit" ? "none" : "visible");
  }, [mode, ready]);

  // --- the lock to the estate ---------------------------------------------------------------------
  const box = lockBox(mode, data?.bbox ?? null);
  const boxKey = box ? box.join(",") : "";
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    const apply = (recentre: boolean) => {
      if (!box) {
        map.setMaxBounds(null);
        map.setMinZoom(0);
        return;
      }
      const c = map.getContainer();
      const z = Math.min(coverZoom(box, c.clientWidth || 1, c.clientHeight || 1), 18.5);
      map.setMinZoom(null);
      map.setMaxBounds(box);
      map.setMinZoom(z);
      if (recentre) map.jumpTo({ center: bboxCenter(data?.bbox ?? box), zoom: z });
    };
    // Re-centre when the box itself changes (first load, a new boundary, entering the editor).
    apply(boxKey !== lastBoxKey.current);
    lastBoxKey.current = boxKey;
    const onResize = () => apply(false);
    map.on("resize", onResize);
    return () => {
      map.off("resize", onResize);
    };
    // box is derived from boxKey
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [boxKey]);

  // --- outline, grid, homes, trails -----------------------------------------------------------------
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !ready) return;
    const set = (id: string, geo: GeoJSON.GeoJSON) => (map.getSource(id) as maplibregl.GeoJSONSource | undefined)?.setData(geo);
    set("gl-boundary", ringFeature(data?.boundary ?? null));
    set("gl-grid", data?.bbox ? gridFeature(padBBox(data.bbox, 0.6, 0.01), gridStep(data.bbox, 5)) : EMPTY);
    set("gl-homes", {
      type: "FeatureCollection",
      features: (data?.homes ?? []).map((h) => ({ type: "Feature", properties: {}, geometry: { type: "Point", coordinates: [h.lng, h.lat] } })),
    });
  }, [data, ready]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || !ready) return;
    const shuttles = mode === "live" ? (live?.shuttles ?? []) : [];
    const trails = {
      type: "FeatureCollection" as const,
      features: shuttles
        .filter((s) => s.trail.length > 1)
        .map((s) => ({ type: "Feature" as const, properties: { stale: s.stale }, geometry: { type: "LineString" as const, coordinates: s.trail } })),
    };
    (map.getSource("gl-trails") as maplibregl.GeoJSONSource | undefined)?.setData(shuttles.length ? trails : EMPTY);
  }, [live, mode, ready]);

  // --- coordinate labels along the left and bottom edges (live and edit) ------------------------------
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !ready || !data?.bbox || mode === "still" || mode === "none") {
      setLabels([]);
      return;
    }
    const grid = padBBox(data.bbox, 0.6, 0.01);
    const step = gridStep(data.bbox, 5);
    let raf = 0;
    const place = () => {
      raf = 0;
      const b = map.getBounds();
      const { clientWidth: w, clientHeight: h } = map.getContainer();
      const out: Label[] = [];
      for (const lat of gridValues(Math.max(grid[1], b.getSouth()), Math.min(grid[3], b.getNorth()), step)) {
        const y = map.project([b.getWest(), lat]).y;
        if (y > 40 && y < h - 40) out.push({ key: `lat${lat}`, text: fmtLat(lat), x: 10, y, axis: "lat" });
      }
      for (const lng of gridValues(Math.max(grid[0], b.getWest()), Math.min(grid[2], b.getEast()), step)) {
        const x = map.project([lng, b.getSouth()]).x;
        if (x > 90 && x < w - 90) out.push({ key: `lng${lng}`, text: fmtLng(lng), x, y: h - 10, axis: "lng" });
      }
      setLabels(out);
    };
    const onMove = () => {
      if (!raf) raf = requestAnimationFrame(place);
    };
    place();
    map.on("move", onMove);
    map.on("resize", onMove);
    return () => {
      cancelAnimationFrame(raf);
      map.off("move", onMove);
      map.off("resize", onMove);
    };
  }, [ready, data?.bbox, mode]);

  // --- markers -----------------------------------------------------------------------------------------
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    const store = markers.current;
    const want = new Set<string>();
    const show = mode === "live" || mode === "still";

    const put = (
      key: string,
      lng: number,
      lat: number,
      create: () => HTMLElement,
      update?: (el: HTMLElement) => void,
      opts: { animate?: boolean; anchor?: maplibregl.PositionAnchor; offset?: [number, number] } = {},
    ) => {
      want.add(key);
      const e = store.get(key);
      if (!e) {
        const el = create();
        const m = new maplibregl.Marker({ element: el, anchor: opts.anchor ?? "center", offset: opts.offset }).setLngLat([lng, lat]).addTo(map);
        store.set(key, { marker: m, el, pos: [lng, lat] });
        return;
      }
      update?.(e.el);
      if (e.pos[0] === lng && e.pos[1] === lat) return;
      if (e.raf) cancelAnimationFrame(e.raf);
      const from = e.marker.getLngLat();
      e.pos = [lng, lat];
      if (!opts.animate || reduced.current) {
        e.marker.setLngLat([lng, lat]);
        return;
      }
      const t0 = performance.now();
      const step = (t: number) => {
        const k = Math.min(1, (t - t0) / 1200);
        const ease = 1 - (1 - k) * (1 - k);
        e.marker.setLngLat([from.lng + (lng - from.lng) * ease, from.lat + (lat - from.lat) * ease]);
        e.raf = k < 1 ? requestAnimationFrame(step) : undefined;
      };
      e.raf = requestAnimationFrame(step);
    };

    if (show) {
      const liveGates = mode === "live" && live ? live.gates : null;
      for (const g of (liveGates ?? data?.gates ?? []) as GateLike[]) {
        if (g.lat == null || g.lng == null) continue;
        put(`gate:${g.id}`, g.lng, g.lat, () => gateEl(g), (el) => updateGateEl(el, g));
      }
      for (const p of mode === "live" && live ? live.places : (data?.places ?? [])) {
        put(`place:${p.id}`, p.lng, p.lat, () => placeEl(p), (el) => updatePlaceEl(el, p));
      }
    }
    if (mode === "live" && live) {
      for (const s of live.shuttles ?? []) {
        if (s.lat == null || s.lng == null) continue;
        put(`bike:${s.shift_id}`, s.lng, s.lat, () => shuttleEl(s), (el) => updateShuttleEl(el, s), { animate: true });
      }
      for (const r of live.rides_waiting) {
        if (r.lat == null || r.lng == null) continue;
        put(`ride:${r.id}`, r.lng, r.lat, () => rideEl(r), (el) => updateRideEl(el, r));
      }
      // Recent entries: a small ring on the home, when the home is pinned.
      const homes = new Map((data?.homes ?? []).map((h) => [h.address, h]));
      const now = Date.now();
      for (const e of live.log ?? []) {
        if (e.method === "refused" || !e.address || now - Date.parse(e.at) > RECENT_MS) continue;
        const h = homes.get(e.address);
        if (h) put(`entry:${e.id}`, h.lng, h.lat, () => entryEl(e));
      }
    }
    for (const [key, e] of store) {
      if (want.has(key)) continue;
      if (e.raf) cancelAnimationFrame(e.raf);
      e.marker.remove();
      store.delete(key);
    }
  }, [mode, data, live]);

  return (
    <>
      <div ref={holder} className="dash-map" data-mode={mode} />
      {labels.length > 0 && (
        <div className="dash-map-labels" aria-hidden="true">
          {mode === "live" && <span className="dash-map-bounds">ESTATE BOUNDARY · BOUNDS LOCKED</span>}
          {labels.map((l) => (
            <span key={l.key} className={`dash-map-label dash-map-label--${l.axis}`} style={{ left: l.x, top: l.y }}>
              {l.text}
            </span>
          ))}
        </div>
      )}
    </>
  );
}
