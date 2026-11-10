import { getEstate, getMap, getMe, load } from "@/app/(dashboard)/_lib/api";
import { ROLE } from "@/app/(dashboard)/_lib/format";
import { nav, persona, seesPositions } from "@/app/(dashboard)/_lib/roles";
import type { ZoneNode } from "@/app/(dashboard)/_lib/types";
import { HeaderStrip } from "@/app/(dashboard)/_map/HeaderStrip";
import { MapShell } from "@/app/(dashboard)/_map/MapShell";
import { signOut } from "./actions";

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const me = await getMe();

  if (me.role === "ops" || !me.estate) {
    const association = me.role === "org_admin" || me.role === "org_viewer";
    return (
      <main id="main" className="dash-center">
        <div className="dash-card dash-narrow">
          <h1 className="dash-h1">{association ? "Choose an estate" : "This dashboard is for estate staff"}</h1>
          <p className="dash-muted">
            {association
              ? "Your association's estates will be listed here to choose from. Ask Gatelog to finish setting up your association's access."
              : "Your account is not linked to an estate."}
          </p>
          <form action={signOut}>
            <button className="dash-btn dash-btn--primary">Sign out</button>
          </form>
        </div>
      </main>
    );
  }

  // The map behind every page, and the counts in the header strip.
  const [map, estate, register] = await Promise.all([getMap(), getEstate(), load<ZoneNode[]>("/v1/admin/register")]);
  const homes = register.ok ? register.data.reduce((n, z) => n + z.streets.reduce((m, st) => m + st.homes.length, 0), 0) : null;
  const place = estate.ok ? [estate.data.lga, estate.data.state].filter(Boolean).join(", ") : "";
  const who = persona(me.role);

  return (
    <MapShell
      data={map.ok ? map.data : null}
      initialTheme={map.ok && map.data.sun?.is_night ? "night" : "day"}
      canSeePositions={seesPositions(me.role)}
      admin={me.role === "admin"}
      liveHome={who === "security" || who === "exco"}
    >
      <div className="dash-shell">
        <HeaderStrip
          estate={me.estate.name}
          place={place}
          gates={map.ok ? map.data.gates.length : 0}
          homes={homes}
          items={nav(me.role)}
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
          {children}
        </main>
      </div>
    </MapShell>
  );
}
