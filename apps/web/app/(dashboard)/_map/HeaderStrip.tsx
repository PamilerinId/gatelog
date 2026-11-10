"use client";

import Link from "next/link";
import { useEffect, useState, type ReactNode } from "react";
import { TZ, fmtTime } from "@/app/(dashboard)/_lib/format";
import { Nav, type NavItem } from "@/app/(dashboard)/_components/Nav";
import { useEstateMap } from "./context";
import { fmtLat, fmtLng } from "./geo";
import { nextSwitch } from "./theme";

const clockFmt = new Intl.DateTimeFormat("en-GB", { timeZone: TZ, hour: "2-digit", minute: "2-digit" });

/** "16:42 WAT", kept to the minute. Rendered in the browser only, so it never disagrees with the server. */
function Clock() {
  const [now, setNow] = useState<string>("");
  useEffect(() => {
    const tick = () => setNow(`${clockFmt.format(new Date())} WAT`);
    tick();
    const t = setInterval(tick, 15_000);
    return () => clearInterval(t);
  }, []);
  return (
    <span className="dash-strip__clock tnum" suppressHydrationWarning>
      {now}
    </span>
  );
}

/** Day and night. Auto follows sunrise and sunset at the estate; the button overrides it on
 * this device (kept in localStorage) until "Auto" is chosen again. */
function ModeToggle() {
  const { pref, setPref, theme, data, live } = useEstateMap();
  const sun = live?.sun ?? data?.sun ?? null;
  const [next, setNext] = useState<number | null>(null);
  useEffect(() => setNext(nextSwitch(sun, Date.now())), [sun, theme]);

  const night = theme === "night";
  const note = sun && next ? `AUTO · ${night ? "SUNRISE" : "SUNSET"} ${fmtTime(new Date(next).toISOString())}` : "AUTO";
  return (
    <span className="dash-strip__mode">
      {pref === "auto" ? (
        <span className="dash-strip__note" aria-live="polite">
          {note}
        </span>
      ) : (
        <button type="button" className="dash-chip-btn" onClick={() => setPref("auto")}>
          BACK TO AUTO
        </button>
      )}
      <button
        type="button"
        className="dash-mode"
        aria-label={night ? "Night map. Switch to the day map" : "Day map. Switch to the night map"}
        onClick={() => setPref(night ? "day" : "night")}
      >
        <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true">
          <circle cx="7" cy="7" r="5.5" fill="none" stroke="currentColor" strokeWidth="1.3" />
          <path d="M7 1.5 A5.5 5.5 0 0 1 7 12.5 Z" fill="currentColor" />
        </svg>
        {night ? "NIGHT" : "DAY"}
      </button>
    </span>
  );
}

export function HeaderStrip({
  estate,
  place,
  gates,
  homes,
  items,
  user,
}: {
  estate: string;
  place: string;
  gates: number;
  homes: number | null;
  items: NavItem[];
  user: ReactNode;
}) {
  const { data } = useEstateMap();
  const c = data?.center;
  const meta = [c ? `${fmtLat(c.lat)} ${fmtLng(c.lng)}` : null, `${gates} ${gates === 1 ? "GATE" : "GATES"}`, homes != null ? `${homes} HOMES` : null]
    .filter(Boolean)
    .join(" · ");
  return (
    <header className="dash-strip dash-glass">
      <div className="dash-strip__row">
        <Link href="/dashboard" className="dash-strip__brand">
          <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true">
            <circle cx="7" cy="7" r="6" fill="none" stroke="currentColor" strokeWidth="1.4" />
            <circle cx="7" cy="7" r="2.2" fill="currentColor" />
          </svg>
          <span className="dash-strip__name">GATELOG</span>
          <span className="dash-strip__estate">
            / {estate.toUpperCase()}
            {place ? ` · ${place.toUpperCase()}` : ""}
          </span>
        </Link>
        <span className="dash-strip__meta">{meta}</span>
        <span className="dash-strip__right">
          <Clock />
          <ModeToggle />
        </span>
      </div>
      <Nav items={items} footer={<div className="dash-strip__user">{user}</div>} />
    </header>
  );
}
