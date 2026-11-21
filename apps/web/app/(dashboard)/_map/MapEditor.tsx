"use client";

import Link from "next/link";
import { useEffect, useMemo, useRef, useState, useTransition, type FormEvent } from "react";
import type { GeoJSONSource, Map as MapLibre, Marker } from "maplibre-gl";
import { PLACE_KIND } from "@/app/(dashboard)/_lib/format";
import type { ActionState, EstateMapData, LngLat, PlaceKind } from "@/app/(dashboard)/_lib/types";
import { ActionForm, runAction, type Action } from "@/app/(dashboard)/_components/ActionForm";
import { ConfirmButton } from "@/app/(dashboard)/_components/ConfirmButton";
import { createPlace, deletePlace, pinGate, pinHome, saveBoundary, updatePlace } from "@/app/(dashboard)/dashboard/actions";
import { useEstateMap, type MapLib } from "./context";
import { ringFeature } from "./geo";

// The map editor (estate admin). Everything can be done three ways: click the map, drag a pin,
// or (from the keyboard) move the map with the arrow keys and use "at the map centre".

type Tab = "boundary" | "gates" | "places" | "homes";
type Armed =
  | { what: "gate"; id: string; name: string }
  | { what: "home"; id: string; name: string }
  | { what: "place"; name: string; kind: PlaceKind }
  | { what: "move-place"; id: string; name: string }
  | null;
type HomeOption = { id: string; address: string; group: string };

const TABS: { id: Tab; label: string }[] = [
  { id: "boundary", label: "Boundary" },
  { id: "gates", label: "Gates" },
  { id: "places", label: "Places" },
  { id: "homes", label: "Homes" },
];

const round = (n: number) => Math.round(n * 1e6) / 1e6;
const roundP = (p: LngLat): LngLat => [round(p[0]), round(p[1])];

/** Metres per degree near the estate, so distances on the ground compare fairly in both directions. */
function metres(lat: number) {
  return { x: 111_320 * Math.cos((lat * Math.PI) / 180), y: 110_540 };
}

/** Where a new corner goes: on the outline's nearest edge, so the admin can click anywhere along a wall
 * and the outline never crosses itself because of the click order. Fewer than 3 corners: at the end. */
function insertCorner(corners: LngLat[], p: LngLat): LngLat[] {
  if (corners.length < 3) return [...corners, p];
  const k = metres(p[1]);
  const xy = ([lng, lat]: LngLat) => [lng * k.x, lat * k.y] as const;
  const [px, py] = xy(p);
  let best = 0;
  let bestD = Infinity;
  for (let i = 0; i < corners.length; i++) {
    const [ax, ay] = xy(corners[i]);
    const [bx, by] = xy(corners[(i + 1) % corners.length]);
    const dx = bx - ax;
    const dy = by - ay;
    const t = dx || dy ? Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy))) : 0;
    const d = Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
    if (d < bestD) {
      bestD = d;
      best = i + 1;
    }
  }
  return [...corners.slice(0, best), p, ...corners.slice(best)];
}

/** The outline's size on the ground, "About 650 m by 400 m", and whether it looks like an estate. */
function outlineSize(corners: LngLat[]): { text: string; warn: string | null } | null {
  if (corners.length < 3) return null;
  const lngs = corners.map((c) => c[0]);
  const lats = corners.map((c) => c[1]);
  const k = metres((Math.min(...lats) + Math.max(...lats)) / 2);
  const w = (Math.max(...lngs) - Math.min(...lngs)) * k.x;
  const h = (Math.max(...lats) - Math.min(...lats)) * k.y;
  const fmt = (m: number) => (m >= 1000 ? `${(m / 1000).toFixed(1)} km` : `${Math.max(10, Math.round(m / 10) * 10)} m`);
  const big = Math.max(w, h);
  const warn =
    big > 8000 ? "That is bigger than most estates. Zoom in and drag the corners onto the estate's walls." : big < 40 ? "That is very small for an estate. Drag the corners out to its walls." : null;
  return { text: `About ${fmt(w)} by ${fmt(h)}.`, warn };
}

function pinEl(kind: string, label: string) {
  const el = document.createElement("div");
  el.className = `gl-m gl-m--${kind} gl-m--edit`;
  el.setAttribute("aria-hidden", "true");
  const parts = kind === "gate" ? ["gl-m__ring", "gl-m__dot", "gl-m__tag"] : ["gl-m__dot", "gl-m__tag"];
  for (const c of parts) {
    const sp = document.createElement("span");
    sp.className = c;
    el.append(sp);
  }
  el.querySelector(".gl-m__tag")!.textContent = kind === "corner" ? label : label.toUpperCase();
  el.title = `${label}. Drag to move.`;
  return el;
}

/** Adds the draft outline's source and layers whenever the style has none (first load, after a
 * day or night switch the carry-over keeps them). */
function ensureDraft(map: MapLibre, data: GeoJSON.GeoJSON) {
  if (map.getSource("ed-draft")) return;
  try {
    map.addSource("ed-draft", { type: "geojson", data });
    map.addLayer({ id: "ed-draft-fill", type: "fill", source: "ed-draft", paint: { "fill-color": "#F5C542", "fill-opacity": 0.08 } });
    map.addLayer({ id: "ed-draft-line", type: "line", source: "ed-draft", paint: { "line-color": "#F5C542", "line-width": 2, "line-dasharray": [3, 2] } });
  } catch {
    // The style is still loading: the next styledata event tries again.
  }
}

function draftGeo(corners: LngLat[]): GeoJSON.FeatureCollection {
  if (corners.length >= 3) return ringFeature(corners) as GeoJSON.FeatureCollection;
  if (corners.length === 2) return { type: "FeatureCollection", features: [{ type: "Feature", properties: {}, geometry: { type: "LineString", coordinates: corners } }] };
  return { type: "FeatureCollection", features: [] };
}

export function MapEditor({ data, homes, area }: { data: EstateMapData; homes: HomeOption[]; area: string | null }) {
  const { map, lib, flyTo } = useEstateMap();
  const hasBoundary = !!data.boundary && data.boundary.length >= 3;

  // Before a boundary exists, open on the estate's own LGA rather than a fixed default place.
  // Once per visit; a failed search just leaves the map where it is (the admin can still search).
  const opened = useRef(false);
  useEffect(() => {
    if (!map || hasBoundary || !area || opened.current) return;
    opened.current = true;
    fetch(`/dashboard/geocode?${new URLSearchParams({ q: area })}`, { signal: AbortSignal.timeout(15000) })
      .then((r) => (r.ok ? r.json() : null))
      .then((body: { results?: { lat: number; lng: number; bbox: [number, number, number, number] | null }[] } | null) => {
        const hit = body?.results?.[0];
        if (!hit) return;
        if (hit.bbox) map.fitBounds(hit.bbox, { padding: 40, maxZoom: 15, duration: 0 });
        else map.jumpTo({ center: [hit.lng, hit.lat], zoom: 14 });
      })
      .catch(() => undefined);
  }, [map, hasBoundary, area]);
  const [tab, setTab] = useState<Tab>(hasBoundary ? "gates" : "boundary");
  const [corners, setCorners] = useState<LngLat[]>(data.boundary ?? []);
  const [dirty, setDirty] = useState(false);
  const [armed, setArmed] = useState<Armed>(null);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [pending, start] = useTransition();
  const [homeId, setHomeId] = useState("");

  // A saved boundary from the server replaces the draft unless the admin is mid-edit.
  const savedKey = JSON.stringify(data.boundary);
  useEffect(() => {
    if (!dirty) setCorners(data.boundary ?? []);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [savedKey]);

  function run(action: Action, fields: Record<string, string>, after?: (r: ActionState) => void) {
    const fd = new FormData();
    for (const [k, v] of Object.entries(fields)) fd.set(k, v);
    setMsg(null);
    start(async () => {
      const r = await runAction(action, fd);
      setMsg(r?.ok ? { ok: true, text: r.message ?? "Saved." } : { ok: false, text: r?.error ?? "That did not work." });
      after?.(r);
    });
  }

  const centre = (): LngLat | null => {
    if (!map) return null;
    const c = map.getCenter();
    return [round(c.lng), round(c.lat)];
  };

  // What a click on the map (or "at the map centre") does right now.
  const placeAt = (p: LngLat, a: Armed) => {
    const [lng, lat] = p.map(round) as LngLat;
    if (!a) return;
    if (a.what === "gate") run(pinGate, { id: a.id, lat: String(lat), lng: String(lng) });
    else if (a.what === "home") run(pinHome, { id: a.id, lat: String(lat), lng: String(lng) });
    else if (a.what === "place") run(createPlace, { name: a.name, kind: a.kind, lat: String(lat), lng: String(lng) }, (r) => r?.ok && formRef.current?.reset());
    else if (a.what === "move-place") run(updatePlace, { id: a.id, lat: String(lat), lng: String(lng) });
  };

  // Every change to the outline goes through here, so Undo can step back through clicks and drags alike.
  const past = useRef<LngLat[][]>([]);
  const [canUndo, setCanUndo] = useState(false);
  const now = useRef(corners);
  now.current = corners;
  const change = (next: (c: LngLat[]) => LngLat[]) => {
    const cur = now.current;
    past.current = [...past.current.slice(-49), cur];
    now.current = next(cur);
    setCorners(now.current);
    setCanUndo(true);
    setDirty(true);
  };
  const undo = () => {
    const prev = past.current.pop();
    if (prev) setCorners(prev);
    setCanUndo(past.current.length > 0);
    setDirty(true);
  };

  const addCorner = (p: LngLat) => change((c) => insertCorner(c, roundP(p)));

  /** A box in the middle of the part of the map the panel does not cover: four corners the admin
   * drags onto the walls. Never wider than an estate (about 500 m); the map zooms to fit it. */
  const panelRef = useRef<HTMLElement>(null);
  const startBox = () => {
    if (!map) return;
    const canvas = map.getCanvas().getBoundingClientRect();
    const panel = panelRef.current?.getBoundingClientRect();
    const left = panel && panel.right < canvas.left + canvas.width * 0.6 ? panel.right - canvas.left : 0;
    const top = Math.min(140, canvas.height * 0.15); // the header's glass sits over the top of the map
    const cx = (left + canvas.width) / 2;
    const cy = (top + canvas.height) / 2;
    const half = { x: (canvas.width - left) * 0.25, y: (canvas.height - top) * 0.25 };
    const nw = map.unproject([cx - half.x, cy - half.y]);
    const se = map.unproject([cx + half.x, cy + half.y]);
    let [w, n, e, s] = [nw.lng, nw.lat, se.lng, se.lat];
    const k = metres((n + s) / 2);
    const MAX = 500;
    if ((e - w) * k.x > MAX) {
      const mid = map.unproject([cx, cy]);
      // Keep the visible area's shape: on screen, pixels are the same size in both directions.
      const hx = MAX / 2 / k.x;
      const hy = ((MAX / 2) * (half.y / half.x)) / k.y;
      [w, e, n, s] = [mid.lng - hx, mid.lng + hx, mid.lat + hy, mid.lat - hy];
      map.fitBounds([w, s, e, n], { padding: { left: left + 80, top: top + 80, right: 80, bottom: 80 }, duration: 0 });
    }
    change(() => [roundP([w, n]), roundP([e, n]), roundP([e, s]), roundP([w, s])]);
    setMsg(null);
  };

  // --- map clicks and Escape ----------------------------------------------------------------------
  const live = useRef({ tab, armed, placeAt, addCorner });
  live.current = { tab, armed, placeAt, addCorner };
  useEffect(() => {
    if (!map) return;
    const onClick = (e: { lngLat: { lng: number; lat: number } }) => {
      const { tab: t, armed: a } = live.current;
      const p: LngLat = [e.lngLat.lng, e.lngLat.lat];
      if (a) {
        live.current.placeAt(p, a);
        setArmed(null);
      } else if (t === "boundary") live.current.addCorner(p);
    };
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setArmed(null);
    map.on("click", onClick);
    window.addEventListener("keydown", onKey);
    return () => {
      map.off("click", onClick);
      window.removeEventListener("keydown", onKey);
    };
  }, [map]);

  useEffect(() => {
    if (!map) return;
    map.getCanvas().style.cursor = armed || tab === "boundary" ? "crosshair" : "";
    return () => {
      map.getCanvas().style.cursor = "";
    };
  }, [map, armed, tab]);

  // --- the draft outline ----------------------------------------------------------------------------
  const draftRef = useRef(draftGeo(corners));
  draftRef.current = draftGeo(corners);
  useEffect(() => {
    if (!map) return;
    const ensure = () => ensureDraft(map, draftRef.current);
    ensure();
    map.on("styledata", ensure);
    return () => {
      map.off("styledata", ensure);
      for (const id of ["ed-draft-line", "ed-draft-fill"]) if (map.getLayer(id)) map.removeLayer(id);
      if (map.getSource("ed-draft")) map.removeSource("ed-draft");
    };
  }, [map]);
  useEffect(() => {
    (map?.getSource("ed-draft") as GeoJSONSource | undefined)?.setData(draftRef.current);
  }, [map, corners]);

  // --- pins: corners, gates, places, homes ------------------------------------------------------------
  const pins = useRef(new Map<string, Marker>());
  const homeName = useMemo(() => new Map(homes.map((h) => [h.id, h.address])), [homes]);
  useEffect(() => {
    if (!map || !lib) return;
    const store = pins.current;
    const want = new Set<string>();
    const put = (key: string, kind: string, label: string, p: LngLat, draggable: boolean, onDrop: (p: LngLat, m: Marker) => void) => {
      want.add(key);
      let m = store.get(key);
      if (!m) {
        m = new (lib as MapLib).Marker({ element: pinEl(kind, label), anchor: "center", draggable }).setLngLat(p).addTo(map);
        const marker = m;
        marker.on("dragend", () => {
          const ll = marker.getLngLat();
          (marker as Marker & { _drop?: (p: LngLat, m: Marker) => void })._drop?.([ll.lng, ll.lat], marker);
        });
        store.set(key, m);
      } else {
        m.setLngLat(p);
        m.setDraggable(draggable);
        const t = m.getElement().querySelector(".gl-m__tag");
        const text = kind === "corner" ? label : label.toUpperCase();
        if (t && t.textContent !== text) t.textContent = text;
      }
      (m as Marker & { _drop?: (p: LngLat, m: Marker) => void })._drop = onDrop;
    };

    if (tab === "boundary")
      corners.forEach((c, i) =>
        put(`corner:${i}`, "corner", String(i + 1), c, true, (p) => change((all) => all.map((x, j) => (j === i ? roundP(p) : x)))),
      );
    for (const g of data.gates) {
      if (g.lat == null || g.lng == null) continue;
      const home: LngLat = [g.lng, g.lat];
      put(`gate:${g.id}`, "gate", g.name, home, tab === "gates", (p, m) =>
        run(pinGate, { id: g.id, lat: String(round(p[1])), lng: String(round(p[0])) }, (r) => !r?.ok && m.setLngLat(home)),
      );
    }
    for (const pl of data.places) {
      const home: LngLat = [pl.lng, pl.lat];
      put(`place:${pl.id}`, "place", pl.name, home, tab === "places", (p, m) =>
        run(updatePlace, { id: pl.id, lat: String(round(p[1])), lng: String(round(p[0])) }, (r) => !r?.ok && m.setLngLat(home)),
      );
    }
    for (const h of data.homes) {
      const home: LngLat = [h.lng, h.lat];
      put(`home:${h.id}`, "home", homeName.get(h.id) ?? h.address, home, tab === "homes", (p, m) =>
        run(pinHome, { id: h.id, lat: String(round(p[1])), lng: String(round(p[0])) }, (r) => !r?.ok && m.setLngLat(home)),
      );
    }
    for (const [key, m] of store) {
      if (!want.has(key)) {
        m.remove();
        store.delete(key);
      }
    }
    // run() is stable enough: it only closes over setters and actions.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [map, lib, tab, corners, data, homeName]);
  useEffect(() => {
    const store = pins.current;
    return () => {
      store.forEach((m) => m.remove());
      store.clear();
    };
  }, []);

  // --- the panel ------------------------------------------------------------------------------------------
  const formRef = useRef<HTMLFormElement>(null);
  const atCentre = (a: Exclude<Armed, null>) => {
    const c = centre();
    if (c) placeAt(c, a);
  };
  const disabled = !hasBoundary;
  const size = useMemo(() => outlineSize(corners), [corners]);

  function addPlace(e: FormEvent<HTMLFormElement>, where: "centre" | "click") {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    const name = String(fd.get("name") ?? "").trim();
    const kind = (String(fd.get("kind") ?? "amenity") as PlaceKind) || "amenity";
    if (name.length < 2) {
      setMsg({ ok: false, text: "Give the place a name of at least 2 letters." });
      return;
    }
    if (where === "centre") atCentre({ what: "place", name, kind });
    else setArmed({ what: "place", name, kind });
  }

  const unpinned = data.gates.filter((g) => g.lat == null);

  return (
    <>
      <div className="dash-crosshair" aria-hidden="true" />
      <section ref={panelRef} className="dash-glass dash-editor" aria-labelledby="editor-title">
        <p className="dash-crumbs">
          <Link href="/dashboard/settings">Staff and settings</Link> <span aria-hidden="true">/</span> Estate map
        </p>
        <h1 className="dash-h1" id="editor-title">
          Estate map
        </h1>
        <p className="dash-small dash-muted">
          The map behind the dashboard is locked to the boundary you draw here. Gates, places and homes must sit inside it.
        </p>

        <div className="dash-seg" role="group" aria-label="What to edit">
          {TABS.map((t) => (
            <button
              key={t.id}
              type="button"
              className="dash-seg__btn"
              aria-pressed={tab === t.id}
              onClick={() => {
                setTab(t.id);
                setArmed(null);
              }}
            >
              {t.label}
            </button>
          ))}
        </div>

        {armed && (
          <p className="dash-msg dash-msg--warn" role="status">
            Click the map where {armed.what === "place" || armed.what === "move-place" ? armed.name : armed.name} is.{" "}
            <button type="button" className="dash-link-btn" onClick={() => setArmed(null)}>
              Cancel
            </button>
          </p>
        )}
        {msg && (
          <p className={`dash-msg ${msg.ok ? "dash-msg--ok" : "dash-msg--error"}`} role={msg.ok ? "status" : "alert"}>
            {msg.text}
          </p>
        )}
        {dirty && tab !== "boundary" && <p className="dash-msg dash-msg--warn">The boundary has changes that are not saved yet.</p>}

        {tab === "boundary" && (
          <div className="dash-editor__body">
            <ol className="dash-steps">
              {!hasBoundary && (
                <li className="dash-step">
                  <h2 className="dash-step__title">Find your estate</h2>
                  <FindEstate map={map} onMessage={setMsg} />
                </li>
              )}
              <li className="dash-step">
                <h2 className="dash-step__title">Outline it</h2>
                {corners.length === 0 ? (
                  <>
                    <p className="dash-small">Put a box on the map, then drag its corners onto the estate&apos;s walls or fence.</p>
                    <button type="button" className="dash-btn dash-btn--primary dash-btn--sm" onClick={startBox} disabled={!map}>
                      Start with a box
                    </button>
                    <p className="dash-small dash-muted">Or click the map at each corner of the estate.</p>
                  </>
                ) : (
                  <p className="dash-small">
                    Drag the numbered corners onto the walls. Where a wall bends, click the map there to add a corner. From the keyboard, move the map
                    with the arrow keys and add a corner at the cross in the middle.
                  </p>
                )}
                <p className="dash-small dash-muted" aria-live="polite">
                  {corners.length === 0
                    ? ""
                    : corners.length < 3
                      ? `${corners.length} ${corners.length === 1 ? "corner" : "corners"}, at least 3 needed.`
                      : `${corners.length} corners. ${size?.text ?? ""}`}
                </p>
                {size?.warn && (
                  <p className="dash-msg dash-msg--warn" role="status">
                    {size.warn}
                  </p>
                )}
                {corners.length > 0 && (
                  <div className="dash-actions dash-actions--tight">
                    <button type="button" className="dash-btn dash-btn--ghost dash-btn--sm" onClick={() => centre() && addCorner(centre()!)}>
                      Add a corner at the cross
                    </button>
                    <button type="button" className="dash-btn dash-btn--ghost dash-btn--sm" disabled={!canUndo} onClick={undo}>
                      Undo
                    </button>
                    <button type="button" className="dash-btn dash-btn--ghost dash-btn--sm" onClick={() => change(() => [])}>
                      Start again
                    </button>
                    {dirty && hasBoundary && (
                      <button
                        type="button"
                        className="dash-btn dash-btn--quiet dash-btn--sm"
                        onClick={() => {
                          setCorners(data.boundary ?? []);
                          past.current = [];
                          setCanUndo(false);
                          setDirty(false);
                        }}
                      >
                        Go back to the saved boundary
                      </button>
                    )}
                  </div>
                )}
              </li>
              <li className="dash-step">
                <h2 className="dash-step__title">Save</h2>
                <p className="dash-small dash-muted">After saving, pin the gates, then the estate&apos;s places and homes.</p>
                <button
                  type="button"
                  className="dash-btn dash-btn--primary"
                  disabled={corners.length < 3 || pending || !dirty}
                  onClick={() =>
                    run(saveBoundary, { ring: JSON.stringify(corners) }, (r) => {
                      if (!r?.ok) return;
                      setDirty(false);
                      past.current = [];
                      setCanUndo(false);
                      if (!hasBoundary) setTab("gates");
                    })
                  }
                >
                  {pending ? "Saving..." : "Save boundary"}
                </button>
              </li>
            </ol>
          </div>
        )}

        {tab !== "boundary" && disabled && <p className="dash-msg dash-msg--warn">Draw and save the boundary first.</p>}

        {tab === "gates" && !disabled && (
          <div className="dash-editor__body">
            <p className="dash-small">Pin each gate where it is. Drag a pin to move it; it saves when you let go.</p>
            <ul className="dash-panel__list">
              {data.gates.map((g) => (
                <li key={g.id} className="dash-panel__item">
                  <div className="dash-panel__main">
                    <strong>{g.name}</strong>
                    <span className="dash-hint">{g.lat == null ? "Not pinned yet" : "Pinned"}</span>
                  </div>
                  <span className="dash-row-actions">
                    {g.lat != null && g.lng != null && (
                      <button type="button" className="dash-btn dash-btn--quiet dash-btn--sm" onClick={() => flyTo(g.lng!, g.lat!)}>
                        Show
                      </button>
                    )}
                    <button type="button" className="dash-btn dash-btn--quiet dash-btn--sm" onClick={() => setArmed({ what: "gate", id: g.id, name: g.name })}>
                      Click to place
                    </button>
                    <button type="button" className="dash-btn dash-btn--quiet dash-btn--sm" onClick={() => atCentre({ what: "gate", id: g.id, name: g.name })}>
                      At map centre
                    </button>
                    {g.lat != null && (
                      <button type="button" className="dash-btn dash-btn--quiet dash-btn--sm" onClick={() => run(pinGate, { id: g.id, clear: "true" })}>
                        Remove pin
                      </button>
                    )}
                  </span>
                </li>
              ))}
            </ul>
            {unpinned.length > 0 && <p className="dash-hint">{unpinned.length} of {data.gates.length} gates are not on the map yet.</p>}
          </div>
        )}

        {tab === "places" && !disabled && (
          <div className="dash-editor__body">
            <p className="dash-small">
              Places residents can ride the shuttle to or from, and the estate&rsquo;s security posts. Drag a pin to move it; it saves when you let go.
            </p>
            <form ref={formRef} className="dash-form dash-editor__add" onSubmit={(e) => addPlace(e, "centre")}>
              <div className="dash-grid2">
                <div className="dash-field">
                  <label htmlFor="place-name">Name</label>
                  <input id="place-name" name="name" className="dash-input" required minLength={2} maxLength={80} placeholder="For example, Clubhouse" />
                </div>
                <div className="dash-field">
                  <label htmlFor="place-kind">Kind</label>
                  <select id="place-kind" name="kind" className="dash-input" defaultValue="amenity">
                    {(Object.keys(PLACE_KIND) as PlaceKind[]).map((k) => (
                      <option key={k} value={k}>
                        {PLACE_KIND[k]}
                      </option>
                    ))}
                  </select>
                </div>
              </div>
              <div className="dash-actions dash-actions--tight">
                <button type="submit" className="dash-btn dash-btn--primary dash-btn--sm" disabled={pending}>
                  Add at the map centre
                </button>
                <button
                  type="button"
                  className="dash-btn dash-btn--ghost dash-btn--sm"
                  onClick={(e) => {
                    const form = e.currentTarget.form;
                    if (form) addPlace({ preventDefault() {}, currentTarget: form } as unknown as FormEvent<HTMLFormElement>, "click");
                  }}
                >
                  Add where I click
                </button>
              </div>
            </form>
            {data.places.length === 0 ? (
              <p className="dash-hint">No places yet.</p>
            ) : (
              <ul className="dash-panel__list">
                {data.places.map((p) => (
                  <li key={p.id} className="dash-panel__item dash-panel__item--wrap">
                    <div className="dash-panel__main">
                      <strong>{p.name}</strong>
                      <span className="dash-hint">{PLACE_KIND[p.kind]}</span>
                    </div>
                    <span className="dash-row-actions">
                      <button type="button" className="dash-btn dash-btn--quiet dash-btn--sm" onClick={() => flyTo(p.lng, p.lat)}>
                        Show
                      </button>
                      <button type="button" className="dash-btn dash-btn--quiet dash-btn--sm" onClick={() => atCentre({ what: "move-place", id: p.id, name: p.name })}>
                        Move to map centre
                      </button>
                      <details className="dash-details dash-details--inline">
                        <summary>Edit</summary>
                        <ActionForm action={updatePlace} hidden={{ id: p.id }} reset={false} submit="Save" submitClass="dash-btn dash-btn--primary dash-btn--sm">
                          <div className="dash-field">
                            <label htmlFor={`pn-${p.id}`}>Name</label>
                            <input id={`pn-${p.id}`} name="name" className="dash-input" defaultValue={p.name} required minLength={2} maxLength={80} />
                          </div>
                          <div className="dash-field">
                            <label htmlFor={`pk-${p.id}`}>Kind</label>
                            <select id={`pk-${p.id}`} name="kind" className="dash-input" defaultValue={p.kind}>
                              {(Object.keys(PLACE_KIND) as PlaceKind[]).map((k) => (
                                <option key={k} value={k}>
                                  {PLACE_KIND[k]}
                                </option>
                              ))}
                            </select>
                          </div>
                        </ActionForm>
                      </details>
                      <ConfirmButton action={deletePlace} hidden={{ id: p.id }} label="Delete" title={`Delete ${p.name}?`} confirmLabel="Delete place">
                        <p>Rides already booked to or from {p.name} keep its name. Residents can no longer ask the shuttle to go there.</p>
                      </ConfirmButton>
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </div>
        )}

        {tab === "homes" && !disabled && (
          <div className="dash-editor__body">
            <p className="dash-small">Optional. Pinned homes show as small dots, and the shuttle panel can point riders to them.</p>
            {homes.length === 0 ? (
              <p className="dash-hint">No homes in the register yet.</p>
            ) : (
              <div className="dash-form">
                <div className="dash-field">
                  <label htmlFor="pin-home">Home</label>
                  <select id="pin-home" className="dash-input" value={homeId} onChange={(e) => setHomeId(e.target.value)}>
                    <option value="">Choose a home</option>
                    {Array.from(new Set(homes.map((h) => h.group))).map((grp) => (
                      <optgroup key={grp} label={grp}>
                        {homes
                          .filter((h) => h.group === grp)
                          .map((h) => (
                            <option key={h.id} value={h.id}>
                              {h.address}
                              {data.homes.some((x) => x.id === h.id) ? " (pinned)" : ""}
                            </option>
                          ))}
                      </optgroup>
                    ))}
                  </select>
                </div>
                <div className="dash-actions dash-actions--tight">
                  <button
                    type="button"
                    className="dash-btn dash-btn--ghost dash-btn--sm"
                    disabled={!homeId}
                    onClick={() => setArmed({ what: "home", id: homeId, name: homeName.get(homeId) ?? "the home" })}
                  >
                    Click to place
                  </button>
                  <button
                    type="button"
                    className="dash-btn dash-btn--ghost dash-btn--sm"
                    disabled={!homeId}
                    onClick={() => atCentre({ what: "home", id: homeId, name: homeName.get(homeId) ?? "the home" })}
                  >
                    At map centre
                  </button>
                </div>
              </div>
            )}
            {data.homes.length > 0 && (
              <ul className="dash-panel__list">
                {data.homes.map((h) => (
                  <li key={h.id} className="dash-panel__item">
                    <div className="dash-panel__main">
                      <strong>{homeName.get(h.id) ?? h.address}</strong>
                    </div>
                    <span className="dash-row-actions">
                      <button type="button" className="dash-btn dash-btn--quiet dash-btn--sm" onClick={() => flyTo(h.lng, h.lat)}>
                        Show
                      </button>
                      <button type="button" className="dash-btn dash-btn--quiet dash-btn--sm" onClick={() => run(pinHome, { id: h.id, clear: "true" })}>
                        Remove pin
                      </button>
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </div>
        )}
      </section>
    </>
  );
}

// --- find the estate (before a boundary exists) ----------------------------------------------------

type Hit = { label: string; lat: number; lng: number; bbox: [number, number, number, number] | null };

/** Coordinates typed or pasted: "6.6155, 3.3870", or a Google Maps link ("@6.61,3.38," or "!3d6.61!4d3.38"). */
function coordsIn(raw: string): LngLat | null {
  const ok = (lat: number, lng: number): LngLat | null =>
    Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 ? [lng, lat] : null;
  const pin = raw.match(/!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/);
  if (pin) return ok(Number(pin[1]), Number(pin[2]));
  const at = raw.match(/@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/);
  if (at) return ok(Number(at[1]), Number(at[2]));
  const pair = raw.trim().match(/^(-?\d+(?:\.\d+)?)\s*[,\s]\s*(-?\d+(?:\.\d+)?)$/);
  return pair ? ok(Number(pair[1]), Number(pair[2])) : null;
}

/** The first two parts of an OpenStreetMap address, then the rest, so the list reads quickly. */
function splitLabel(label: string) {
  const parts = label.split(", ");
  return { head: parts.slice(0, 2).join(", "), rest: parts.slice(2, 5).join(", ") };
}

function FindEstate({ map, onMessage }: { map: MapLibre | null; onMessage: (m: { ok: boolean; text: string } | null) => void }) {
  const [hits, setHits] = useState<Hit[] | null>(null);
  const [busy, setBusy] = useState<"search" | "locate" | null>(null);

  const go = (h: Hit) => {
    if (!map) return;
    // A large match (a whole area) fits its box; a street or building zooms in close.
    if (h.bbox && Math.abs(h.bbox[2] - h.bbox[0]) > 0.004) map.fitBounds(h.bbox, { padding: 40, maxZoom: 17, duration: 0 });
    else map.jumpTo({ center: [h.lng, h.lat], zoom: 17 });
    setHits(null);
    onMessage({ ok: true, text: "Found. Zoom in until you can see the estate's walls, then outline it below." });
  };

  async function find(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const q = String(new FormData(e.currentTarget).get("where") ?? "").trim();
    onMessage(null);
    setHits(null);
    const c = coordsIn(q);
    if (c) {
      map?.jumpTo({ center: c, zoom: 17 });
      return;
    }
    if (q.length < 3) {
      onMessage({ ok: false, text: "Type the estate's name, or a nearby street, area or landmark." });
      return;
    }
    setBusy("search");
    try {
      const res = await fetch(`/dashboard/geocode?${new URLSearchParams({ q })}`, { signal: AbortSignal.timeout(15000) });
      const body = (await res.json().catch(() => ({}))) as { results?: Hit[]; error?: string };
      if (!res.ok) return onMessage({ ok: false, text: body.error ?? "The place search did not work. Try again." });
      const results = body.results ?? [];
      if (results.length === 0) return onMessage({ ok: false, text: "Nothing found. Try a nearby street, area or landmark, such as \"Admiralty Way, Lekki\"." });
      if (results.length === 1) return go(results[0]);
      setHits(results);
    } catch {
      onMessage({ ok: false, text: "The place search did not answer. Check the connection and try again." });
    } finally {
      setBusy(null);
    }
  }

  function locate() {
    if (!("geolocation" in navigator)) return onMessage({ ok: false, text: "This browser cannot share its location. Search instead." });
    onMessage(null);
    setBusy("locate");
    navigator.geolocation.getCurrentPosition(
      (p) => {
        setBusy(null);
        map?.jumpTo({ center: [p.coords.longitude, p.coords.latitude], zoom: 17 });
        onMessage({ ok: true, text: "The map is on your location. Outline the estate below." });
      },
      (err) => {
        setBusy(null);
        onMessage({
          ok: false,
          text: err.code === err.PERMISSION_DENIED ? "Location is blocked for this site. Allow it in the browser, or search instead." : "Your location could not be found. Search instead.",
        });
      },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 60000 },
    );
  }

  return (
    <div className="dash-find">
      <form className="dash-inline-form" onSubmit={find} role="search">
        <label htmlFor="find-estate" className="dash-inline-label">
          Find the estate
        </label>
        <input
          id="find-estate"
          name="where"
          className="dash-input dash-input--sm"
          placeholder="Estate name, street or area"
          autoComplete="off"
          enterKeyHint="search"
        />
        <button type="submit" className="dash-btn dash-btn--ghost dash-btn--sm" disabled={busy !== null}>
          {busy === "search" ? "Finding…" : "Find"}
        </button>
        <button type="button" className="dash-link-btn" onClick={locate} disabled={busy !== null}>
          {busy === "locate" ? "Finding you…" : "Use my location"}
        </button>
      </form>
      {hits && (
        <ul className="dash-find__hits" aria-label="Places found">
          {hits.map((h) => {
            const { head, rest } = splitLabel(h.label);
            return (
              <li key={`${h.lat},${h.lng}`}>
                <button type="button" className="dash-find__hit" onClick={() => go(h)}>
                  <span className="dash-find__head">{head}</span>
                  {rest && <span className="dash-find__rest">{rest}</span>}
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
