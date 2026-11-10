import type { Metadata } from "next";
import Link from "next/link";
import { getEstate, getMap, getMe, load } from "@/app/(dashboard)/_lib/api";
import { TZ_OFFSET, hhmm, thisMonthLagos, todayLagos } from "@/app/(dashboard)/_lib/format";
import { persona } from "@/app/(dashboard)/_lib/roles";
import type { Device, Guard, Live, Motorcycle, Resident, Summary, ZoneNode } from "@/app/(dashboard)/_lib/types";
import { ApiError, BigNumber } from "@/app/(dashboard)/_components/ui";
import { ExcoToday, SecurityLive } from "@/app/(dashboard)/_map/LivePanels";
import { MessagingView } from "./messaging/MessagingView";

export const metadata: Metadata = { title: "Today" };

const MONTH = /^\d{4}-(0[1-9]|1[0-2])$/;
const DAY_MS = 86_400_000;

/** Each role's first screen. */
export default async function FirstScreen({ searchParams }: { searchParams: Promise<{ month?: string }> }) {
  const me = await getMe();
  const who = persona(me.role);
  const estateName = me.estate?.name ?? "The estate";

  if (who === "treasurer") {
    const { month: raw } = await searchParams;
    const current = thisMonthLagos();
    return <MessagingView month={raw && MONTH.test(raw) && raw <= current ? raw : current} base="/dashboard" />;
  }
  if (who === "security") {
    const estate = await getEstate();
    const s = estate.ok ? estate.data.settings : null;
    return <SecurityLive estate={estateName} shuttle={!!s?.shuttle_enabled} nightList={s ? hhmm(s.rollup_time) : null} />;
  }
  if (who === "exco") return <ExcoToday estate={estateName} />;
  return <OfficeToday />;
}

// --- the estate office -----------------------------------------------------------------------------

type Todo = { key: string; text: string; href: string; tone?: "warn" | "bad" };

function plural(n: number, one: string, many = `${one}s`) {
  return `${n} ${n === 1 ? one : many}`;
}

function daysAgo(iso: string | null) {
  if (!iso) return null;
  return Math.floor((Date.now() - Date.parse(iso)) / DAY_MS);
}

async function OfficeToday() {
  const since = `${todayLagos()}T00:00:00${TZ_OFFSET}`;
  const [map, estate, live, today, register, residents, guards, devices] = await Promise.all([
    getMap(),
    getEstate(),
    load<Live>("/v1/admin/live"),
    load<Summary>(`/v1/reports/summary?${new URLSearchParams({ since })}`),
    load<ZoneNode[]>("/v1/admin/register"),
    load<Resident[]>("/v1/admin/residents"),
    load<Guard[]>("/v1/admin/guards"),
    load<Device[]>("/v1/admin/devices"),
  ]);
  const shuttle = estate.ok && estate.data.settings.shuttle_enabled;
  const bikes = shuttle ? await load<Motorcycle[]>("/v1/admin/shuttles") : null;

  const todo: Todo[] = [];
  // Most urgent first.
  const disputes = today.ok ? (today.data.trust?.disputes.length ?? 0) : 0;
  if (disputes) todo.push({ key: "no", tone: "bad", text: `${plural(disputes, "home")} said NO to a guest today`, href: "/dashboard/gate-log" });
  const overdue = live.ok ? live.data.counts.overdue : 0;
  if (overdue) todo.push({ key: "late", tone: "warn", text: `${plural(overdue, "guest is", "guests are")} past their time`, href: "/dashboard/gate-log" });

  if (devices.ok) {
    const gateName = new Map((live.ok ? live.data.gates : []).map((g) => [g.id, g.name]));
    for (const d of devices.data.filter((x) => x.status === "paired")) {
      const days = daysAgo(d.last_sync_at);
      if (days == null) todo.push({ key: `dev-${d.id}`, tone: "warn", text: `${d.label} (${gateName.get(d.gate_id) ?? "a gate"}) has never synced`, href: "/dashboard/gate" });
      else if (days >= 1) todo.push({ key: `dev-${d.id}`, tone: "warn", text: `${d.label} (${gateName.get(d.gate_id) ?? "a gate"}) has not synced for ${plural(days, "day")}`, href: "/dashboard/gate" });
    }
  }

  if (register.ok && residents.ok) {
    const withNumber = new Set(residents.data.filter((r) => r.numbers.some((n) => !n.pending)).map((r) => r.home_id));
    const homes = register.data.flatMap((z) => z.streets.flatMap((st) => st.homes));
    const none = homes.filter((h) => !withNumber.has(h.id)).length;
    if (none) todo.push({ key: "nonum", text: `${plural(none, "home has", "homes have")} no phone number`, href: "/dashboard/register?show=no-number" });
  }

  if (guards.ok) {
    const missing = guards.data.filter((g) => g.active && !g.consent_at);
    if (missing.length > 0 && missing.length <= 3)
      for (const g of missing) todo.push({ key: `consent-${g.id}`, text: `${g.name} has no consent form recorded`, href: "/dashboard/gate" });
    else if (missing.length > 3) todo.push({ key: "consent", text: `${missing.length} guards have no consent form recorded`, href: "/dashboard/gate" });
  }

  if (map.ok) {
    if (!map.data.bbox) todo.push({ key: "map", text: "Draw the estate on the map", href: "/dashboard/settings/map" });
    else {
      const unpinned = map.data.gates.filter((g) => g.lat == null);
      if (unpinned.length === 1) todo.push({ key: "pins", text: `Put ${unpinned[0].name} on the map`, href: "/dashboard/settings/map" });
      else if (unpinned.length > 1) todo.push({ key: "pins", text: `Put ${unpinned.length} gates on the map`, href: "/dashboard/settings/map" });
    }
  }

  if (today.ok) {
    const d = today.data.directory;
    if (d.reported_not_working)
      todo.push({ key: "dir-bad", tone: "warn", text: `${plural(d.reported_not_working, "emergency number was", "emergency numbers were")} reported not working`, href: "/dashboard/emergency-numbers" });
    if (d.overdue_verification) todo.push({ key: "dir-due", text: `${plural(d.overdue_verification, "emergency number is", "emergency numbers are")} due a test call`, href: "/dashboard/emergency-numbers" });
  }

  if (bikes?.ok && bikes.data.filter((b) => b.active).length === 0) todo.push({ key: "bikes", text: "Add the shuttle's motorcycles", href: "/dashboard/gate#shuttle" });

  return (
    <>
      <header className="dash-head">
        <div>
          <h1 className="dash-h1">Today</h1>
          <p className="dash-lede">{todayLabel()}</p>
        </div>
      </header>

      <div className="dash-bigs">
        <BigNumber value={live.ok ? live.data.counts.inside : "..."} label="Guests inside now" />
        <BigNumber value={today.ok ? today.data.entries.total : "..."} label="Entries today" href="/dashboard/gate-log" />
        <BigNumber value={todo.length} label={todo.length === 1 ? "Thing to do" : "Things to do"} tone={todo.length ? "warn" : undefined} />
      </div>

      {!live.ok && <ApiError error={live.error} />}

      <h2 className="dash-h2 dash-mt">To do</h2>
      {todo.length === 0 ? (
        <p className="dash-done">Nothing to do. Everything is set up and working.</p>
      ) : (
        <ul className="dash-todo">
          {todo.map((t) => (
            <li key={t.key}>
              <Link href={t.href} className={`dash-todo__item${t.tone ? ` is-${t.tone}` : ""}`}>
                <span>{t.text}</span>
                <span className="dash-todo__go" aria-hidden="true">
                  →
                </span>
              </Link>
            </li>
          ))}
        </ul>
      )}

      <p className="dash-alsolinks">
        Also: <Link href="/dashboard/gate-log">Gate log</Link> · <Link href="/dashboard/reports">Monthly report</Link> ·{" "}
        <Link href="/dashboard/messaging">Messages</Link>
        {shuttle && (
          <>
            {" "}
            · <Link href="/dashboard/shuttle">Shuttle rides</Link>
          </>
        )}
      </p>
    </>
  );
}

function todayLabel() {
  return new Intl.DateTimeFormat("en-GB", { timeZone: "Africa/Lagos", weekday: "long", day: "numeric", month: "long" }).format(new Date());
}
