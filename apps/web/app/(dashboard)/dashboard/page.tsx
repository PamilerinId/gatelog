import type { Metadata } from "next";
import Link from "next/link";
import { getEstate, getMap, getMe, load } from "@/app/(dashboard)/_lib/api";
import { fmtDate, pct } from "@/app/(dashboard)/_lib/format";
import type { Summary } from "@/app/(dashboard)/_lib/types";
import { ApiError, PageHead } from "@/app/(dashboard)/_components/ui";
import { LivePanels } from "@/app/(dashboard)/_map/LivePanels";

export const metadata: Metadata = { title: "Overview" };

export default async function OverviewPage() {
  const [me, r, map, estate] = await Promise.all([getMe(), load<Summary>("/v1/reports/summary"), getMap(), getEstate()]);
  const hasMap = map.ok && map.data.bbox != null;
  const shuttle = estate.ok && estate.data.settings.shuttle_enabled;

  // With a boundary drawn, the overview is the live map; the last 30 days follow below it.
  if (hasMap)
    return (
      <>
        <LivePanels estate={me.estate?.name ?? "The estate"} shuttle={shuttle} />
        <section className="dash-live__after" aria-labelledby="last-30">
          <h2 className="dash-h2 dash-live__after-title" id="last-30">
            The last 30 days
          </h2>
          {r.ok ? <Summary30 s={r.data} /> : <ApiError error={r.error} />}
        </section>
      </>
    );

  if (!r.ok)
    return (
      <>
        <PageHead title="Overview" />
        <MapPrompt admin={me.role === "admin"} />
        <ApiError error={r.error} />
      </>
    );

  return (
    <>
      <PageHead title="Overview">
        {me.estate?.name}: the last 30 days at the gate, {fmtDate(r.data.since)} to {fmtDate(r.data.until)}.
      </PageHead>
      <MapPrompt admin={me.role === "admin"} />
      <Summary30 s={r.data} />
    </>
  );
}

function MapPrompt({ admin }: { admin: boolean }) {
  if (!admin) return null;
  return (
    <div className="dash-msg dash-msg--warn dash-prompt">
      <p>
        <strong>Draw the estate boundary to turn on the live map.</strong> The overview then shows the estate as it is right now: who is on
        duty at each gate, whose phone has gone quiet, and the shuttle if the estate runs one.
      </p>
      <Link href="/dashboard/settings/map" className="dash-btn dash-btn--primary dash-btn--sm">
        Draw the boundary
      </Link>
    </div>
  );
}

function Summary30({ s }: { s: Summary }) {
  const phoneOver = s.phone_share != null && s.phone_share > 0.4;
  const captureUnder = s.exits.capture_rate != null && s.exits.capture_rate < 0.7;
  const phoneCount = s.entries.by_method.phone_announced + s.entries.by_method.callback_confirmed;

  return (
    <>
      <div className="dash-stats">
        <Stat label="Entries" value={String(s.entries.total)} href="/dashboard/gate-log">
          {s.entries.admitted} let in, {s.entries.by_method.refused} refused.
          {(s.entries.by_method.walk_in_admitted ?? 0) > 0 && ` ${s.entries.by_method.walk_in_admitted} of those let in were walk-ins decided at the gate.`}
        </Stat>

        <Stat label="Entries by phone" value={pct(s.phone_share)} tone={s.phone_share == null ? undefined : phoneOver ? "warn" : "ok"}>
          {phoneCount} of {s.entries.admitted} admitted guests were phoned through instead of using a code.
          <span className="dash-stat__rule">Codes are not being adopted if this is over 40% by phone after 8 weeks.</span>
        </Stat>

        <Stat label="Exit capture rate" value={pct(s.exits.capture_rate)} tone={s.exits.capture_rate == null ? undefined : captureUnder ? "warn" : "ok"}>
          {s.exits.gate_confirmed} of {s.exits.measurable_entries} guests had their exit confirmed at the gate.
          <span className="dash-stat__rule">Exit capture should be at least 70%.</span>
        </Stat>

        <Stat label="Missed exits" value={String(s.exits.missed)} tone={s.exits.missed > 0 ? "warn" : undefined} href="/dashboard/reports">
          Guests still on the night list at morning handover. {s.exits.unmatched_exits} exits had no matching entry.
        </Stat>

        <Stat
          label="Emergency numbers"
          value={String(s.directory.numbers)}
          tone={s.directory.overdue_verification + s.directory.reported_not_working > 0 ? "warn" : undefined}
          href="/dashboard/emergency-numbers"
        >
          {s.directory.overdue_verification} due for a test call, {s.directory.reported_not_working} reported not working.
        </Stat>
      </div>

      <p className="dash-muted dash-small">
        {fmtDate(s.since)} to {fmtDate(s.until)}. Entries are counted when the gate phone syncs. A guest still inside within their expected time
        is not counted as a missed exit yet.{" "}
        <Link href="/dashboard/reports">See the full reports</Link>.
      </p>
    </>
  );
}

function Stat({
  label,
  value,
  tone,
  href,
  children,
}: {
  label: string;
  value: string;
  tone?: "ok" | "warn";
  href?: string;
  children: React.ReactNode;
}) {
  return (
    <div className={`dash-stat${tone ? ` dash-stat--${tone}` : ""}`}>
      <p className="dash-stat__label">{href ? <Link href={href}>{label}</Link> : label}</p>
      <p className="dash-stat__value tnum">{value}</p>
      <p className="dash-stat__note">{children}</p>
    </div>
  );
}
