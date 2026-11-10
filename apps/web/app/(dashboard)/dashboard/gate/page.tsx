import type { Metadata } from "next";
import { getEstate, getMe, load } from "@/app/(dashboard)/_lib/api";
import { GUARD_ROLE, SELFIE, SHIFT_END, fmtDate, fmtDateTime } from "@/app/(dashboard)/_lib/format";
import type { Device, Gate, Guard, Shift } from "@/app/(dashboard)/_lib/types";
import { ActionForm } from "@/app/(dashboard)/_components/ActionForm";
import { ConfirmButton } from "@/app/(dashboard)/_components/ConfirmButton";
import { ApiError, Badge, Empty, PageHead, Section } from "@/app/(dashboard)/_components/ui";
import { createGate, createGuard, resetGuardPin, revokeDevice, setGuardActive, updateGuard } from "../actions";
import { NewCodeButton, RegisterDevice } from "./DeviceTools";
import { SelfieButton } from "./SelfieButton";

export const metadata: Metadata = { title: "Guards and gate phones" };

const STATUS: Record<Device["status"], { label: string; tone: "ok" | "warn" | "bad" }> = {
  paired: { label: "Working", tone: "ok" },
  "awaiting pairing": { label: "Waiting to be paired", tone: "warn" },
  revoked: { label: "Revoked", tone: "bad" },
};

const SHIFT_DAYS = 14;

export default async function GatePage() {
  const [me, estate] = await Promise.all([getMe(), getEstate()]);
  const admin = me.role === "admin";
  const shuttle = estate.ok && estate.data.settings.shuttle_enabled;
  // Selfies are personal data: only the estate admin and the security head may open them.
  const canSeeSelfies = admin || me.role === "security_head";
  const since = new Date(Date.now() - SHIFT_DAYS * 86_400_000).toISOString();
  const [guards, gates, devices, shifts] = await Promise.all([
    load<Guard[]>("/v1/admin/guards"),
    load<Gate[]>("/v1/admin/gates"),
    admin ? load<Device[]>("/v1/admin/devices") : Promise.resolve(null),
    load<Shift[]>(`/v1/admin/shifts?${new URLSearchParams({ since })}`),
  ]);
  const gateName = new Map((gates.ok ? gates.data : []).map((g) => [g.id, g.name]));

  return (
    <>
      <PageHead title="Guards and gate phones">The people on duty, their shifts, the estate&rsquo;s gates, and the phones guards use to check codes.</PageHead>

      <Section title="Guards and CSO" id="guards">
        <p className="dash-muted dash-small">
          Each person starts a shift on a gate phone with their own PIN and a selfie. The CSO signs in on any gate phone the same way and gets
          the CSO view: who is on duty at each gate, guests past their time, walk-ins and refusals.
          {shuttle && " Shuttle riders sign in the same way, pick their motorcycle, and their phone reports where they are while the shift is open."}
        </p>
        {!guards.ok ? (
          <ApiError error={guards.error} />
        ) : guards.data.length === 0 ? (
          <Empty title="No guards yet">{admin ? "Add the guards who work the gate, and the CSO." : undefined}</Empty>
        ) : (
          <div className="dash-table-wrap">
            <table className="dash-table dash-table--stack">
              <thead>
                <tr>
                  <th scope="col">Name</th>
                  <th scope="col">Role</th>
                  <th scope="col">Selfie consent</th>
                  <th scope="col">PIN</th>
                  <th scope="col">Status</th>
                  {admin && (
                    <th scope="col">
                      <span className="sr-only">Actions</span>
                    </th>
                  )}
                </tr>
              </thead>
              <tbody>
                {guards.data.map((g) => (
                  <GuardRow key={g.id} g={g} admin={admin} shuttle={shuttle} />
                ))}
              </tbody>
            </table>
          </div>
        )}
        {admin && (
          <details className="dash-details">
            <summary>Add a guard or CSO</summary>
            <ActionForm action={createGuard} submit="Add">
              <div className="dash-grid2">
                <div className="dash-field">
                  <label htmlFor="guard-name">Full name</label>
                  <input id="guard-name" name="name" className="dash-input" required minLength={2} maxLength={120} />
                </div>
                <RoleField id="guard-role" shuttle={shuttle} />
              </div>
              <ConsentCheck />
            </ActionForm>
          </details>
        )}
      </Section>

      <Section title="Shifts" id="shifts">
        <p className="dash-muted dash-small">
          The last {SHIFT_DAYS} days, newest first. When a shift ends, the gate phone records who took over, how many guests were still
          inside, how many records had not synced yet, and how many names on the night list were still to check.
        </p>
        {canSeeSelfies && <p className="dash-msg dash-msg--warn">Viewing is recorded in the audit log. Selfies are deleted after 30 days.</p>}
        {!shifts.ok ? (
          <ApiError error={shifts.error} />
        ) : shifts.data.length === 0 ? (
          <Empty title="No shifts yet">Shifts appear here once someone starts one on a gate phone and the phone syncs.</Empty>
        ) : (
          <div className="dash-table-wrap">
            <table className="dash-table dash-table--stack">
              <thead>
                <tr>
                  <th scope="col">Person</th>
                  <th scope="col">Gate</th>
                  <th scope="col">Started</th>
                  <th scope="col">Ended</th>
                  <th scope="col">How it ended</th>
                  <th scope="col">Handover</th>
                  <th scope="col">Selfie</th>
                </tr>
              </thead>
              <tbody>
                {shifts.data.map((sh) => (
                  <ShiftRow key={sh.id} sh={sh} canSeeSelfies={canSeeSelfies} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Section>

      <Section title="Gates" id="gates">
        {!gates.ok ? (
          <ApiError error={gates.error} />
        ) : gates.data.length === 0 ? (
          <Empty title="No gates yet" />
        ) : (
          <ul className="dash-rows">
            {gates.data.map((g) => (
              <li key={g.id} className="dash-rows__item">
                <span className="dash-rows__main">{g.name}</span>
              </li>
            ))}
          </ul>
        )}
        {admin && (
          <ActionForm action={createGate} className="dash-inline-form dash-add" submit="Add gate" submitClass="dash-btn dash-btn--ghost dash-btn--sm">
            <label htmlFor="gate-name" className="sr-only">
              Gate name
            </label>
            <input id="gate-name" name="name" className="dash-input dash-input--sm" placeholder="For example, Back Gate" required maxLength={120} />
          </ActionForm>
        )}
      </Section>

      <Section title="Gate phones" id="phones">
        {!admin ? (
          <p className="dash-muted">Only an estate admin can see and manage gate phones.</p>
        ) : !devices?.ok ? (
          <ApiError error={devices?.error ?? "Could not load gate phones."} />
        ) : (
          <>
            {devices.data.length === 0 ? (
              <Empty title="No gate phones yet">Register the phone at each gate. You get a pairing code to type into the Gatelog app on that phone.</Empty>
            ) : (
              <div className="dash-table-wrap">
                <table className="dash-table dash-table--stack">
                  <thead>
                    <tr>
                      <th scope="col">Phone</th>
                      <th scope="col">Gate</th>
                      <th scope="col">Status</th>
                      <th scope="col">Last sync</th>
                      <th scope="col">
                        <span className="sr-only">Actions</span>
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    {devices.data.map((d) => (
                      <tr key={d.id}>
                        <td data-label="Phone">{d.label}</td>
                        <td data-label="Gate">{gateName.get(d.gate_id) ?? "Unknown gate"}</td>
                        <td data-label="Status">
                          <Badge tone={STATUS[d.status].tone}>{STATUS[d.status].label}</Badge>
                          {d.revoked_at && <span className="dash-hint">since {fmtDateTime(d.revoked_at)}</span>}
                        </td>
                        <td data-label="Last sync">{d.last_sync_at ? fmtDateTime(d.last_sync_at) : <span className="dash-muted">Never</span>}</td>
                        <td data-label="Actions">
                          {d.status !== "revoked" && (
                            <span className="dash-row-actions">
                              <NewCodeButton device={d} />
                              <ConfirmButton action={revokeDevice} hidden={{ id: d.id }} label="Revoke" title={`Revoke ${d.label}?`} confirmLabel="Revoke this phone">
                                <p>Use this if the phone is lost, stolen or no longer used at the gate.</p>
                                <ul>
                                  <li>The phone is cut off at once. It can no longer sync or check codes.</li>
                                  <li>From now on, new codes use a new key, so the lost phone cannot check or make them.</li>
                                  <li>Codes residents already have keep working until they expire.</li>
                                  <li>A revoked phone cannot be paired again. To use it again, register it as a new phone.</li>
                                </ul>
                              </ConfirmButton>
                            </span>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
            <h3 className="dash-h3 dash-mt">Register a gate phone</h3>
            <RegisterDevice gates={gates.ok ? gates.data : []} />
          </>
        )}
      </Section>
    </>
  );
}

function RoleField({ id, value = "guard", shuttle }: { id: string; value?: string; shuttle: boolean }) {
  return (
    <div className="dash-field">
      <label htmlFor={id}>Role</label>
      <select id={id} name="role" className="dash-input" defaultValue={value}>
        <option value="guard">Guard</option>
        <option value="cso">CSO (chief security officer)</option>
        {(shuttle || value === "rider") && <option value="rider">Shuttle rider</option>}
      </select>
      <span className="dash-hint">
        The CSO signs in on any gate phone and gets the CSO view.
        {shuttle && " A shuttle rider gets the rider view; their position is shared only while their shift is open."}
      </span>
    </div>
  );
}

function ConsentCheck({ checked }: { checked?: boolean }) {
  return (
    <label className="dash-check">
      <input type="checkbox" name="consent_recorded" defaultChecked={checked} />
      <span>
        Written consent recorded
        <span className="dash-hint">
          Tick this once they have signed the written consent to shift selfies. The gate phone won&rsquo;t start their shift until this is
          ticked.
        </span>
      </span>
    </label>
  );
}

function GuardRow({ g, admin, shuttle }: { g: Guard; admin: boolean; shuttle: boolean }) {
  return (
    <tr>
      <td data-label="Name">
        <strong>{g.name}</strong>
      </td>
      <td data-label="Role">{g.role === "guard" ? GUARD_ROLE.guard : <Badge tone="info">{GUARD_ROLE[g.role]}</Badge>}</td>
      <td data-label="Selfie consent">
        {g.consent_at ? (
          <>
            <Badge tone="ok">Recorded</Badge>
            <span className="dash-hint">{fmtDate(g.consent_at)}</span>
          </>
        ) : (
          <>
            <Badge tone="warn">Not recorded</Badge>
            <span className="dash-hint">Their shift won&rsquo;t start until it is.</span>
          </>
        )}
      </td>
      <td data-label="PIN">
        {g.pin_set ? (
          <>
            Set
            {g.pin_set_at && <span className="dash-hint">{fmtDate(g.pin_set_at)}</span>}
          </>
        ) : (
          <span className="dash-muted">Not set: they choose it at their next shift</span>
        )}
      </td>
      <td data-label="Status">{g.active ? <Badge tone="ok">Active</Badge> : <Badge>Deactivated</Badge>}</td>
      {admin && (
        <td data-label="Actions">
          <span className="dash-row-actions">
            <details className="dash-details dash-details--inline">
              <summary>Edit</summary>
              <ActionForm action={updateGuard} hidden={{ id: g.id }} reset={false} submit="Save" submitClass="dash-btn dash-btn--primary dash-btn--sm">
                <RoleField id={`role-${g.id}`} value={g.role} shuttle={shuttle} />
                <ConsentCheck checked={g.consent_at != null} />
              </ActionForm>
            </details>
            {g.pin_set && (
              <ConfirmButton action={resetGuardPin} hidden={{ id: g.id }} label="Reset PIN" title={`Reset ${g.name}'s PIN?`} confirmLabel="Reset PIN" danger={false}>
                <p>Use this when they have forgotten their PIN.</p>
                <ul>
                  <li>Their old PIN stops working once the gate phones next sync.</li>
                  <li>They choose a new PIN on the gate phone at their next shift. Nobody else ever sees it.</li>
                </ul>
              </ConfirmButton>
            )}
            {g.active ? (
              <ConfirmButton action={setGuardActive} hidden={{ id: g.id, active: "false" }} label="Deactivate" title={`Deactivate ${g.name}?`} confirmLabel="Deactivate">
                <p>They will no longer appear on the gate phones. Their past entries and shifts stay in the log.</p>
              </ConfirmButton>
            ) : (
              <ActionForm action={setGuardActive} hidden={{ id: g.id, active: "true" }} className="dash-inline-form" submit="Reactivate" submitClass="dash-btn dash-btn--quiet dash-btn--sm" showMessage={false} />
            )}
          </span>
        </td>
      )}
    </tr>
  );
}

function ShiftRow({ sh, canSeeSelfies }: { sh: Shift; canSeeSelfies: boolean }) {
  const who = sh.guard ?? "Unknown";
  const h = sh.handover;
  const selfie = SELFIE[sh.selfie];
  return (
    <tr>
      <td data-label="Person">
        <strong>{who}</strong>
        {sh.role && <span className="dash-hint">{GUARD_ROLE[sh.role]}</span>}
      </td>
      <td data-label="Gate">{sh.gate ?? <span className="dash-muted">Unknown gate</span>}</td>
      <td data-label="Started" className="tnum dash-nowrap">
        {fmtDateTime(sh.started_at)}
      </td>
      <td data-label="Ended" className="tnum dash-nowrap">
        {sh.ended_at ? fmtDateTime(sh.ended_at) : <Badge tone="ok">On shift</Badge>}
      </td>
      <td data-label="How it ended">
        {sh.end_reason ? SHIFT_END[sh.end_reason] : <span className="dash-muted">Not ended yet</span>}
        {sh.handed_to && <span className="dash-hint">Taken over by {sh.handed_to}</span>}
      </td>
      <td data-label="Handover">
        {h ? (
          <span className="dash-small">
            {h.inside ?? 0} inside, {h.unsynced ?? 0} not synced
            {h.night_list_open != null && `, ${h.night_list_open} on the night list`}
          </span>
        ) : (
          <span className="dash-muted">None</span>
        )}
      </td>
      <td data-label="Selfie">
        <span className="dash-row-actions">
          <Badge tone={selfie.tone}>{selfie.label}</Badge>
          {canSeeSelfies && sh.selfie === "available" && <SelfieButton shiftId={sh.id} who={who} when={fmtDateTime(sh.started_at)} />}
        </span>
      </td>
    </tr>
  );
}
