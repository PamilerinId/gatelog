"use client";

import Link from "next/link";
import { useEffect, useState, type ReactNode } from "react";
import { fmtTime, pct } from "@/app/(dashboard)/_lib/format";
import type { GateEntry, Live, LiveGate } from "@/app/(dashboard)/_lib/types";
import { useEstateMap } from "./context";
import { minutesSince, trustOf, waitLabel } from "./util";

// The first screens that sit on the live map: the security head's Live screen and the Exco's
// Today screen. Plain sentences and cards, few buttons. Everything the map markers show is also
// said here in words, and tapping a card moves the map to it.

/** Re-renders every 15 seconds so "4 min" stays true between polls. */
function useNow(ms = 15_000) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), ms);
    return () => clearInterval(t);
  }, [ms]);
  return now;
}

function Dot({ tone }: { tone: "gate" | "warn" | "guard" | "alert" | "entry" | "muted" }) {
  return <span className={`dash-dot dash-dot--${tone}`} aria-hidden="true" />;
}

function Status({ live, error }: { live: Live | null; error: string | null }) {
  return (
    <p className="dash-livestate" aria-live="polite">
      {error ? <span className="dash-warn-text">{error}</span> : live ? "Live. Updates every 10 seconds." : "Loading..."}
    </p>
  );
}

function firstName(full: string) {
  return full.trim().split(/\s+/)[0];
}

// --- gate cards ------------------------------------------------------------------------------------

function gateCounts(log: GateEntry[] | null | undefined, gate: string) {
  const mine = (log ?? []).filter((e) => e.gate === gate && e.method !== "refused");
  return { inToday: mine.length, stillIn: mine.filter((e) => !e.exit_at).length };
}

export function GateCard({ g, log, now }: { g: LiveGate; log: GateEntry[] | null | undefined; now: number }) {
  const { flyTo } = useEstateMap();
  const off = g.phones > 0 && g.quiet;
  const status =
    g.phones === 0 ? "no phone" : off ? (g.phone_last_sync_at ? `offline ${minutesSince(g.phone_last_sync_at, now).toLowerCase()}` : "never synced") : "online";
  const c = gateCounts(log, g.name);
  const duty = g.on_duty.length
    ? g.on_duty.map((d) => `${firstName(d.guard)} on duty since ${fmtTime(d.since)}`).join(", ")
    : "Nobody on duty";
  const body = (
    <>
      <span className="dash-gatecard__top">
        <span className="dash-gatecard__name">{g.name}</span>
        <span className={`dash-gatecard__state dash-mono${off || g.phones === 0 ? " is-warn" : ""}`}>
          <Dot tone={off || g.phones === 0 ? "warn" : "gate"} />
          {status}
        </span>
      </span>
      <span className="dash-gatecard__line">{duty}</span>
      <span className="dash-gatecard__line dash-mono">
        {c.inToday} in today · {c.stillIn} still inside
      </span>
    </>
  );
  if (g.lat == null || g.lng == null) return <div className="dash-gatecard">{body}</div>;
  return (
    <button type="button" className="dash-gatecard" onClick={() => flyTo(g.lng!, g.lat!)} aria-label={`${g.name}: ${status}. ${duty}. Show on the map.`}>
      {body}
    </button>
  );
}

function RiderCard({ s, now }: { s: NonNullable<Live["shuttles"]>[number]; now: number }) {
  const { flyTo } = useEstateMap();
  const where = s.at ? (s.stale ? `last seen ${minutesSince(s.at, now).toLowerCase()} ago` : "moving now") : "no position yet";
  const body = (
    <>
      <span className="dash-gatecard__top">
        <span className="dash-gatecard__name">{s.rider}</span>
        <span className="dash-gatecard__state dash-mono">
          <Dot tone={s.stale ? "muted" : "guard"} />
          {s.shuttle ?? "shuttle"}
        </span>
      </span>
      <span className="dash-gatecard__line">{where}</span>
      <span className="dash-gatecard__line">{s.ride ? `Taking: ${s.ride.from} to ${s.ride.to}` : "No ride right now"}</span>
    </>
  );
  if (s.lat == null || s.lng == null) return <div className={`dash-gatecard${s.stale ? " is-stale" : ""}`}>{body}</div>;
  return (
    <button type="button" className={`dash-gatecard${s.stale ? " is-stale" : ""}`} onClick={() => flyTo(s.lng!, s.lat!)} aria-label={`${s.rider}, ${where}. Show on the map.`}>
      {body}
    </button>
  );
}

function GateCards({ live, now }: { live: Live; now: number }) {
  return (
    <section className="dash-gatecards" aria-label="Gates and riders">
      {live.gates.map((g) => (
        <GateCard key={g.id} g={g} log={live.log} now={now} />
      ))}
      {(live.shuttles ?? []).map((s) => (
        <RiderCard key={s.shift_id} s={s} now={now} />
      ))}
    </section>
  );
}

// --- needs you (security head) ----------------------------------------------------------------------

type Need = { key: string; tone?: "bad" | "warn"; text: ReactNode; href?: string; at?: [number, number] };

function needs(live: Live, now: number, nightList: string | null): Need[] {
  const out: Need[] = [];
  const log = live.log ?? [];
  for (const e of log.filter((x) => x.disputed_at)) {
    out.push({
      key: `no-${e.id}`,
      tone: "bad",
      text: (
        <>
          <strong>{e.address ?? "A home"} said NO</strong> to {e.guest_name === "Voice clip" ? "a visitor" : e.guest_name}, let in at {fmtTime(e.at)}
          {e.gate ? ` at ${e.gate}` : ""}.
        </>
      ),
      href: "/dashboard/gate-log",
    });
  }
  const overdue = (live.inside ?? []).filter((v) => v.expected_until && Date.parse(v.expected_until) < now);
  for (const v of overdue.slice(0, 5)) {
    out.push({
      key: `late-${v.id}`,
      tone: "warn",
      text: (
        <>
          <strong>{v.guest_name}</strong> is still at {v.address}, due out at {fmtTime(v.expected_until)}.
        </>
      ),
      href: "/dashboard/gate-log",
    });
  }
  if (overdue.length > 5) out.push({ key: "late-more", tone: "warn", text: `${overdue.length - 5} more guests are past their time.`, href: "/dashboard/gate-log" });
  if (overdue.length === 0 && live.counts.overdue > 0)
    out.push({ key: "late-count", tone: "warn", text: `${live.counts.overdue} guests are past their time.`, href: "/dashboard/gate-log" });

  const walkIns = log.filter((e) => e.method === "walk_in_admitted");
  const alone = walkIns.filter((e) => e.decided_alone).length;
  if (walkIns.length)
    out.push({
      key: "walkins",
      tone: alone ? "warn" : undefined,
      text: `${walkIns.length} ${walkIns.length === 1 ? "walk-in" : "walk-ins"} let in today${alone ? `, ${alone} decided alone at the gate` : ""}.`,
      href: "/dashboard/gate-log?tab=walkins",
    });
  if (live.counts.inside > 0)
    out.push({
      key: "night",
      text: `Tonight's list${nightList ? ` at ${nightList}` : ""}: ${live.counts.inside} ${live.counts.inside === 1 ? "guest" : "guests"} still inside now.`,
      href: "/dashboard/gate-log",
    });
  for (const r of live.rides_waiting) {
    out.push({
      key: `ride-${r.id}`,
      tone: r.waiting_minutes >= 10 ? "warn" : undefined,
      text: `Shuttle: ${r.from} to ${r.to}, ${Date.parse(r.wanted_at) > now ? `due at ${fmtTime(r.wanted_at)}` : `waiting ${waitLabel(r.waiting_minutes).toLowerCase()}`}.`,
      at: r.lat != null && r.lng != null ? [r.lng, r.lat] : undefined,
      href: r.lat == null ? "/dashboard/shuttle" : undefined,
    });
  }
  return out;
}

function NeedsYou({ live, now, nightList, shuttle }: { live: Live; now: number; nightList: string | null; shuttle: boolean }) {
  const { flyTo, liveError } = useEstateMap();
  const list = needs(live, now, nightList);
  return (
    <section className="dash-glass dash-needs" aria-labelledby="needs-title">
      <h2 className="dash-needs__title" id="needs-title">
        Needs you
      </h2>
      <Status live={live} error={liveError} />
      {list.length === 0 ? (
        <p className="dash-needs__none">Nothing needs you right now.</p>
      ) : (
        <ol className="dash-needs__list">
          {list.map((n) => (
            <li key={n.key} className={`dash-need${n.tone ? ` is-${n.tone}` : ""}`}>
              {n.href ? (
                <Link href={n.href} className="dash-need__link">
                  {n.text}
                </Link>
              ) : n.at ? (
                <button type="button" className="dash-need__link" onClick={() => flyTo(n.at![0], n.at![1])}>
                  {n.text}
                </button>
              ) : (
                <span className="dash-need__link">{n.text}</span>
              )}
            </li>
          ))}
        </ol>
      )}
      <p className="dash-alsolinks">
        Also: <Link href="/dashboard/emergency-numbers">Emergency numbers</Link>
        {shuttle && (
          <>
            {" "}
            · <Link href="/dashboard/shuttle">Shuttle rides</Link>
          </>
        )}
      </p>
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
    </ul>
  );
}

export function SecurityLive({ estate, shuttle, nightList }: { estate: string; shuttle: boolean; nightList: string | null }) {
  const { live, liveError } = useEstateMap();
  const now = useNow();
  return (
    <div className="dash-live">
      <h1 className="sr-only">Live: {estate} right now</h1>
      {!live && <Status live={live} error={liveError} />}
      <div className="dash-live__row">
        {live ? <NeedsYou live={live} now={now} nightList={nightList} shuttle={shuttle} /> : <div />}
        <div className="dash-live__gap" />
        {live && <GateCards live={live} now={now} />}
      </div>
      <Legend shuttle={shuttle} />
    </div>
  );
}

// --- Exco today ---------------------------------------------------------------------------------------

function TrustBar({ live }: { live: Live }) {
  const split = live.today?.trust?.phone_entries;
  const c = split
    ? { verified: split.verified ?? 0, pin: split.pin_verified ?? 0, unverified: split.unverified ?? 0 }
    : (live.log ?? []).reduce(
        (acc, e) => {
          const t = e.method === "code" ? null : trustOf(e);
          if (t) acc[t] += 1;
          return acc;
        },
        { verified: 0, pin: 0, unverified: 0 },
      );
  const total = c.verified + c.pin + c.unverified;
  return (
    <div className="dash-trust">
      <p className="dash-kicker">PHONE ENTRIES BY TRUST</p>
      <div className="dash-trust__bar" role="img" aria-label={`Verified ${c.verified}, PIN ${c.pin}, unverified ${c.unverified}`}>
        {total === 0 ? (
          <span className="dash-trust__empty" />
        ) : (
          <>
            <span className="dash-trust__v" style={{ flexGrow: c.verified }} />
            <span className="dash-trust__p" style={{ flexGrow: c.pin }} />
            <span className="dash-trust__u" style={{ flexGrow: c.unverified }} />
          </>
        )}
      </div>
      <div className="dash-trust__legend dash-mono">
        <span>VERIFIED {c.verified}</span>
        <span>PIN {c.pin}</span>
        <span className="dash-warn-text">UNVERIFIED {c.unverified}</span>
      </div>
    </div>
  );
}

export function ExcoToday({ estate }: { estate: string }) {
  const { live, liveError } = useEstateMap();
  const now = useNow();
  const rate = live?.today?.exits.capture_rate;
  return (
    <div className="dash-live">
      <h1 className="sr-only">Today at {estate}</h1>
      <div className="dash-live__row">
        <section className="dash-glass dash-status" aria-label="Today in numbers">
          <Status live={live} error={liveError} />
          <dl className="dash-figs">
            <div>
              <dd className="dash-mono">{live?.today?.entries.total ?? "..."}</dd>
              <dt>Entries today</dt>
            </div>
            <div>
              <dd className="dash-mono">{live?.counts.inside ?? "..."}</dd>
              <dt>Inside now</dt>
            </div>
            <div>
              <dd className="dash-mono">{live ? (rate == null ? "None yet" : pct(rate)) : "..."}</dd>
              <dt>Exits confirmed</dt>
            </div>
            <div>
              <dd className={`dash-mono${live && live.counts.overdue > 0 ? " dash-warn-text" : ""}`}>{live?.counts.overdue ?? "..."}</dd>
              <dt>Past their time</dt>
            </div>
          </dl>
          {live && <TrustBar live={live} />}
          <Link href="/dashboard/emergency-numbers" className="dash-quiet-link">
            Emergency numbers
          </Link>
        </section>
        <div className="dash-live__gap" />
        {live && <GateCards live={live} now={now} />}
      </div>
      <Legend shuttle={false} />
    </div>
  );
}
