import type { Metadata } from "next";
import Link from "next/link";
import { getEstate, getMap, getMe, load } from "@/app/(dashboard)/_lib/api";
import { ROLE, clock12, hhmm } from "@/app/(dashboard)/_lib/format";
import { canOpen } from "@/app/(dashboard)/_lib/roles";
import type { Estate, StaffMember } from "@/app/(dashboard)/_lib/types";
import { ActionForm } from "@/app/(dashboard)/_components/ActionForm";
import { ConfirmButton } from "@/app/(dashboard)/_components/ConfirmButton";
import { ApiError, Fold, More, NotForRole, PageHead } from "@/app/(dashboard)/_components/ui";
import { createStaff, setStaffActive, updateSettings, updateShuttleSettings, updateVisitorPhotos } from "../actions";
import { MessageName } from "./MessageName";

export const metadata: Metadata = { title: "Settings" };

const PHOTOS = {
  all: "Every visitor",
  phone_entries: "Only visitors without a code (phone calls, PIN, walk-ins)",
  off: "Never",
} as const;

// The estate office's settings: one list, and each section opens on its own.

export default async function SettingsPage() {
  const me = await getMe();
  if (!canOpen(me.role, "settings")) return <NotForRole title="Settings" />;
  const [staff, estate, map] = await Promise.all([load<StaffMember[]>("/v1/admin/staff"), getEstate(), getMap()]);
  const e = estate.ok ? estate.data : null;
  const s = e?.settings;
  const activeStaff = staff.ok ? staff.data.filter((u) => u.active).length : 0;

  return (
    <>
      <PageHead title="Settings">How the estate&rsquo;s gate works, who can use this dashboard, and the tools you need now and then.</PageHead>
      {!estate.ok && <ApiError error={estate.error} />}

      <div className="dash-folds">
        <Fold group="settings" title="Estate and message name" status={e ? (e.short_name ? `Messages start with ${e.short_name}` : e.name) : undefined}>
          {e && (
            <>
              <p className="dash-small">
                <strong>{e.name}</strong>, {e.lga}, {e.state}. Set up by Gatelog; ask Gatelog to change these.
              </p>
              <MessageName shortName={e.short_name} estateName={e.name} />
            </>
          )}
        </Fold>

        <Fold group="settings" title="Gate rules and times" status={s ? `Codes until ${clock12(s.code_valid_until)} · night list ${clock12(s.rollup_time)}` : undefined}>
          {e && <SettingsForm estate={e} />}
        </Fold>

        <Fold group="settings" title="Dashboard staff" status={staff.ok ? `${activeStaff} can sign in` : undefined}>
          {!staff.ok ? <ApiError error={staff.error} /> : <Staff staff={staff.data} meId={me.id} />}
        </Fold>

        <Fold group="settings" title="Visitor photos" status={s ? PHOTOS[s.visitor_photos ?? "phone_entries"] : undefined}>
          {s && (
            <ActionForm action={updateVisitorPhotos} reset={false} submit="Save" className="dash-form">
              <fieldset className="dash-radios">
                <legend className="dash-small">When should the gate phone take a photo of the visitor?</legend>
                {(Object.keys(PHOTOS) as (keyof typeof PHOTOS)[]).map((k) => (
                  <label key={k} className="dash-check">
                    <input type="radio" name="visitor_photos" value={k} defaultChecked={(s.visitor_photos ?? "phone_entries") === k} />
                    <span>{PHOTOS[k]}</span>
                  </label>
                ))}
              </fieldset>
              <p className="dash-hint">
                The guard can always skip a photo (no camera, or the visitor refuses); a skipped photo is recorded. Photos are seen only by the estate
                admin and the security head, and every viewing is recorded.
              </p>
            </ActionForm>
          )}
        </Fold>

        <Fold group="settings" title="Estate shuttle" status={s ? (s.shuttle_enabled ? `On · ${s.max_rides_per_home_per_day} rides per home a day` : "Off") : undefined}>
          {e && <ShuttleForm estate={e} />}
        </Fold>

        <Fold group="settings" title="Estate map" status={map.ok ? (map.data.bbox ? "Boundary drawn" : "Not drawn yet") : undefined} tone={map.ok && !map.data.bbox ? "warn" : undefined}>
          <p className="dash-small">
            The satellite map behind the dashboard is locked to the estate&rsquo;s boundary. Draw it, pin each gate, and add the places residents ride
            the shuttle to.
          </p>
          <Link href="/dashboard/settings/map" className="dash-btn dash-btn--ghost dash-btn--sm">
            Open the map editor
          </Link>
        </Fold>

        <ToolLink href="/dashboard/emergency-numbers" title="Emergency numbers" note="The numbers residents get with NUMBERS" />
        <ToolLink href="/dashboard/import" title="Import a register" note="Homes and residents from a spreadsheet" />
        <ToolLink href="/dashboard/messaging" title="Messaging usage" note="What was sent this month" />
      </div>
    </>
  );
}

function ToolLink({ href, title, note }: { href: string; title: string; note: string }) {
  return (
    <Link href={href} className="dash-fold dash-fold--link">
      <span className="dash-fold__head">
        <span className="dash-fold__title">{title}</span>
        <span className="dash-fold__status">{note}</span>
      </span>
    </Link>
  );
}

function Staff({ staff, meId }: { staff: StaffMember[]; meId: string }) {
  return (
    <>
      <ul className="dash-plainlist">
        {staff.map((u) => (
          <li key={u.id} className={`dash-plainlist__item${u.active ? "" : " is-off"}`}>
            <span className="dash-plainlist__main">
              <strong>{u.name}</strong>
              {u.id === meId && <span className="dash-muted"> (you)</span>}
              <span className="dash-hint">
                {ROLE[u.role]} · {u.email}
                {u.phone ? ` · ${u.phone}` : ""}
                {u.active ? "" : " · cannot sign in"}
              </span>
            </span>
            {u.id !== meId &&
              (u.active ? (
                <More label="Change">
                  <ConfirmButton action={setStaffActive} hidden={{ id: u.id, active: "false" }} label="Remove access" title={`Remove ${u.name}'s access?`} confirmLabel="Remove access">
                    <p>They will not be able to sign in to the dashboard again. You can restore access later.</p>
                  </ConfirmButton>
                </More>
              ) : (
                <ActionForm action={setStaffActive} hidden={{ id: u.id, active: "true" }} className="dash-inline-form" submit="Restore access" submitClass="dash-btn dash-btn--quiet dash-btn--sm" showMessage={false} />
              ))}
          </li>
        ))}
      </ul>
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
              <label htmlFor="staff-role">What they do</label>
              <select id="staff-role" name="role" className="dash-input" defaultValue="committee">
                <option value="admin">Estate office: can change everything</option>
                <option value="committee">Committee (Exco): the day and the monthly report</option>
                <option value="security_head">Security head or CSO: live map, gate log, shifts, guards</option>
                <option value="treasurer">Treasurer: messages and the monthly report</option>
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
    </>
  );
}

function SettingsForm({ estate }: { estate: Estate }) {
  const s = estate.settings;
  return (
    <ActionForm action={updateSettings} reset={false} submit="Save" className="dash-form dash-settings">
      <Setting id="code_valid_until" label="Codes work until" hint={`A code with no arrival time works until this time on the day. Now ${clock12(s.code_valid_until)}.`}>
        <input id="code_valid_until" name="code_valid_until" type="time" className="dash-input" defaultValue={hhmm(s.code_valid_until)} required />
      </Setting>
      <Setting id="default_stay_until" label="Guests expected to leave by" hint={`When a resident does not say how long a guest is staying. Now ${clock12(s.default_stay_until)}.`}>
        <input id="default_stay_until" name="default_stay_until" type="time" className="dash-input" defaultValue={hhmm(s.default_stay_until)} required />
      </Setting>
      <Setting id="rollup_time" label="Night list time" hint={`Each night the security head gets the list of guests still inside. Now ${clock12(s.rollup_time)}.`}>
        <input id="rollup_time" name="rollup_time" type="time" className="dash-input" defaultValue={hhmm(s.rollup_time)} required />
      </Setting>
      <Setting id="handover_time" label="Morning handover" hint={`Anyone still on last night's list is closed as a missed exit. Now ${clock12(s.handover_time)}.`}>
        <input id="handover_time" name="handover_time" type="time" className="dash-input" defaultValue={hhmm(s.handover_time)} required />
      </Setting>
      <Setting id="walk_in_policy" label="Walk-in rule" hint="What the guard does when a guest has no code and the resident cannot be reached. Shown to guards on the gate phone." wide>
        <textarea id="walk_in_policy" name="walk_in_policy" className="dash-input dash-textarea" defaultValue={s.walk_in_policy} maxLength={280} rows={3} required />
      </Setting>
      <Setting id="daily_sms_budget" label="Daily SMS limit" hint="Past this, messages are held and Gatelog is alerted, so the estate's credit is not drained. Between 10 and 20,000.">
        <input id="daily_sms_budget" name="daily_sms_budget" type="number" min={10} max={20000} className="dash-input" defaultValue={s.daily_sms_budget} required />
      </Setting>
      <Setting id="max_visits_per_home_per_day" label="Most visits per home per day" hint="Past this, the resident is asked to call the gate instead. Between 5 and 500.">
        <input id="max_visits_per_home_per_day" name="max_visits_per_home_per_day" type="number" min={5} max={500} className="dash-input" defaultValue={s.max_visits_per_home_per_day} required />
      </Setting>
    </ActionForm>
  );
}

function ShuttleForm({ estate }: { estate: Estate }) {
  const s = estate.settings;
  return (
    <ActionForm action={updateShuttleSettings} reset={false} submit="Save" className="dash-form dash-settings">
      <div className="dash-field dash-field--wide">
        <label className="dash-check">
          <input type="checkbox" name="shuttle_enabled" defaultChecked={s.shuttle_enabled} />
          <span>
            The estate runs a shuttle
            <span className="dash-hint">
              Residents can book rides with RIDE, guards can book deliveries and guest runs at the gate, and shuttle riders can sign in. Turn it off
              and all of this stops; past rides stay in the log.
            </span>
          </span>
        </label>
      </div>
      <Setting id="max_rides_per_home_per_day" label="Most rides per home per day" hint="Rides one home can book by WhatsApp or SMS in a day. Past this, the resident is asked to call the CSO. Between 2 and 200.">
        <input id="max_rides_per_home_per_day" name="max_rides_per_home_per_day" type="number" min={2} max={200} className="dash-input" defaultValue={s.max_rides_per_home_per_day} required />
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
