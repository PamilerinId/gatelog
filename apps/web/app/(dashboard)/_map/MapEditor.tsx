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

export function MapEditor({ data, homes }: { data: EstateMapData; homes: HomeOption[] }) {
  const { map, lib, flyTo } = useEstateMap();
  const hasBoundary = !!data.boundary && data.boundary.length >= 3;
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

  const addCorner = (p: LngLat) => {
    setCorners((c) => [...c, [round(p[0]), round(p[1])]]);
    setDirty(true);
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
        put(`corner:${i}`, "corner", String(i + 1), c, true, (p) => {
          setCorners((all) => all.map((x, j) => (j === i ? [round(p[0]), round(p[1])] : x)));
          setDirty(true);
        }),
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
      <section className="dash-glass dash-editor" aria-labelledby="editor-title">
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
            <p className="dash-small">
              Click the map at each corner of the estate, in order around its edge. Drag a numbered corner to move it. From the keyboard, move the
              map with the arrow keys and add a corner at the cross in the middle.
            </p>
            {!hasBoundary && (
              <form
                className="dash-inline-form"
                onSubmit={(e) => {
                  e.preventDefault();
                  const raw = String(new FormData(e.currentTarget).get("where") ?? "");
                  const [a, b] = raw.split(/[,\s]+/).filter(Boolean).map(Number);
                  if (!Number.isFinite(a) || !Number.isFinite(b) || Math.abs(a) > 90 || Math.abs(b) > 180) {
                    setMsg({ ok: false, text: "Type the estate's latitude and longitude, for example 6.6155, 3.3870." });
                    return;
                  }
                  setMsg(null);
                  map?.jumpTo({ center: [b, a], zoom: 16 });
                }}
              >
                <label htmlFor="find-estate" className="dash-inline-label">
                  Find the estate
                </label>
                <input id="find-estate" name="where" className="dash-input dash-input--sm" placeholder="Latitude, longitude" inputMode="decimal" autoComplete="off" />
                <button type="submit" className="dash-btn dash-btn--ghost dash-btn--sm">
                  Go
                </button>
              </form>
            )}
            <p className="dash-small dash-muted" aria-live="polite">
              {corners.length === 0 ? "No corners yet." : `${corners.length} ${corners.length === 1 ? "corner" : "corners"}${corners.length < 3 ? ", at least 3 needed" : ""}.`}
            </p>
            <div className="dash-actions dash-actions--tight">
              <button type="button" className="dash-btn dash-btn--ghost dash-btn--sm" onClick={() => centre() && addCorner(centre()!)}>
                Add a corner at the map centre
              </button>
              <button
                type="button"
                className="dash-btn dash-btn--ghost dash-btn--sm"
                disabled={corners.length === 0}
                onClick={() => {
                  setCorners((c) => c.slice(0, -1));
                  setDirty(true);
                }}
              >
                Undo last corner
              </button>
              <button
                type="button"
                className="dash-btn dash-btn--ghost dash-btn--sm"
                disabled={corners.length === 0}
                onClick={() => {
                  setCorners([]);
                  setDirty(true);
                }}
              >
                Clear
              </button>
              {dirty && hasBoundary && (
                <button
                  type="button"
                  className="dash-btn dash-btn--quiet dash-btn--sm"
                  onClick={() => {
                    setCorners(data.boundary ?? []);
                    setDirty(false);
                  }}
                >
                  Go back to the saved boundary
                </button>
              )}
            </div>
            <button
              type="button"
              className="dash-btn dash-btn--primary"
              disabled={corners.length < 3 || pending || !dirty}
              onClick={() => run(saveBoundary, { ring: JSON.stringify(corners) }, (r) => r?.ok && setDirty(false))}
            >
              {pending ? "Saving..." : "Save boundary"}
            </button>
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
