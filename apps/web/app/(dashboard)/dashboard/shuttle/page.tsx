import type { Metadata } from "next";
import Form from "next/form";
import Link from "next/link";
import { getEstate, getMe, load } from "@/app/(dashboard)/_lib/api";
import {
  RIDE_CONFIRM,
  RIDE_KIND,
  RIDE_SOURCE,
  RIDE_STATE,
  TZ_OFFSET,
  addDays,
  addMonths,
  fmtDateTime,
  fmtMonth,
  thisMonthLagos,
  todayLagos,
} from "@/app/(dashboard)/_lib/format";
import type { Guard, Motorcycle, Ride, RideKind, RideState, ShuttleReport, ZoneNode } from "@/app/(dashboard)/_lib/types";
import { ActionForm } from "@/app/(dashboard)/_components/ActionForm";
import { ConfirmButton } from "@/app/(dashboard)/_components/ConfirmButton";
import { ApiError, Badge, Empty, NotForRole, PageHead, Section } from "@/app/(dashboard)/_components/ui";
import { canOpen } from "@/app/(dashboard)/_lib/roles";
import { createMotorcycle, setMotorcycleActive, updateMotorcycle } from "../actions";

export const metadata: Metadata = { title: "Shuttle" };

type Tab = "rides" | "bikes" | "report";
type Search = { tab?: string; from?: string; to?: string; state?: string; home?: string; rider?: string; month?: string };

const DAY = /^\d{4}-\d{2}-\d{2}$/;
const MONTH = /^\d{4}-\d{2}$/;
const UUID_RE = /^[0-9a-f-]{36}$/i;
const LIMIT = 500;

export default async function ShuttlePage({ searchParams }: { searchParams: Promise<Search> }) {
  const sp = await searchParams;
  const tab: Tab = sp.tab === "bikes" ? "bikes" : sp.tab === "report" ? "report" : "rides";
  const [me, estate] = await Promise.all([getMe(), getEstate()]);
  if (!canOpen(me.role, "shuttle")) return <NotForRole title="Shuttle" />;
  const admin = me.role === "admin";

  if (estate.ok && !estate.data.settings.shuttle_enabled) {
    return (
      <>
        <PageHead title="Shuttle" />
        <Empty title="The estate shuttle is off">
          {admin ? (
            <>
              Turn it on in <Link href="/dashboard/settings#shuttle">Staff and settings</Link> if the estate runs one.
            </>
          ) : (
            "An estate admin can turn it on if the estate runs one."
          )}
        </Empty>
      </>
    );
  }

  return (
    <>
      <PageHead title="Shuttle">Rides on the estate&rsquo;s motorcycles: who booked, who rode, and how long people waited. Times are Lagos time.</PageHead>
      <nav className="dash-tabs" aria-label="Shuttle views">
        <Link href="/dashboard/shuttle" className="dash-tab" aria-current={tab === "rides" ? "page" : undefined}>
          Ride log
        </Link>
        <Link href="/dashboard/shuttle?tab=bikes" className="dash-tab" aria-current={tab === "bikes" ? "page" : undefined}>
          Motorcycles
        </Link>
        <Link href="/dashboard/shuttle?tab=report" className="dash-tab" aria-current={tab === "report" ? "page" : undefined}>
          Monthly report
        </Link>
      </nav>
      {tab === "rides" && <Rides sp={sp} />}
      {tab === "bikes" && <Bikes admin={admin} />}
      {tab === "report" && <Report month={sp.month && MONTH.test(sp.month) ? sp.month : thisMonthLagos()} />}
    </>
  );
}

// --- ride log -------------------------------------------------------------------------------------

async function Rides({ sp }: { sp: Search }) {
  const today = todayLagos();
  const to = sp.to && DAY.test(sp.to) ? sp.to : today;
  const from = sp.from && DAY.test(sp.from) ? sp.from : addDays(to, -6);
  const state = sp.state && sp.state in RIDE_STATE ? (sp.state as RideState) : "";
  const home = sp.home && UUID_RE.test(sp.home) ? sp.home : "";
  const rider = sp.rider && UUID_RE.test(sp.rider) ? sp.rider : "";

  const q = new URLSearchParams({ since: `${from}T00:00:00${TZ_OFFSET}`, until: `${addDays(to, 1)}T00:00:00${TZ_OFFSET}`, limit: String(LIMIT) });
  if (state) q.set("state", state);
  if (home) q.set("home_id", home);
  if (rider) q.set("rider_id", rider);

  const [rides, guards, register] = await Promise.all([
    load<Ride[]>(`/v1/admin/rides?${q}`),
    load<Guard[]>("/v1/admin/guards"),
    load<ZoneNode[]>("/v1/admin/register"),
  ]);
  const riders = guards.ok ? guards.data.filter((g) => g.role === "rider") : [];

  return (
    <>
      <Form action="/dashboard/shuttle" className="dash-filters">
        <div className="dash-field">
          <label htmlFor="from">From</label>
          <input id="from" name="from" type="date" className="dash-input dash-input--sm" defaultValue={from} max={today} />
        </div>
        <div className="dash-field">
          <label htmlFor="to">To</label>
          <input id="to" name="to" type="date" className="dash-input dash-input--sm" defaultValue={to} />
        </div>
        <div className="dash-field">
          <label htmlFor="state">State</label>
          <select id="state" name="state" className="dash-input dash-input--sm" defaultValue={state}>
            <option value="">Any</option>
            {(Object.keys(RIDE_STATE) as RideState[]).map((k) => (
              <option key={k} value={k}>
                {RIDE_STATE[k].label}
              </option>
            ))}
          </select>
        </div>
        <div className="dash-field">
          <label htmlFor="home">Home</label>
          <select id="home" name="home" className="dash-input dash-input--sm" defaultValue={home}>
            <option value="">All homes</option>
            {(register.ok ? register.data : []).flatMap((z) =>
              z.streets.map((st) => (
                <optgroup key={st.id} label={`${z.name}, ${st.name}`}>
                  {st.homes.map((h) => (
                    <option key={h.id} value={h.id}>
                      {h.address}
                    </option>
                  ))}
                </optgroup>
              )),
            )}
          </select>
        </div>
        <div className="dash-field">
          <label htmlFor="rider">Rider</label>
          <select id="rider" name="rider" className="dash-input dash-input--sm" defaultValue={rider}>
            <option value="">All riders</option>
            {riders.map((g) => (
              <option key={g.id} value={g.id}>
                {g.name}
              </option>
            ))}
          </select>
        </div>
        <button type="submit" className="dash-btn dash-btn--primary dash-btn--sm">
          Show
        </button>
      </Form>

      {!rides.ok ? (
        <ApiError error={rides.error} />
      ) : rides.data.length === 0 ? (
        <Empty title="No rides for these filters">Try a wider date range or clear the filters.</Empty>
      ) : (
        <>
          <p className="dash-muted dash-small">
            {rides.data.length === LIMIT ? `Showing the latest ${LIMIT} rides. Narrow the dates to see the rest.` : `${rides.data.length} rides, newest first.`}
          </p>
          <div className="dash-table-wrap">
            <table className="dash-table dash-table--stack">
              <thead>
                <tr>
                  <th scope="col">Wanted</th>
                  <th scope="col">Ride</th>
                  <th scope="col">Home</th>
                  <th scope="col">State</th>
                  <th scope="col">Rider</th>
                  <th scope="col">Booked</th>
                  <th scope="col">Who rode</th>
                </tr>
              </thead>
              <tbody>
                {rides.data.map((r) => (
                  <tr key={r.id}>
                    <td data-label="Wanted" className="tnum dash-nowrap">
                      <Link href={`/dashboard/shuttle/rides/${r.id}`}>{fmtDateTime(r.wanted_at)}</Link>
                    </td>
                    <td data-label="Ride">
                      {r.from} to {r.to}
                      <span className="dash-hint">
                        {RIDE_KIND[r.kind]}
                        {r.passenger ? `: ${r.passenger}` : ""}
                      </span>
                    </td>
                    <td data-label="Home">{r.address ?? <span className="dash-muted">Unknown</span>}</td>
                    <td data-label="State">
                      <Badge tone={RIDE_STATE[r.state].tone}>{RIDE_STATE[r.state].label}</Badge>
                    </td>
                    <td data-label="Rider">
                      {r.rider ?? <span className="dash-muted">Nobody yet</span>}
                      {r.shuttle && <span className="dash-hint">On {r.shuttle}</span>}
                    </td>
                    <td data-label="Booked">
                      {RIDE_SOURCE[r.source]}
                      {r.booked_by && <span className="dash-hint">By {r.booked_by}</span>}
                    </td>
                    <td data-label="Who rode">
                      {r.confirmed_by ? RIDE_CONFIRM[r.confirmed_by] : <span className="dash-muted">Not recorded</span>}
                      {r.confirmed_resident && <span className="dash-hint">{r.confirmed_resident}</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </>
  );
}

// --- motorcycles ----------------------------------------------------------------------------------

async function Bikes({ admin }: { admin: boolean }) {
  const bikes = await load<Motorcycle[]>("/v1/admin/shuttles");
  return (
    <Section title="Motorcycles" id="bikes">
      <p className="dash-muted dash-small">At the start of a shift each rider picks the motorcycle they are on. Retired motorcycles keep their rides in the log.</p>
      {!bikes.ok ? (
        <ApiError error={bikes.error} />
      ) : bikes.data.length === 0 ? (
        <Empty title="No motorcycles yet">{admin ? "Add the estate's motorcycles below." : undefined}</Empty>
      ) : (
        <div className="dash-table-wrap">
          <table className="dash-table dash-table--stack">
            <thead>
              <tr>
                <th scope="col">Name</th>
                <th scope="col">Plate</th>
                <th scope="col">Status</th>
                {admin && (
                  <th scope="col">
                    <span className="sr-only">Actions</span>
                  </th>
                )}
              </tr>
            </thead>
            <tbody>
              {bikes.data.map((b) => (
                <tr key={b.id}>
                  <td data-label="Name">
                    <strong>{b.label}</strong>
                  </td>
                  <td data-label="Plate">{b.plate ? <span className="dash-plate">{b.plate}</span> : <span className="dash-muted">None</span>}</td>
                  <td data-label="Status">{b.active ? <Badge tone="ok">In service</Badge> : <Badge>Retired</Badge>}</td>
                  {admin && (
                    <td data-label="Actions">
                      <span className="dash-row-actions">
                        <details className="dash-details dash-details--inline">
                          <summary>Edit</summary>
                          <ActionForm action={updateMotorcycle} hidden={{ id: b.id }} reset={false} submit="Save" submitClass="dash-btn dash-btn--primary dash-btn--sm">
                            <BikeFields id={b.id} label={b.label} plate={b.plate} />
                          </ActionForm>
                        </details>
                        {b.active ? (
                          <ConfirmButton action={setMotorcycleActive} hidden={{ id: b.id, active: "false" }} label="Retire" title={`Retire ${b.label}?`} confirmLabel="Retire">
                            <p>Riders can no longer pick it at the start of a shift. Its past rides stay in the log.</p>
                          </ConfirmButton>
                        ) : (
                          <ActionForm
                            action={setMotorcycleActive}
                            hidden={{ id: b.id, active: "true" }}
                            className="dash-inline-form"
                            submit="Back in service"
                            submitClass="dash-btn dash-btn--quiet dash-btn--sm"
                            showMessage={false}
                          />
                        )}
                      </span>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {admin && (
        <details className="dash-details">
          <summary>Add a motorcycle</summary>
          <ActionForm action={createMotorcycle} submit="Add motorcycle">
            <div className="dash-grid2">
              <BikeFields id="new" />
            </div>
          </ActionForm>
        </details>
      )}
    </Section>
  );
}

function BikeFields({ id, label, plate }: { id: string; label?: string; plate?: string | null }) {
  return (
    <>
      <div className="dash-field">
        <label htmlFor={`bike-label-${id}`}>Name</label>
        <input id={`bike-label-${id}`} name="label" className="dash-input" defaultValue={label} required maxLength={40} placeholder="For example, S1" />
        <span className="dash-hint">What riders and the CSO call it.</span>
      </div>
      <div className="dash-field">
        <label htmlFor={`bike-plate-${id}`}>Plate (optional)</label>
        <input
          id={`bike-plate-${id}`}
          name="plate"
          className="dash-input"
          defaultValue={plate ?? ""}
          maxLength={16}
          autoComplete="off"
          autoCapitalize="characters"
          spellCheck={false}
          placeholder="LND 1 EV"
        />
      </div>
    </>
  );
}

// --- monthly report ----------------------------------------------------------------------------------

const KINDS: RideKind[] = ["resident", "delivery", "guest"];

function CountTable<K extends string>({ caption, rows, labels }: { caption: string; rows: Partial<Record<K, number>>; labels: Record<K, string> }) {
  const entries = (Object.keys(labels) as K[]).map((k) => [k, rows[k] ?? 0] as const);
  return (
    <div className="dash-table-wrap">
      <table className="dash-table dash-table--num dash-table--compact">
        <caption className="sr-only">{caption}</caption>
        <thead>
          <tr>
            <th scope="col">{caption}</th>
            <th scope="col">Rides</th>
          </tr>
        </thead>
        <tbody>
          {entries.map(([k, n]) => (
            <tr key={k}>
              <th scope="row">{labels[k]}</th>
              <td className="tnum">{n}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

async function Report({ month }: { month: string }) {
  const r = await load<ShuttleReport>(`/v1/reports/shuttle?month=${month}`);
  const current = thisMonthLagos();
  return (
    <>
      <div className="dash-head">
        <h2 className="dash-h2">{fmtMonth(month)}</h2>
        <div className="dash-head__actions">
          <Link className="dash-btn dash-btn--ghost dash-btn--sm" href={`/dashboard/shuttle?tab=report&month=${addMonths(month, -1)}`}>
            Previous month
          </Link>
          {month < current && (
            <Link className="dash-btn dash-btn--ghost dash-btn--sm" href={`/dashboard/shuttle?tab=report&month=${addMonths(month, 1)}`}>
              Next month
            </Link>
          )}
        </div>
      </div>
      {!r.ok ? (
        <ApiError error={r.error} />
      ) : (
        <>
          <dl className="dash-figures">
            <div className="dash-fig">
              <dt>Rides booked</dt>
              <dd className="tnum">{r.data.rides}</dd>
            </div>
            <div className="dash-fig">
              <dt>Completed</dt>
              <dd className="tnum">{r.data.done}</dd>
            </div>
            <div className="dash-fig">
              <dt>Homes served</dt>
              <dd className="tnum">{r.data.homes_served}</dd>
            </div>
            <div className="dash-fig">
              <dt>Median wait</dt>
              <dd className="tnum">{r.data.median_wait_minutes == null ? "None" : `${r.data.median_wait_minutes} min`}</dd>
            </div>
          </dl>
          <p className="dash-muted dash-small">
            Kinds, zones and riders count completed rides. Booking and state count every ride booked for the month. The wait is from when the
            ride was wanted (or booked, if later) to when a rider took it, for rides booked by message or through the CSO.
          </p>

          <div className="dash-cards">
            <CountTable caption="Kind of ride" rows={r.data.by_kind} labels={RIDE_KIND} />
            <CountTable caption="How it was booked" rows={r.data.by_source} labels={RIDE_SOURCE} />
            <CountTable caption="How it ended" rows={r.data.by_state} labels={Object.fromEntries(Object.entries(RIDE_STATE).map(([k, v]) => [k, v.label])) as Record<RideState, string>} />
            <CountTable caption="How riders confirmed who rode" rows={r.data.confirmed_by} labels={RIDE_CONFIRM} />
          </div>

          <Section title="By zone" id="by-zone">
            {r.data.by_zone.length === 0 ? (
              <p className="dash-muted dash-small">No completed rides this month.</p>
            ) : (
              <div className="dash-table-wrap">
                <table className="dash-table dash-table--num dash-table--stack">
                  <thead>
                    <tr>
                      <th scope="col">Zone</th>
                      <th scope="col">Rides</th>
                      {KINDS.map((k) => (
                        <th key={k} scope="col">
                          {RIDE_KIND[k]}
                        </th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {r.data.by_zone.map((z) => (
                      <tr key={z.zone}>
                        <th scope="row">{z.zone}</th>
                        <td data-label="Rides" className="tnum">
                          {z.rides}
                        </td>
                        {KINDS.map((k) => (
                          <td key={k} data-label={RIDE_KIND[k]} className="tnum">
                            {z[k] ?? 0}
                          </td>
                        ))}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </Section>

          <Section title="By rider" id="by-rider">
            {r.data.by_rider.length === 0 ? (
              <p className="dash-muted dash-small">No completed rides this month.</p>
            ) : (
              <ul className="dash-rows">
                {r.data.by_rider.map((x) => (
                  <li key={x.rider} className="dash-rows__item">
                    <span className="dash-rows__main">{x.rider}</span>
                    <span className="tnum">{x.rides} rides</span>
                  </li>
                ))}
              </ul>
            )}
          </Section>
        </>
      )}
    </>
  );
}
