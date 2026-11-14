import { GUARD_ROLE, fmtDate } from "@/app/(dashboard)/_lib/format";
import type { Guard } from "@/app/(dashboard)/_lib/types";
import { ActionForm } from "@/app/(dashboard)/_components/ActionForm";
import { ConfirmButton } from "@/app/(dashboard)/_components/ConfirmButton";
import { More } from "@/app/(dashboard)/_components/ui";
import { resetGuardPin, setGuardActive, updateGuard } from "../actions";

// Guard cards: name, role, consent and PIN in plain words. The estate admin gets one "Change" per
// card for changes; the security head gets "Change" with only Reset PIN; everyone else reads.

export function RoleField({ id, value = "guard", shuttle }: { id: string; value?: string; shuttle: boolean }) {
  return (
    <div className="dash-field">
      <label htmlFor={id}>Job</label>
      <select id={id} name="role" className="dash-input" defaultValue={value}>
        <option value="guard">Guard</option>
        <option value="cso">CSO (chief security officer)</option>
        {(shuttle || value === "rider") && <option value="rider">Shuttle rider</option>}
      </select>
      <span className="dash-hint">
        The CSO signs in on a gate phone like any guard and also gets the CSO view.
        {shuttle && " A shuttle rider gets the rider view; their position is shared only while their shift is open."}
      </span>
    </div>
  );
}

export function ConsentCheck({ checked }: { checked?: boolean }) {
  return (
    <label className="dash-check">
      <input type="checkbox" name="consent_recorded" defaultChecked={checked} />
      <span>
        Written consent recorded
        <span className="dash-hint">Tick this once they have signed the consent to shift selfies. Their shift will not start until it is ticked.</span>
      </span>
    </label>
  );
}

/** `canResetPin`: the security head, who may reset a forgotten PIN (audited) but changes nothing else. */
export function GuardCard({ g, admin, shuttle, canResetPin = false }: { g: Guard; admin: boolean; shuttle: boolean; canResetPin?: boolean }) {
  const resetPin = g.pin_set && g.active && (admin || canResetPin) && (
    <ConfirmButton action={resetGuardPin} hidden={{ id: g.id }} label="Reset PIN" title={`Reset ${g.name}'s PIN?`} confirmLabel="Reset PIN" danger={false}>
      <p>Use this when they have forgotten their PIN.</p>
      <ul>
        <li>Their old PIN stops working once the gate phones next sync.</li>
        <li>They choose a new PIN on the gate phone at their next shift. Nobody else ever sees it.</li>
        <li>The reset is recorded with your name.</li>
      </ul>
    </ConfirmButton>
  );
  return (
    <li className={`dash-personcard${g.active ? "" : " is-off"}`} id={`guard-${g.id}`}>
      <div className="dash-personcard__top">
        <span className="dash-personcard__name">{g.name}</span>
        {!admin && resetPin && <More label="Change">{resetPin}</More>}
        {admin && (
          <More label="Change">
            <details className="dash-details dash-details--inline">
              <summary>Job and consent</summary>
              <ActionForm action={updateGuard} hidden={{ id: g.id }} reset={false} submit="Save" submitClass="dash-btn dash-btn--primary dash-btn--sm">
                <RoleField id={`role-${g.id}`} value={g.role} shuttle={shuttle} />
                <ConsentCheck checked={g.consent_at != null} />
              </ActionForm>
            </details>
            {resetPin}
            {g.active ? (
              <ConfirmButton action={setGuardActive} hidden={{ id: g.id, active: "false" }} label="Stop their access" title={`Stop ${g.name}'s access?`} confirmLabel="Stop access">
                <p>They will no longer appear on the gate phones. Their past entries and shifts stay in the log.</p>
              </ConfirmButton>
            ) : (
              <ActionForm action={setGuardActive} hidden={{ id: g.id, active: "true" }} className="dash-inline-form" submit="Give access back" submitClass="dash-btn dash-btn--quiet dash-btn--sm" showMessage={false} />
            )}
          </More>
        )}
      </div>
      <span className="dash-personcard__role">{GUARD_ROLE[g.role]}{g.active ? "" : " · no access"}</span>
      <span className={`dash-personcard__fact${g.consent_at ? "" : " dash-warn-text"}`}>
        {g.consent_at ? `Consent form ✓ ${fmtDate(g.consent_at)}` : "No consent form recorded"}
      </span>
      <span className="dash-personcard__fact">{g.pin_set ? "PIN set ✓" : "PIN not set yet: chosen at their next shift"}</span>
    </li>
  );
}
