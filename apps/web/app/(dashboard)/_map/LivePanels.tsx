"use client";

import Link from "next/link";
import { useEffect, useState, type ReactNode } from "react";
import { GUARD_ROLE, PLACE_KIND, RIDE_KIND, RIDE_STATE, ago, fmtTime } from "@/app/(dashboard)/_lib/format";
import type { LiveGate, LiveShuttle, MapPlace, RideBrief } from "@/app/(dashboard)/_lib/types";
import { useEstateMap } from "./context";

// The overview's floating panels. They list everything the map markers show, in words, so the
// live map works without seeing it: each item can also move the map to where it is.

const COMPASS = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"];
function heading(deg: number | null) {
  if (deg == null) return null;
  return COMPASS[Math.round((((deg % 360) + 360) % 360) / 45) % 8];
}

/** Re-renders every 15 seconds so "2 min ago" stays true between polls. */
function useNow(ms = 15_000) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), ms);
    return () => clearInterval(t);
  }, [ms]);
  return now;
}

function ShowOnMap({ lng, lat, what }: { lng: number | null; lat: number | null; what: string }) {
  const { flyTo } = useEstateMap();
  if (lng == null || lat == null) return <span className="dash-hint">Not on the map yet</span>;
  return (
    <button
      type="button"
      className="dash-btn dash-btn--quiet dash-btn--sm dash-live__show"
      onClick={() => {
        flyTo(lng, lat);
        // On a phone the map is above the panels.
        if (window.matchMedia("(max-width: 899px)").matches) window.scrollTo({ top: 0, behavior: "smooth" });
      }}
    >
      Show <span className="sr-only">{what}</span> on map
    </button>
  );
}

function Panel({ id, title, count, children }: { id: string; title: string; count?: number; children: ReactNode }) {
  return (
    <section className="dash-float dash-panel" aria-labelledby={id}>
      <h2 className="dash-panel__title" id={id}>
        {title}
        {count != null && <span className="dash-panel__count tnum">{count}</span>}
      </h2>
      {children}
    </section>
  );
}

function GateItem({ g, now }: { g: LiveGate; now: number }) {
  return (
    <li className={`dash-panel__item${g.quiet ? " is-bad" : ""}`}>
      <div className="dash-panel__main">
        <strong>{g.name}</strong>
        {g.on_duty.length === 0 ? (
          <span className="dash-hint">Nobody on duty</span>
        ) : (
          g.on_duty.map((d) => (
            <span key={`${d.guard}-${d.since}`} className="dash-hint">
              {d.guard} ({GUARD_ROLE[d.role]}), on since {fmtTime(d.since)}
            </span>
          ))
        )}
        {g.phones === 0 ? (
          <span className="dash-hint">No gate phone paired</span>
        ) : g.quiet ? (
          <span className="dash-problem dash-problem--bad">
            Phone quiet: {g.phone_last_sync_at ? `last synced ${ago(g.phone_last_sync_at, now)}` : "never synced"}
          </span>
        ) : (
          <span className="dash-hint">Phone synced {ago(g.phone_last_sync_at, now)}</span>
        )}
      </div>
      <ShowOnMap lng={g.lng} lat={g.lat} what={g.name} />
    </li>
  );
}

function rideLine(r: RideBrief, now: number) {
  const due = Date.parse(r.wanted_at);
  const when = due > now ? `due at ${fmtTime(r.wanted_at)}` : `waiting ${r.waiting_minutes} min`;
  return { route: `${r.from} to ${r.to}`, when };
}

function ShuttleItem({ s, now }: { s: LiveShuttle; now: number }) {
  const h = heading(s.heading);
  return (
    <li className={`dash-panel__item${s.stale ? " is-stale" : ""}`}>
      <div className="dash-panel__main">
        <strong>{s.rider}</strong>
        <span className="dash-hint">
          {s.shuttle ? `On ${s.shuttle}` : "Motorcycle not recorded"}
          {h && !s.stale ? `, heading ${h}` : ""}
        </span>
        {s.at ? (
          <span className={s.stale ? "dash-problem dash-problem--warn" : "dash-hint"}>
            {s.stale ? `No position since ${ago(s.at, now)}` : `Position ${ago(s.at, now)}`}
          </span>
        ) : (
          <span className="dash-problem dash-problem--warn">No position yet this shift</span>
        )}
        {s.ride ? (
          <span className="dash-hint">
            {RIDE_STATE[s.ride.state].label}: {s.ride.from} to {s.ride.to}
          </span>
        ) : (
          <span className="dash-hint">No ride right now</span>
        )}
      </div>
      <ShowOnMap lng={s.lng} lat={s.lat} what={s.rider} />
    </li>
  );
}

export function LivePanels({ estate, shuttle }: { estate: string; shuttle: boolean }) {
  const { live, liveError, liveAt, canSeePositions, admin } = useEstateMap();
  const now = useNow();

  const counts = live?.counts;
  return (
    <div className="dash-live">
      <header className="dash-float dash-live__top">
        <div className="dash-live__title">
          <h1 className="dash-h1">Overview</h1>
          <p className="dash-small dash-muted" aria-live="polite">
            {liveError ? (
              <span className="dash-problem dash-problem--warn">{liveError}</span>
            ) : liveAt ? (
              `${estate} right now. Updated ${fmtTime(new Date(liveAt).toISOString())}, every 10 seconds.`
            ) : (
              "Loading the live map..."
            )}
          </p>
        </div>
        <dl className="dash-live__counts">
          <Count label="Guests inside" value={counts?.inside} />
          <Count label="Past their time" value={counts?.overdue} warn={!!counts?.overdue} />
          {shuttle && <Count label="Rides open" value={counts?.rides_open} />}
          <Count label="On duty" value={counts?.on_duty} />
        </dl>
        {admin && (
          <Link href="/dashboard/settings/map" className="dash-btn dash-btn--ghost dash-btn--sm dash-live__edit">
            Edit map
          </Link>
        )}
      </header>

      <div className="dash-live__panels">
        {live && (
          <>
            <Panel id="live-gates" title="Gates" count={live.gates.length}>
              <ul className="dash-panel__list">
                {live.gates.map((g) => (
                  <GateItem key={g.id} g={g} now={now} />
                ))}
              </ul>
            </Panel>

            {shuttle && live.shuttles && (
              <Panel id="live-shuttles" title="Shuttles" count={live.shuttles.length}>
                {live.shuttles.length === 0 ? (
                  <p className="dash-hint">No rider is on shift.</p>
                ) : (
                  <ul className="dash-panel__list">
                    {live.shuttles.map((s) => (
                      <ShuttleItem key={s.shift_id} s={s} now={now} />
                    ))}
                  </ul>
                )}
              </Panel>
            )}
            {shuttle && !canSeePositions && (
              <p className="dash-float dash-panel dash-hint">Where the shuttle riders are is shown only to the estate admin, the committee and the security head.</p>
            )}

            {shuttle && (
              <Panel id="live-rides" title="Rides waiting" count={live.rides_waiting.length}>
                {live.rides_waiting.length === 0 ? (
                  <p className="dash-hint">Nobody is waiting for the shuttle.</p>
                ) : (
                  <ul className="dash-panel__list">
                    {live.rides_waiting.map((r) => {
                      const l = rideLine(r, now);
                      return (
                        <li key={r.id} className={`dash-panel__item${r.waiting_minutes >= 10 ? " is-warn" : ""}`}>
                          <div className="dash-panel__main">
                            <strong>{l.route}</strong>
                            <span className="dash-hint">
                              {RIDE_KIND[r.kind]}, {l.when}
                            </span>
                          </div>
                          <ShowOnMap lng={r.lng} lat={r.lat} what={`the pickup for ${l.route}`} />
                        </li>
                      );
                    })}
                  </ul>
                )}
              </Panel>
            )}

            <Panel id="live-places" title="Estate places" count={live.places.length}>
              {live.places.length === 0 ? (
                <p className="dash-hint">{admin ? "No places yet. Add them in the map editor." : "No places on the map yet."}</p>
              ) : (
                <ul className="dash-panel__list">
                  {live.places.map((p: MapPlace) => (
                    <li key={p.id} className="dash-panel__item">
                      <div className="dash-panel__main">
                        <strong>{p.name}</strong>
                        <span className="dash-hint">{PLACE_KIND[p.kind]}</span>
                      </div>
                      <ShowOnMap lng={p.lng} lat={p.lat} what={p.name} />
                    </li>
                  ))}
                </ul>
              )}
            </Panel>
          </>
        )}
      </div>
    </div>
  );
}

function Count({ label, value, warn }: { label: string; value: number | undefined; warn?: boolean }) {
  return (
    <div className={`dash-live__count${warn ? " is-warn" : ""}`}>
      <dt>{label}</dt>
      <dd className="tnum">{value ?? "-"}</dd>
    </div>
  );
}
