"use client";

import Link from "next/link";
import { useEffect, useState, type ReactNode } from "react";
import { GUARD_ROLE, PLACE_KIND, RIDE_KIND, RIDE_STATE, ago, fmtTime, pct } from "@/app/(dashboard)/_lib/format";
import type { EntryMethod, GateEntry, LiveGate, LiveShuttle, RideBrief } from "@/app/(dashboard)/_lib/types";
import { useEstateMap } from "./context";
import { minutesSince, shortName, trustOf, waitLabel } from "./util";

// The overview, laid out as docs/gatelog-handoff/design/Main.dc.html: a status panel on the
// left, the live log on the right, the legend at the bottom, all floating on the live map. The
// panels say in words everything the markers show, and each item can move the map to itself.

const LOG_ROWS = 8;

const COMPASS = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"];
function heading(deg: number | null) {
  return deg == null ? null : COMPASS[Math.round((((deg % 360) + 360) % 360) / 45) % 8];
}

/** Re-renders every 15 seconds so "4 MIN" stays true between polls. */
function useNow(ms = 15_000) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), ms);
    return () => clearInterval(t);
  }, [ms]);
  return now;
}

function Show({ lng, lat, what }: { lng: number | null; lat: number | null; what: string }) {
  const { flyTo } = useEstateMap();
  if (lng == null || lat == null) return <span className="dash-mono dash-faint">NOT PINNED</span>;
  return (
    <button
      type="button"
      className="dash-show"
      onClick={() => {
        flyTo(lng, lat);
        if (window.matchMedia("(max-width: 899px)").matches) window.scrollTo({ top: 0, behavior: "smooth" });
      }}
    >
      SHOW<span className="sr-only"> {what} on the map</span>
    </button>
  );
}

function Kicker({ children, aside }: { children: ReactNode; aside?: ReactNode }) {
  return (
    <div className="dash-kicker">
      <span>{children}</span>
      {aside}
    </div>
  );
}

function Dot({ tone }: { tone: "gate" | "warn" | "guard" | "alert" | "entry" | "muted" }) {
  return <span className={`dash-dot dash-dot--${tone}`} aria-hidden="true" />;
}

// --- status ----------------------------------------------------------------------------------------

/** Phone entries today (everything let in without a code), by the API's trust level. Today's
 * summary has the split ready; the log is the fallback when the summary could not be loaded. */
function trustCounts(live: { today?: { trust?: { phone_entries: Record<string, number> } } | null; log?: GateEntry[] | null } | null) {
  const split = live?.today?.trust?.phone_entries;
  if (split) return { verified: split.verified ?? 0, pin: split.pin_verified ?? 0, unverified: split.unverified ?? 0 };
  const c = { verified: 0, pin: 0, unverified: 0 };
  for (const e of live?.log ?? []) {
    const t = e.method === "code" ? null : trustOf(e);
    if (t) c[t] += 1;
  }
  return c;
}

function GateRow({ g, now }: { g: LiveGate; now: number }) {
  const status = g.phones === 0 ? "NO PHONE" : g.quiet ? `OFFLINE ${g.phone_last_sync_at ? minutesSince(g.phone_last_sync_at, now).replace(" ", "") : ""}`.trim() : "ONLINE";
  return (
    <li className="dash-gate">
      <div className="dash-gate__top">
        <span className="dash-gate__name">{g.name}</span>
        <span className={`dash-mono dash-gate__status${g.quiet ? " is-warn" : ""}`}>
          <Dot tone={g.quiet ? "warn" : "gate"} />
          {status}
        </span>
      </div>
      <div className="dash-gate__sub">
        <span>
          {g.on_duty.length === 0
            ? "Nobody on duty"
            : g.on_duty.map((d) => `${d.guard} (${GUARD_ROLE[d.role]}) since ${fmtTime(d.since)}`).join(", ")}
          {g.phones > 0 && (g.quiet ? `. Phone quiet${g.phone_last_sync_at ? `, last synced ${ago(g.phone_last_sync_at, now)}` : ", never synced"}.` : `. Synced ${ago(g.phone_last_sync_at, now)}.`)}
        </span>
        <Show lng={g.lng} lat={g.lat} what={g.name} />
      </div>
    </li>
  );
}

function StatusPanel({ now }: { now: number }) {
  const { live, liveError, liveAt, admin } = useEstateMap();
  const t = trustCounts(live);
  const total = t.verified + t.pin + t.unverified;
  const entries = live?.today?.entries.total ?? live?.log?.filter((e) => e.method !== "refused").length;
  const overdue = live?.counts.overdue ?? 0;
  return (
    <section className="dash-glass dash-status" aria-labelledby="status-title">
      <Kicker
        aside={
          <span className="dash-mono" aria-live="polite">
            {liveError ? <span className="dash-warn-text">RECONNECTING</span> : liveAt ? `UPDATED ${fmtTime(new Date(liveAt).toISOString())}` : "LOADING"}
          </span>
        }
      >
        <span id="status-title">STATUS · TODAY</span>
      </Kicker>
      {liveError && <p className="dash-small dash-warn-text">{liveError}</p>}
      <dl className="dash-figs">
        <div>
          <dd className="dash-mono">{live?.counts.inside ?? "..."}</dd>
          <dt>Inside now</dt>
        </div>
        <div>
          <dd className="dash-mono">{entries ?? "..."}</dd>
          <dt>Entries</dt>
        </div>
        <div>
          {live?.today?.exits.capture_rate == null ? (
            <dd className="dash-mono dash-figs__none" title="No guest has been due out yet today">
              {live ? "NONE YET" : "..."}
            </dd>
          ) : (
            <dd className="dash-mono">{pct(live.today.exits.capture_rate)}</dd>
          )}
          <dt>Exits confirmed</dt>
        </div>
        <div>
          <dd className={`dash-mono${overdue > 0 ? " dash-warn-text" : ""}`}>{live ? overdue : "..."}</dd>
          <dt>Overstays</dt>
        </div>
      </dl>
      <hr className="dash-rule" />
      <div className="dash-trust">
        <Kicker>PHONE ENTRIES BY TRUST</Kicker>
        <div className="dash-trust__bar" role="img" aria-label={`Verified ${t.verified}, PIN ${t.pin}, unverified ${t.unverified}`}>
          {total === 0 ? (
            <span className="dash-trust__empty" />
          ) : (
            <>
              <span className="dash-trust__v" style={{ flexGrow: t.verified }} />
              <span className="dash-trust__p" style={{ flexGrow: t.pin }} />
              <span className="dash-trust__u" style={{ flexGrow: t.unverified }} />
            </>
          )}
        </div>
        <div className="dash-trust__legend dash-mono">
          <span>VERIFIED {t.verified}</span>
          <span>PIN {t.pin}</span>
          <span className="dash-warn-text">UNVERIFIED {t.unverified}</span>
        </div>
      </div>
      <hr className="dash-rule" />
      <div>
        <Kicker
          aside={
            admin ? (
              <Link href="/dashboard/settings/map" className="dash-mono dash-link-mono">
                EDIT MAP
              </Link>
            ) : undefined
          }
        >
          GATES
        </Kicker>
        <ul className="dash-gates">{live?.gates.map((g) => <GateRow key={g.id} g={g} now={now} />)}</ul>
      </div>
      {live && live.places.length > 0 && (
        <details className="dash-places">
          <summary className="dash-kicker">PLACES · {live.places.length}</summary>
          <ul className="dash-gates">
            {live.places.map((p) => (
              <li key={p.id} className="dash-gate">
                <div className="dash-gate__top">
                  <span className="dash-gate__name">{p.name}</span>
                  <Show lng={p.lng} lat={p.lat} what={p.name} />
                </div>
                <div className="dash-gate__sub">{PLACE_KIND[p.kind]}</div>
              </li>
            ))}
          </ul>
        </details>
      )}
    </section>
  );
}

// --- the live log --------------------------------------------------------------------------------

const METHOD_TAG: Record<EntryMethod, string> = {
  code: "ENTRY · CODE",
  callback_confirmed: "ENTRY · CALLBACK",
  pin_confirmed: "ENTRY · PIN",
  phone_announced: "ENTRY · ANNOUNCED",
  walk_in_admitted: "ENTRY · UNVERIFIED",
  refused: "REFUSED",
};

type LogRow = { key: string; at: string; tag: string; tone?: "warn" | "alert" | "muted"; text: string; sub?: string };

type LogRowFull = LogRow & { alert?: string };

function logRows(log: GateEntry[]): LogRowFull[] {
  const rows: LogRowFull[] = [];
  for (const e of log) {
    const where = [e.address, e.gate].filter(Boolean).join(" · ");
    const name = e.name_clip_id && e.guest_name === "Voice clip" ? "Visitor (name in a voice clip)" : e.guest_name;
    const unverified = e.trust === "unverified";
    const subs = [
      e.decided_by ? `${e.method === "refused" ? "Refused" : "Let in"} by ${e.decided_by}${e.decided_alone ? ", alone at the gate" : ""}${e.reason ? `: ${e.reason}` : ""}` : null,
      unverified && e.method !== "refused" ? "Home alerted: Not you? Reply NO" : null,
    ].filter(Boolean);
    rows.push({
      key: `in-${e.id}`,
      at: e.at,
      // The design labels entries by how they were verified: an unverified entry says so, whatever the method.
      tag: unverified ? "ENTRY · UNVERIFIED" : METHOD_TAG[e.method],
      tone: unverified ? "warn" : e.method === "refused" ? "alert" : undefined,
      text: `${name} → ${where || "estate"}`,
      sub: subs.length ? subs.join(" · ") : undefined,
      alert: e.disputed_at ? `HOME SAID NO · ${fmtTime(e.disputed_at)}` : undefined,
    });
    if (e.exit_at && e.exit_method !== "rollup_closed")
      rows.push({ key: `out-${e.id}`, at: e.exit_at, tag: "EXIT", tone: "muted", text: `${name} ← ${e.address ?? "estate"}${e.gate ? ` · ${e.gate}` : ""}` });
  }
  return rows.sort((a, b) => Date.parse(b.at) - Date.parse(a.at)).slice(0, LOG_ROWS);
}

function LiveLog() {
  const { live, liveError } = useEstateMap();
  const rows = live?.log ? logRows(live.log) : null;
  return (
    <section className="dash-glass dash-log" aria-labelledby="log-title">
      <Kicker
        aside={
          <span className="dash-mono dash-log__state">
            <Dot tone={liveError ? "warn" : "alert"} />
            {liveError ? "PAUSED" : "STREAMING"}
          </span>
        }
      >
        <span id="log-title">LIVE</span>
      </Kicker>
      {rows == null ? (
        <p className="dash-log__empty">{live ? "The log could not be loaded." : "Loading..."}</p>
      ) : rows.length === 0 ? (
        <p className="dash-log__empty">No entries yet today.</p>
      ) : (
        <ol className="dash-log__list">
          {rows.map((r) => (
            <li key={r.key} className="dash-log__row">
              <time className="dash-mono dash-log__time" dateTime={r.at}>
                {fmtTime(r.at)}
              </time>
              <div className="dash-log__body">
                <span className={`dash-mono dash-log__tag${r.tone ? ` is-${r.tone}` : ""}`}>{r.tag}</span>
                <span className="dash-log__text">{r.text}</span>
                {r.sub && <span className="dash-log__sub">{r.sub}</span>}
                {r.alert && <span className="dash-mono dash-log__tag is-alert">{r.alert}</span>}
              </div>
            </li>
          ))}
        </ol>
      )}
      <Link href="/dashboard/gate-log" className="dash-log__more dash-mono">
        OPEN FULL LOG →
      </Link>
    </section>
  );
}

// --- the shuttle ---------------------------------------------------------------------------------

function ShuttleRow({ s, now }: { s: LiveShuttle; now: number }) {
  const h = heading(s.heading);
  return (
    <li className={`dash-gate${s.stale ? " is-stale" : ""}`}>
      <div className="dash-gate__top">
        <span className="dash-gate__name">{s.rider}</span>
        <span className="dash-mono dash-gate__status">
          <Dot tone={s.stale ? "muted" : "guard"} />
          {s.shuttle ? s.shuttle.toUpperCase() : "NO BIKE"}
        </span>
      </div>
      <div className="dash-gate__sub">
        <span>
          {s.at ? (s.stale ? `Last position ${ago(s.at, now)}.` : `Position ${ago(s.at, now)}${h ? `, heading ${h}` : ""}.`) : "No position yet this shift."}{" "}
          {s.ride ? `${RIDE_STATE[s.ride.state].label}: ${s.ride.from} to ${s.ride.to}.` : "No ride right now."}
        </span>
        <Show lng={s.lng} lat={s.lat} what={s.rider} />
      </div>
    </li>
  );
}

function RideRow({ r, now }: { r: RideBrief; now: number }) {
  const due = Date.parse(r.wanted_at) > now;
  return (
    <li className="dash-gate">
      <div className="dash-gate__top">
        <span className="dash-gate__name">
          {r.from} to {r.to}
        </span>
        <span className={`dash-mono dash-gate__status${r.waiting_minutes >= 10 ? " is-warn" : ""}`}>
          <Dot tone="warn" />
          {due ? `DUE ${fmtTime(r.wanted_at)}` : waitLabel(r.waiting_minutes)}
        </span>
      </div>
      <div className="dash-gate__sub">
        <span>{RIDE_KIND[r.kind]}, waiting for a rider.</span>
        <Show lng={r.lng} lat={r.lat} what={`the pickup for ${r.from} to ${r.to}`} />
      </div>
    </li>
  );
}

function ShuttlePanel({ now }: { now: number }) {
  const { live, canSeePositions } = useEstateMap();
  if (!live) return null;
  return (
    <section className="dash-glass dash-status" aria-labelledby="shuttle-title">
      <Kicker aside={<span className="dash-mono">{live.counts.rides_open} OPEN</span>}>
        <span id="shuttle-title">SHUTTLE</span>
      </Kicker>
      {live.shuttles ? (
        live.shuttles.length === 0 ? (
          <p className="dash-small dash-muted">No rider is on shift.</p>
        ) : (
          <ul className="dash-gates">
            {live.shuttles.map((s) => (
              <ShuttleRow key={s.shift_id} s={s} now={now} />
            ))}
          </ul>
        )
      ) : (
        !canSeePositions && <p className="dash-small dash-muted">Where the riders are is shown only to the estate admin, the committee and the security head.</p>
      )}
      <Kicker>WAITING · {live.rides_waiting.length}</Kicker>
      {live.rides_waiting.length === 0 ? (
        <p className="dash-small dash-muted">Nobody is waiting for the shuttle.</p>
      ) : (
        <ul className="dash-gates">
          {live.rides_waiting.map((r) => (
            <RideRow key={r.id} r={r} now={now} />
          ))}
        </ul>
      )}
    </section>
  );
}

function Legend({ shuttle }: { shuttle: boolean }) {
  return (
    <ul className="dash-glass dash-legend dash-mono" aria-label="Map key">
      <li>
        <Dot tone="gate" />
        GATE
      </li>
      <li>
        <Dot tone="warn" />
        GATE OFFLINE
      </li>
      <li>
        <Dot tone="guard" />
        {shuttle ? "GUARD · SHUTTLE" : "GUARD"}
      </li>
      <li>
        <Dot tone="alert" />
        SOS
      </li>
      <li>
        <Dot tone="entry" />
        RECENT ENTRY
      </li>
      {shuttle && (
        <li>
          <span className="dash-dot dash-dot--warn dash-dot--square" aria-hidden="true" />
          PICKUP WAITING
        </li>
      )}
    </ul>
  );
}

export function LivePanels({ estate, shuttle }: { estate: string; shuttle: boolean }) {
  const now = useNow();
  return (
    <div className="dash-live">
      <h1 className="sr-only">Overview: {estate} right now</h1>
      <div className="dash-live__row">
        <StatusPanel now={now} />
        <div className="dash-live__gap" />
        <div className="dash-live__side">
          <LiveLog />
          {shuttle && <ShuttlePanel now={now} />}
        </div>
      </div>
      <Legend shuttle={shuttle} />
    </div>
  );
}
