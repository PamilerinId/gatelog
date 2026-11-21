import { ActionForm } from "@/app/(dashboard)/_components/ActionForm";
import { NG_STATES } from "@/app/(dashboard)/_lib/ng";
import { updateEstateArea } from "../actions";

/** The estate's name and where it is. The state and LGA decide which emergency numbers the estate gets. */
export function EstateArea({ name, state, lga }: { name: string; state: string; lga: string }) {
  return (
    <ActionForm action={updateEstateArea} reset={false} submit="Save name and area" className="dash-form dash-settings">
      <div className="dash-field">
        <label htmlFor="estate-name">Estate name</label>
        <input id="estate-name" name="name" className="dash-input" defaultValue={name} required minLength={2} maxLength={160} autoComplete="off" />
      </div>
      <div className="dash-field">
        <label htmlFor="estate-state">State</label>
        <select id="estate-state" name="state" className="dash-input" defaultValue={state} required>
          {!(NG_STATES as readonly string[]).includes(state) && <option value={state}>{state}</option>}
          {NG_STATES.map((s) => (
            <option key={s} value={s}>
              {s === "FCT" ? "FCT (Abuja)" : s}
            </option>
          ))}
        </select>
      </div>
      <div className="dash-field">
        <label htmlFor="estate-lga">Local government area (LGA)</label>
        <input id="estate-lga" name="lga" className="dash-input" defaultValue={lga} required minLength={2} maxLength={80} placeholder="For example, Eti-Osa" autoComplete="off" />
        <span className="dash-hint">
          The state and LGA decide which police, fire and hospital numbers the estate gets, and where the estate map opens. Spell the LGA the
          usual way, for example Eti-Osa or Ikeja.
        </span>
      </div>
    </ActionForm>
  );
}
