import type { Metadata } from "next";
import { getMe, load } from "@/app/(dashboard)/_lib/api";
import { ROLE, clock12, hhmm } from "@/app/(dashboard)/_lib/format";
import type { Estate, StaffMember } from "@/app/(dashboard)/_lib/types";
import { ActionForm } from "@/app/(dashboard)/_components/ActionForm";
import { ConfirmButton } from "@/app/(dashboard)/_components/ConfirmButton";
import { ApiError, Badge, PageHead, Section } from "@/app/(dashboard)/_components/ui";
import { createStaff, setStaffActive, updateSettings } from "../actions";
import { MessageName } from "./MessageName";

export const metadata: Metadata = { title: "Staff and settings" };

export default async function SettingsPage() {
  const me = await getMe();
  if (me.role !== "admin") {
    return (
      <>
        <PageHead title="Staff and settings" />
        <p className="dash-msg dash-msg--warn">Only an estate admin can see this page.</p>
      </>
    );
  }
  const [staff, estate] = await Promise.all([load<StaffMember[]>("/v1/admin/staff"), load<Estate>("/v1/admin/estate")]);

  return (
    <>
      <PageHead title="Staff and settings">Who can use this dashboard, and how the estate&rsquo;s gate works day to day.</PageHead>

      <Section title="Dashboard staff" id="staff">
        {!staff.ok ? (
          <ApiError error={staff.error} />
        ) : (
          <div className="dash-table-wrap">
            <table className="dash-table dash-table--stack">
              <thead>
                <tr>
                  <th scope="col">Name</th>
                  <th scope="col">Email</th>
                  <th scope="col">Role</th>
                  <th scope="col">Phone</th>
                  <th scope="col">Access</th>
                </tr>
              </thead>
              <tbody>
                {staff.data.map((u) => (
                  <tr key={u.id}>
                    <td data-label="Name">
                      {u.name}
                      {u.id === me.id && <span className="dash-hint">You</span>}
                    </td>
                    <td data-label="Email" className="dash-break">
                      {u.email}
                    </td>
                    <td data-label="Role">{ROLE[u.role]}</td>
                    <td data-label="Phone" className="tnum">
                      {u.phone ?? <span className="dash-muted">None</span>}
                    </td>
                    <td data-label="Access">
                      <span className="dash-row-actions">
                        {u.active ? <Badge tone="ok">Can sign in</Badge> : <Badge>Removed</Badge>}
                        {u.id !== me.id &&
                          (u.active ? (
                            <ConfirmButton action={setStaffActive} hidden={{ id: u.id, active: "false" }} label="Remove access" title={`Remove ${u.name}'s access?`} confirmLabel="Remove access">
                              <p>They will not be able to sign in to the dashboard again. You can restore access later.</p>
                            </ConfirmButton>
                          ) : (
                            <ActionForm action={setStaffActive} hidden={{ id: u.id, active: "true" }} className="dash-inline-form" submit="Restore access" submitClass="dash-btn dash-btn--quiet dash-btn--sm" showMessage={false} />
                          ))}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <details className="dash-details">
          <summary>Add a staff member</summary>
          <ActionForm action={createStaff} submit="Add staff member">
            <div className="dash-grid2">
              <div className="dash-field">
                <label htmlFor="staff-name">Full name</label>
                <input id="staff-name" name="name" className="dash-input" required minLength={2} maxLength={120} />
              </div>
              <div className="dash-field">
                <label htmlFor="staff-email">Email</label>
                <input id="staff-email" name="email" type="email" className="dash-input" required autoComplete="off" />
              </div>
              <div className="dash-field">
                <label htmlFor="staff-role">Role</label>
                <select id="staff-role" name="role" className="dash-input" defaultValue="committee">
                  <option value="admin">Estate admin: can change everything</option>
                  <option value="committee">Committee: can view, cannot change</option>
                  <option value="security_head">Security head: can view, cannot change</option>
                  <option value="treasurer">Treasurer: sees messaging usage and reports, cannot change</option>
                </select>
              </div>
              <div className="dash-field">
                <label htmlFor="staff-phone">Phone (security head only, optional)</label>
                <input id="staff-phone" name="phone" className="dash-input" inputMode="tel" autoComplete="off" placeholder="0803 123 4567" />
                <span className="dash-hint">The security head gets the night list of guests still inside on this number.</span>
              </div>
            </div>
          </ActionForm>
        </details>
      </Section>

      <Section title="Message name" id="message-name">
        {!estate.ok ? <ApiError error={estate.error} /> : <MessageName shortName={estate.data.short_name} estateName={estate.data.name} />}
      </Section>

      <Section title="Estate settings" id="settings">
        {!estate.ok ? <ApiError error={estate.error} /> : <SettingsForm estate={estate.data} />}
      </Section>
    </>
  );
}

function SettingsForm({ estate }: { estate: Estate }) {
  const s = estate.settings;
  return (
    <ActionForm action={updateSettings} reset={false} submit="Save settings" className="dash-form dash-settings">
      <Setting id="code_valid_until" label="Codes work until" hint={`A code with no arrival time given works until this time on the day. Now ${clock12(s.code_valid_until)}.`}>
        <input id="code_valid_until" name="code_valid_until" type="time" className="dash-input" defaultValue={hhmm(s.code_valid_until)} required />
      </Setting>
      <Setting id="default_stay_until" label="Guests expected to leave by" hint={`When a resident does not say how long a guest is staying, the guest is expected out by this time. Now ${clock12(s.default_stay_until)}.`}>
        <input id="default_stay_until" name="default_stay_until" type="time" className="dash-input" defaultValue={hhmm(s.default_stay_until)} required />
      </Setting>
      <Setting id="rollup_time" label="Night list time" hint={`Each night at this time, the security head gets the list of guests still inside past their time. Now ${clock12(s.rollup_time)}.`}>
        <input id="rollup_time" name="rollup_time" type="time" className="dash-input" defaultValue={hhmm(s.rollup_time)} required />
      </Setting>
      <Setting id="handover_time" label="Morning handover" hint={`Anyone still on last night's list at this time is closed as a missed exit. Now ${clock12(s.handover_time)}.`}>
        <input id="handover_time" name="handover_time" type="time" className="dash-input" defaultValue={hhmm(s.handover_time)} required />
      </Setting>
      <Setting id="walk_in_policy" label="Walk-in rule" hint="What the guard does when a guest has no code and the resident cannot be reached. Shown to guards in the gate app." wide>
        <textarea id="walk_in_policy" name="walk_in_policy" className="dash-input dash-textarea" defaultValue={s.walk_in_policy} maxLength={280} rows={3} required />
      </Setting>
      <Setting id="daily_sms_budget" label="Daily SMS limit" hint="The most SMS messages the estate sends in a day. Past this, messages are held and Gatelog is alerted, so the estate's credit is not drained. Between 10 and 20,000.">
        <input id="daily_sms_budget" name="daily_sms_budget" type="number" min={10} max={20000} className="dash-input" defaultValue={s.daily_sms_budget} required />
      </Setting>
      <Setting id="max_visits_per_home_per_day" label="Most visits per home per day" hint="Past this, the resident is asked to call the gate instead. Between 5 and 500.">
        <input id="max_visits_per_home_per_day" name="max_visits_per_home_per_day" type="number" min={5} max={500} className="dash-input" defaultValue={s.max_visits_per_home_per_day} required />
      </Setting>
    </ActionForm>
  );
}

function Setting({ id, label, hint, children, wide }: { id: string; label: string; hint: string; children: React.ReactNode; wide?: boolean }) {
  return (
    <div className={`dash-field${wide ? " dash-field--wide" : ""}`}>
      <label htmlFor={id}>{label}</label>
      {children}
      <span className="dash-hint">{hint}</span>
    </div>
  );
}
