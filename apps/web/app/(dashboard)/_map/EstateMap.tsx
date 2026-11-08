"use client";

import "maplibre-gl/dist/maplibre-gl.css";
import * as maplibregl from "maplibre-gl";
import { PMTiles, Protocol } from "pmtiles";
import { useEffect, useRef, useState } from "react";
import { PLACE_KIND, fmtTime } from "@/app/(dashboard)/_lib/format";
import type { BBox, LiveShuttle, MapGate, MapPlace, RideBrief } from "@/app/(dashboard)/_lib/types";
import { useEstateMap, type MapMode } from "./context";
import { EMPTY, bboxCenter, coverZoom, maskFeature, padBBox, ringFeature } from "./geo";
import { DISPLAY_ONLY, TILES_URL, absolute, buildStyle, carryOver } from "./style";

// The one map behind the dashboard. Created once, when the dashboard first needs it, and kept
// while the user moves between pages; each page only changes its mode (live, edit or still).

let protocol: Protocol | null = null;

function lockBox(mode: MapMode, bbox: BBox | null, tiles: BBox | null): BBox | null {
  if (mode === "edit") return tiles ?? (bbox ? padBBox(bbox, 0.6, 0.01) : null);
  return bbox ? padBBox(bbox) : null;
}

type Entry = { marker: maplibregl.Marker; el: HTMLElement; pos: [number, number]; raf?: number };

function setText(el: Element, selector: string, text: string) {
  const t = el.querySelector(selector);
  if (t && t.textContent !== text) t.textContent = text;
}

function makeEl(kind: string, parts: string[]) {
  const el = document.createElement("div");
  el.className = `dash-pin dash-pin--${kind}`;
  el.setAttribute("aria-hidden", "true");
  for (const p of parts) {
    const s = document.createElement("span");
    s.className = p;
    el.appendChild(s);
  }
  return el;
}

type GateLike = MapGate & { quiet?: boolean; on_duty?: { guard: string }[] };

function gateEl(g: GateLike) {
  const el = makeEl("gate", ["dash-pin__dot", "dash-pin__label"]);
  updateGateEl(el, g);
  return el;
}
function updateGateEl(el: HTMLElement, g: GateLike) {
  setText(el, ".dash-pin__label", g.name);
  el.classList.toggle("is-quiet", !!g.quiet);
  const duty = g.on_duty ? (g.on_duty.length ? `On duty: ${g.on_duty.map((d) => d.guard).join(", ")}` : "Nobody on duty") : "";
  el.title = [g.name, duty, g.quiet ? "Phone quiet" : ""].filter(Boolean).join(". ");
}

function placeEl(p: MapPlace) {
  const el = makeEl("place", ["dash-pin__dot", "dash-pin__label"]);
  updatePlaceEl(el, p);
  return el;
}
function updatePlaceEl(el: HTMLElement, p: MapPlace) {
  setText(el, ".dash-pin__label", p.name);
  for (const k of Object.keys(PLACE_KIND)) el.classList.toggle(`dash-pin--${k}`, k === p.kind);
  el.title = `${p.name} (${PLACE_KIND[p.kind]})`;
}

function shuttleEl(s: LiveShuttle) {
  const el = makeEl("bike", ["dash-pin__arrow", "dash-pin__label"]);
  updateShuttleEl(el, s);
  return el;
}
function updateShuttleEl(el: HTMLElement, s: LiveShuttle) {
  setText(el, ".dash-pin__label", s.shuttle ?? s.rider);
  el.classList.toggle("is-stale", s.stale);
  el.classList.toggle("has-heading", s.heading != null);
  const arrow = el.querySelector<HTMLElement>(".dash-pin__arrow");
  if (arrow) arrow.style.setProperty("--heading", `${s.heading ?? 0}deg`);
  el.title = `${s.rider}${s.shuttle ? ` on ${s.shuttle}` : ""}${s.stale ? ". No recent position" : ""}`;
}

function rideEl(r: RideBrief) {
  const el = makeEl("ride", ["dash-pin__pulse", "dash-pin__label"]);
  updateRideEl(el, r);
  return el;
}
function updateRideEl(el: HTMLElement, r: RideBrief) {
  const future = Date.parse(r.wanted_at) > Date.now();
  setText(el, ".dash-pin__label", future ? `Due ${fmtTime(r.wanted_at)}` : `${r.waiting_minutes} min`);
  el.classList.toggle("is-long", r.waiting_minutes >= 10);
  el.title = `Waiting: ${r.from} to ${r.to}`;
}

export default function EstateMap() {
  const { mode, data, live, theme, setEngine, tileBounds, setTileBounds } = useEstateMap();
  const holder = useRef<HTMLDivElement>(null);
  const mapRef = useRef<maplibregl.Map | null>(null);
  const [ready, setReady] = useState(false);
  const markers = useRef(new Map<string, Entry>());
  const reduced = useRef(false);
  const coarse = useRef(false);
  const first = useRef({ theme, mode });
  const lastTheme = useRef(theme);
  const lastBoxKey = useRef("");

  // --- create the map once ----------------------------------------------------------------------
  useEffect(() => {
    if (!holder.current) return;
    reduced.current = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    coarse.current = window.matchMedia("(pointer: coarse)").matches;
    // The bundler cannot follow MapLibre's worker file: it is copied to public/map at install.
    maplibregl.setWorkerUrl(absolute("/map/maplibre-gl-worker.mjs"));
    if (!protocol) {
      protocol = new Protocol();
      maplibregl.addProtocol("pmtiles", protocol.tile);
    }
    if (TILES_URL) {
      const archive = new PMTiles(absolute(TILES_URL));
      protocol.add(archive);
      archive
        .getHeader()
        .then((h) => setTileBounds([h.minLon, h.minLat, h.maxLon, h.maxLat]))
        .catch(() => setTileBounds(null));
    }
    const map = new maplibregl.Map({
      container: holder.current,
      style: buildStyle(first.current.theme, first.current.mode === "edit"),
      center: [3.385, 6.615],
      zoom: 14,
      attributionControl: false, // the shell shows the OpenStreetMap credit on every page
      dragRotate: false,
      pitchWithRotate: false,
      touchPitch: false,
      maxPitch: 0,
      renderWorldCopies: false,
      maxZoom: 19,
      fadeDuration: reduced.current ? 0 : 300,
    });
    map.touchZoomRotate.disableRotation();
    map.keyboard.disableRotation();
    map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "bottom-right");
    map.getCanvas().setAttribute("aria-label", "Map of the estate. Use the arrow keys to move and plus or minus to zoom.");
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
  }, [setEngine, setTileBounds]);

  // --- day and night ------------------------------------------------------------------------------
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !ready || lastTheme.current === theme) return;
    lastTheme.current = theme;
    map.setStyle(buildStyle(theme, mode === "edit"), { diff: true, transformStyle: (prev, next) => carryOver(prev, next) });
    // mode is applied by its own effect; only the theme triggers a new style.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [theme, ready]);

  // --- mode: interaction, layers the editor replaces, the lock to the estate ---------------------
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
    // On phones the map sits behind a page that scrolls: one finger scrolls, two move the map.
    if (interactive && coarse.current && mode === "live") map.cooperativeGestures.enable();
    else map.cooperativeGestures.disable();
    const canvas = map.getCanvas();
    canvas.tabIndex = interactive ? 0 : -1;
    map.getContainer().setAttribute("aria-hidden", interactive ? "false" : "true");
    if (ready) {
      for (const id of DISPLAY_ONLY) if (map.getLayer(id)) map.setLayoutProperty(id, "visibility", mode === "edit" ? "none" : "visible");
    }
  }, [mode, ready]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    const box = lockBox(mode, data?.bbox ?? null, tileBounds);
    const apply = (recentre: boolean) => {
      if (!box) {
        map.setMaxBounds(null);
        map.setMinZoom(0);
        return;
      }
      const c = map.getContainer();
      const z = Math.min(coverZoom(box, c.clientWidth || 1, c.clientHeight || 1), 18);
      map.setMinZoom(null);
      map.setMaxBounds(box);
      map.setMinZoom(z);
      if (recentre) map.jumpTo({ center: bboxCenter(data?.bbox ?? box), zoom: z });
    };
    // Re-centre when the box itself changes (first load, a new boundary, entering the editor).
    const key = box ? box.join(",") : "";
    apply(key !== lastBoxKey.current);
    lastBoxKey.current = key;
    const onResize = () => apply(false);
    map.on("resize", onResize);
    return () => {
      map.off("resize", onResize);
    };
  }, [mode, data?.bbox, tileBounds]);

  // --- the estate outline, homes, trails ------------------------------------------------------------
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !ready) return;
    const set = (id: string, geo: GeoJSON.GeoJSON) => (map.getSource(id) as maplibregl.GeoJSONSource | undefined)?.setData(geo);
    set("gl-boundary", ringFeature(data?.boundary ?? null));
    set("gl-mask", maskFeature(data?.boundary ?? null));
    set("gl-homes", {
      type: "FeatureCollection",
      features: (data?.homes ?? []).map((h) => ({ type: "Feature", properties: { address: h.address }, geometry: { type: "Point", coordinates: [h.lng, h.lat] } })),
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

  // --- markers -----------------------------------------------------------------------------------------
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    const store = markers.current;
    const want = new Set<string>();
    const show = mode === "live" || mode === "still";

    const place = (key: string, lng: number, lat: number, create: () => HTMLElement, update?: (el: HTMLElement) => void, animate = false) => {
      want.add(key);
      const e = store.get(key);
      if (!e) {
        const el = create();
        const marker = new maplibregl.Marker({ element: el, anchor: "center" }).setLngLat([lng, lat]).addTo(map);
        store.set(key, { marker, el, pos: [lng, lat] });
        return;
      }
      update?.(e.el);
      if (e.pos[0] === lng && e.pos[1] === lat) return;
      if (e.raf) cancelAnimationFrame(e.raf);
      const from = e.marker.getLngLat();
      e.pos = [lng, lat];
      if (!animate || reduced.current) {
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
      const gates = mode === "live" && live ? live.gates : (data?.gates ?? []);
      for (const g of gates) {
        if (g.lat == null || g.lng == null) continue;
        place(`gate:${g.id}`, g.lng, g.lat, () => gateEl(g), (el) => updateGateEl(el, g));
      }
      const places = mode === "live" && live ? live.places : (data?.places ?? []);
      for (const p of places) {
        place(`place:${p.id}`, p.lng, p.lat, () => placeEl(p), (el) => updatePlaceEl(el, p));
      }
    }
    if (mode === "live" && live) {
      for (const s of live.shuttles ?? []) {
        if (s.lat == null || s.lng == null) continue;
        place(`bike:${s.shift_id}`, s.lng, s.lat, () => shuttleEl(s), (el) => updateShuttleEl(el, s), true);
      }
      for (const r of live.rides_waiting) {
        if (r.lat == null || r.lng == null) continue;
        place(`ride:${r.id}`, r.lng, r.lat, () => rideEl(r), (el) => updateRideEl(el, r));
      }
    }
    for (const [key, e] of store) {
      if (want.has(key)) continue;
      if (e.raf) cancelAnimationFrame(e.raf);
      e.marker.remove();
      store.delete(key);
    }
  }, [mode, data, live]);

  return <div ref={holder} className="dash-map" data-mode={mode} />;
}
