import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getMe, load } from "@/app/(dashboard)/_lib/api";
import { RIDE_CONFIRM, RIDE_EVENT, RIDE_KIND, RIDE_SOURCE, RIDE_STATE, fmtDateTime } from "@/app/(dashboard)/_lib/format";
import { canOpen } from "@/app/(dashboard)/_lib/roles";
import type { RideDetail } from "@/app/(dashboard)/_lib/types";
import { ApiError, Badge, NotForRole, PageHead, Section } from "@/app/(dashboard)/_components/ui";

export const metadata: Metadata = { title: "Ride" };

export default async function RidePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();
  const me = await getMe();
  if (!canOpen(me.role, "shuttle")) return <NotForRole title="Ride" />;
  const r = await load<RideDetail>(`/v1/admin/rides/${id}`);
  if (!r.ok && r.status === 404) notFound();

  return (
    <>
      <p className="dash-crumbs">
        <Link href="/dashboard/shuttle">Shuttle</Link> <span aria-hidden="true">/</span> Ride
      </p>
      {!r.ok ? (
        <>
          <PageHead title="Ride" />
          <ApiError error={r.error} />
        </>
      ) : (
        <RideView ride={r.data} />
      )}
    </>
  );
}

function RideView({ ride }: { ride: RideDetail }) {
  const s = RIDE_STATE[ride.state];
  const rows: [string, React.ReactNode][] = [
    ["Kind", `${RIDE_KIND[ride.kind]}${ride.passenger ? `: ${ride.passenger}` : ""}`],
    ["For the home", ride.address ?? "Unknown"],
    ["Booked", `${RIDE_SOURCE[ride.source]}${ride.booked_by ? `, by ${ride.booked_by}` : ""}, ${fmtDateTime(ride.created_at)}`],
    ["Wanted", fmtDateTime(ride.wanted_at)],
    ["Rider", ride.rider ? `${ride.rider}${ride.shuttle ? ` on ${ride.shuttle}` : ""}` : "Nobody took it"],
    ["Taken", ride.accepted_at ? fmtDateTime(ride.accepted_at) : "Not taken"],
    ["Picked up", ride.picked_up_at ? fmtDateTime(ride.picked_up_at) : "Not picked up"],
    ["Dropped off", ride.done_at ? fmtDateTime(ride.done_at) : "Not dropped off"],
    ["Who rode", ride.confirmed_by ? `${RIDE_CONFIRM[ride.confirmed_by]}${ride.confirmed_resident ? `: ${ride.confirmed_resident}` : ""}` : "Not recorded"],
  ];
  if (ride.closed_at && ride.state !== "done") rows.push(["Closed", fmtDateTime(ride.closed_at)]);

  return (
    <>
      <PageHead title={`${ride.from} to ${ride.to}`}>
        <Badge tone={s.tone}>{s.label}</Badge>
      </PageHead>
      <div className="dash-table-wrap">
        <table className="dash-table dash-table--kv">
          <tbody>
            {rows.map(([k, v]) => (
              <tr key={k}>
                <th scope="row">{k}</th>
                <td className={k === "Kind" || k === "For the home" || k === "Rider" || k === "Who rode" ? undefined : "tnum"}>{v}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <Section title="What happened" id="events">
        <p className="dash-muted dash-small">
          Every tap from the rider phones, in order. When two riders tap &ldquo;take it&rdquo; at once, the first gets the ride and the other tap
          is kept here as not applied.
        </p>
        {ride.events.length === 0 ? (
          <p className="dash-muted dash-small">Nothing yet: no rider has taken this ride.</p>
        ) : (
          <div className="dash-table-wrap">
            <table className="dash-table dash-table--stack">
              <thead>
                <tr>
                  <th scope="col">When</th>
                  <th scope="col">What</th>
                  <th scope="col">Who</th>
                  <th scope="col">Result</th>
                </tr>
              </thead>
              <tbody>
                {ride.events.map((e, i) => (
                  <tr key={`${e.at}-${i}`} className={e.applied ? undefined : "dash-row--bad"}>
                    <td data-label="When" className="tnum dash-nowrap">
                      {fmtDateTime(e.at)}
                    </td>
                    <td data-label="What">{RIDE_EVENT[e.event]}</td>
                    <td data-label="Who">{e.by ?? <span className="dash-muted">Unknown</span>}</td>
                    <td data-label="Result">
                      {e.applied ? (
                        <Badge tone="ok">Applied</Badge>
                      ) : (
                        <Badge tone="warn">{e.event === "accept" ? "Lost: already taken" : "Not applied"}</Badge>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Section>
    </>
  );
}
