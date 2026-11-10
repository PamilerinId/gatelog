import type { Metadata } from "next";
import Link from "next/link";
import { getEstate, getMe, load } from "@/app/(dashboard)/_lib/api";
import { TZ_OFFSET, ago, fmtTime, todayLagos } from "@/app/(dashboard)/_lib/format";
import { canOpen } from "@/app/(dashboard)/_lib/roles";
import type { Device, GateEntry, Guard, Live, LiveGate, Motorcycle } from "@/app/(dashboard)/_lib/types";
import { ActionForm } from "@/app/(dashboard)/_components/ActionForm";
import { ConfirmButton } from "@/app/(dashboard)/_components/ConfirmButton";
import { InlineEdit } from "@/app/(dashboard)/_components/InlineEdit";
import { ApiError, Empty, More, NotForRole, PageHead } from "@/app/(dashboard)/_components/ui";
import { createGate, createGuard, createMotorcycle, renameGate, revokeDevice, setMotorcycleActive, updateMotorcycle } from "../actions";
import { NewCodeButton, RegisterDevice } from "./DeviceTools";
import { ConsentCheck, GuardCard, RoleField } from "./GuardCards";

export const metadata: Metadata = { title: "Gates & guards" };

// The estate office's gates and people: a card per gate with its phones inside, a card per guard,
// and the shuttle when the estate runs one.

export default async function GatesPage() {
  const me = await getMe();
  if (!canOpen(me.role, "gate")) return <NotForRole title="Gates & guards" />;
  const since = `${todayLagos()}T00:00:00${TZ_OFFSET}`;
  const [estate, live, devices, guards, entries] = await Promise.all([
    getEstate(),
    load<Live>("/v1/admin/live"),
    load<Device[]>("/v1/admin/devices"),
    load<Guard[]>("/v1/admin/guards"),
    load<GateEntry[]>(`/v1/admin/entries?${new URLSearchParams({ since, limit: "1000" })}`),
  ]);
  const shuttle = estate.ok && estate.data.settings.shuttle_enabled;
  const bikes = shuttle ? await load<Motorcycle[]>("/v1/admin/shuttles") : null;
  const people = guards.ok ? guards.data : [];
  const staff = people.filter((g) => g.role !== "rider");
  const riders = people.filter((g) => g.role === "rider");

  return (
    <>
      <PageHead
        title="Gates & guards"
        actions={
          <>
            <details className="dash-primary-fold">
              <summary className="dash-btn dash-btn--primary">Add a guard</summary>
              <div className="dash-primary-fold__panel dash-glass">
                <ActionForm action={createGuard} submit="Add">
                  <div className="dash-field">
                    <label htmlFor="guard-name">Full name</label>
                    <input id="guard-name" name="name" className="dash-input" required minLength={2} maxLength={120} />
                  </div>
                  <RoleField id="guard-role" shuttle={shuttle} />
                  <ConsentCheck />
                </ActionForm>
              </div>
            </details>
            <More>
              <Link href="/dashboard/shifts">Shifts and selfies</Link>
              <details className="dash-details dash-details--inline">
                <summary>Add a gate</summary>
                <ActionForm action={createGate} className="dash-form" submit="Add gate" submitClass="dash-btn dash-btn--primary dash-btn--sm">
                  <div className="dash-field">
                    <label htmlFor="gate-name">Gate name</label>
                    <input id="gate-name" name="name" className="dash-input" placeholder="For example, Back Gate" required maxLength={120} />
                  </div>
                </ActionForm>
              </details>
            </More>
          </>
        }
      >
        Each gate, who is on duty and its phones. Use Change on a card to change it.
      </PageHead>

      {!live.ok ? (
        <ApiError error={live.error} />
      ) : live.data.gates.length === 0 ? (
        <Empty title="No gates yet">Add a gate from More, then register its phone.</Empty>
      ) : (
        <ul className="dash-gatecards dash-gatecards--grid">
          {live.data.gates.map((g) => (
            <GateCard key={g.id} g={g} devices={devices.ok ? devices.data.filter((d) => d.gate_id === g.id) : []} entries={entries.ok ? entries.data : []} />
          ))}
        </ul>
      )}

      <h2 className="dash-h2 dash-mt">Guards</h2>
      {!guards.ok ? (
        <ApiError error={guards.error} />
      ) : staff.length === 0 ? (
        <Empty title="No guards yet">Add the guards who work the gate, and the CSO.</Empty>
      ) : (
        <ul className="dash-personcards">
          {staff.map((g) => (
            <GuardCard key={g.id} g={g} admin shuttle={shuttle} />
          ))}
        </ul>
      )}

      {shuttle && (
        <section id="shuttle" className="dash-mt" aria-labelledby="shuttle-title">
          <div className="dash-section__head">
            <h2 className="dash-h2" id="shuttle-title">
              Shuttle
            </h2>
            <Link href="/dashboard/shuttle" className="dash-quiet-link">
              See all rides →
            </Link>
          </div>
          <h3 className="dash-h3">Motorcycles</h3>
          {bikes && !bikes.ok ? (
            <ApiError error={bikes.error} />
          ) : (
            <ul className="dash-personcards">
              {(bikes?.ok ? bikes.data : []).map((b) => (
                <li key={b.id} className={`dash-personcard${b.active ? "" : " is-off"}`}>
                  <div className="dash-personcard__top">
                    <span className="dash-personcard__name">{b.label}</span>
                    <More label="Change">
                      <details className="dash-details dash-details--inline">
                        <summary>Name and plate</summary>
                        <ActionForm action={updateMotorcycle} hidden={{ id: b.id }} reset={false} submit="Save" submitClass="dash-btn dash-btn--primary dash-btn--sm">
                          <BikeFields id={b.id} label={b.label} plate={b.plate} />
                        </ActionForm>
                      </details>
                      {b.active ? (
                        <ConfirmButton action={setMotorcycleActive} hidden={{ id: b.id, active: "false" }} label="Retire" title={`Retire ${b.label}?`} confirmLabel="Retire">
                          <p>Riders can no longer pick it at the start of a shift. Its past rides stay in the log.</p>
                        </ConfirmButton>
                      ) : (
                        <ActionForm action={setMotorcycleActive} hidden={{ id: b.id, active: "true" }} className="dash-inline-form" submit="Back in service" submitClass="dash-btn dash-btn--quiet dash-btn--sm" showMessage={false} />
                      )}
                    </More>
                  </div>
                  <span className="dash-personcard__role dash-plate">{b.plate ?? "No plate"}</span>
                  <span className="dash-personcard__fact">{b.active ? "In service" : "Retired"}</span>
                </li>
              ))}
              <li className="dash-personcard dash-personcard--add">
                <details>
                  <summary>Add a motorcycle</summary>
                  <ActionForm action={createMotorcycle} submit="Add motorcycle" submitClass="dash-btn dash-btn--primary dash-btn--sm">
                    <BikeFields id="new" />
                  </ActionForm>
                </details>
              </li>
            </ul>
          )}
          <h3 className="dash-h3 dash-mt">Riders</h3>
          {riders.length === 0 ? (
            <p className="dash-muted dash-small">No riders yet. Add one with Add a guard and choose Shuttle rider.</p>
          ) : (
            <ul className="dash-personcards">
              {riders.map((g) => (
                <GuardCard key={g.id} g={g} admin shuttle={shuttle} />
              ))}
            </ul>
          )}
        </section>
      )}
    </>
  );
}

function GateCard({ g, devices, entries }: { g: LiveGate; devices: Device[]; entries: GateEntry[] }) {
  const working = devices.filter((d) => d.status !== "revoked");
  const off = g.phones > 0 && g.quiet;
  const mine = entries.filter((e) => e.gate === g.name && e.method !== "refused");
  const duty = g.on_duty.length ? g.on_duty.map((d) => `${d.guard.split(" ")[0]} on duty since ${fmtTime(d.since)}`).join(", ") : "Nobody on duty";
  return (
    <li className="dash-gatecard dash-gatecard--office">
      <span className="dash-gatecard__top">
        <span className="dash-gatecard__name">{g.name}</span>
        <span className={`dash-gatecard__state dash-mono${off || g.phones === 0 ? " is-warn" : ""}`}>
          <span className={`dash-dot dash-dot--${off || g.phones === 0 ? "warn" : "gate"}`} aria-hidden="true" />
          {g.phones === 0 ? "no phone" : off ? "offline" : "online"}
        </span>
      </span>
      <span className="dash-gatecard__line">{duty}</span>
      <span className="dash-gatecard__line dash-mono">
        {mine.length} in today · {mine.filter((e) => !e.exit_at).length} still inside
      </span>
      <div className="dash-gatecard__phones">
        {working.length === 0 ? (
          <p className="dash-warn-text dash-small">No phone at this gate.</p>
        ) : (
          <ul className="dash-plainlist">
            {working.map((d) => (
              <li key={d.id} className="dash-plainlist__item">
                <span className="dash-plainlist__main">
                  {d.label}
                  <span className="dash-hint">
                    {d.status === "awaiting pairing" ? "Waiting to be paired" : d.last_sync_at ? `Synced ${ago(d.last_sync_at)}` : "Never synced"}
                  </span>
                </span>
              </li>
            ))}
          </ul>
        )}
        <More label="Change" align="start">
          <details className="dash-details dash-details--inline">
            <summary>Add a phone to this gate</summary>
            <RegisterDevice gates={[]} gate={{ id: g.id, name: g.name }} />
          </details>
          {working.map((d) => (
            <details key={d.id} className="dash-details dash-details--inline">
              <summary>{d.label}: new code or revoke</summary>
              <div className="dash-row-actions">
                <NewCodeButton device={d} />
                <ConfirmButton action={revokeDevice} hidden={{ id: d.id }} label="Revoke this phone" title={`Revoke ${d.label}?`} confirmLabel="Revoke this phone">
                  <p>Use this if the phone is lost, stolen or no longer used at the gate.</p>
                  <ul>
                    <li>The phone is cut off at once. It can no longer sync or check codes.</li>
                    <li>From now on, new codes use a new key, so the lost phone cannot check or make them.</li>
                    <li>Codes residents already have keep working until they expire.</li>
                    <li>A revoked phone cannot be paired again. To use it again, register it as a new phone.</li>
                  </ul>
                </ConfirmButton>
              </div>
            </details>
          ))}
          <InlineEdit action={renameGate} hidden={{ id: g.id }} name="name" value={g.name} label={`New name for ${g.name}`} buttonLabel="Rename this gate" />
        </More>
      </div>
    </li>
  );
}

function BikeFields({ id, label, plate }: { id: string; label?: string; plate?: string | null }) {
  return (
    <>
      <div className="dash-field">
        <label htmlFor={`bike-label-${id}`}>Name</label>
        <input id={`bike-label-${id}`} name="label" className="dash-input" defaultValue={label} required maxLength={40} placeholder="For example, S1" />
      </div>
      <div className="dash-field">
        <label htmlFor={`bike-plate-${id}`}>Plate (optional)</label>
        <input id={`bike-plate-${id}`} name="plate" className="dash-input" defaultValue={plate ?? ""} maxLength={16} autoComplete="off" autoCapitalize="characters" spellCheck={false} placeholder="LND 1 EV" />
      </div>
    </>
  );
}
