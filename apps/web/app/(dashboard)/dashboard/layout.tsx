import { getEstate, getMap, getMe, load } from "@/app/(dashboard)/_lib/api";
import { POSITION_ROLES, ROLE } from "@/app/(dashboard)/_lib/format";
import type { ZoneNode } from "@/app/(dashboard)/_lib/types";
import type { NavItem } from "@/app/(dashboard)/_components/Nav";
import { HeaderStrip } from "@/app/(dashboard)/_map/HeaderStrip";
import { MapShell } from "@/app/(dashboard)/_map/MapShell";
import { signOut } from "./actions";

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const me = await getMe();
  const admin = me.role === "admin";

  if (me.role === "ops" || !me.estate) {
    return (
      <main id="main" className="dash-center">
        <div className="dash-card dash-narrow">
          <h1 className="dash-h1">This dashboard is for estate staff</h1>
          <p className="dash-muted">Your account is not linked to an estate.</p>
          <form action={signOut}>
            <button className="dash-btn dash-btn--primary">Sign out</button>
          </form>
        </div>
      </main>
    );
  }

  // The map behind every page, whether the estate runs a shuttle (for the nav), and the counts
  // in the header strip.
  const [map, estate, register] = await Promise.all([getMap(), getEstate(), load<ZoneNode[]>("/v1/admin/register")]);
  const shuttle = estate.ok && estate.data.settings.shuttle_enabled;
  const homes = register.ok ? register.data.reduce((n, z) => n + z.streets.reduce((m, st) => m + st.homes.length, 0), 0) : null;
  const place = estate.ok ? [estate.data.lga, estate.data.state].filter(Boolean).join(", ") : "";

  // The treasurer looks after the money side: what was sent and what it will cost.
  const treasurer = me.role === "treasurer";
  const items: NavItem[] = treasurer
    ? [
        { href: "/dashboard", label: "Overview" },
        { href: "/dashboard/messaging", label: "Messaging usage" },
        { href: "/dashboard/reports", label: "Reports" },
      ]
    : [
        { href: "/dashboard", label: "Overview" },
        { href: "/dashboard/register", label: "Register" },
        ...(admin ? [{ href: "/dashboard/import", label: "Import" }] : []),
        { href: "/dashboard/gate", label: "Guards and gate phones" },
        { href: "/dashboard/emergency-numbers", label: "Emergency numbers" },
        { href: "/dashboard/gate-log", label: "Gate log" },
        ...(shuttle ? [{ href: "/dashboard/shuttle", label: "Shuttle" }] : []),
        { href: "/dashboard/reports", label: "Reports" },
        { href: "/dashboard/messaging", label: "Messaging usage" },
        ...(admin ? [{ href: "/dashboard/settings", label: "Staff and settings" }] : []),
      ];

  return (
    <MapShell
      data={map.ok ? map.data : null}
      initialTheme={map.ok && map.data.sun?.is_night ? "night" : "day"}
      canSeePositions={POSITION_ROLES.includes(me.role)}
      admin={admin}
    >
      <div className="dash-shell">
        <HeaderStrip
          estate={me.estate.name}
          place={place}
          gates={map.ok ? map.data.gates.length : 0}
          homes={homes}
          items={items}
          user={
            <>
              <span className="dash-strip__who">
                {me.name} · {ROLE[me.role]}
              </span>
              <form action={signOut}>
                <button className="dash-chip-btn">SIGN OUT</button>
              </form>
            </>
          }
        />
        <main id="main" className="dash-main">
          {!admin && (
            <p className="dash-banner" role="note">
              {treasurer
                ? "You can view the overview, messaging usage and reports. Only an estate admin can make changes."
                : "You can view everything here. Only an estate admin can make changes."}
            </p>
          )}
          {children}
        </main>
      </div>
    </MapShell>
  );
}
