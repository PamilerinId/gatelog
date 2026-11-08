import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getMe, load } from "@/app/(dashboard)/_lib/api";
import { CONTACT, RELATION } from "@/app/(dashboard)/_lib/format";
import type { HomeDetail, Relation, Resident } from "@/app/(dashboard)/_lib/types";
import { ActionForm } from "@/app/(dashboard)/_components/ActionForm";
import { ConfirmButton } from "@/app/(dashboard)/_components/ConfirmButton";
import { ApiError, Badge, Empty, PageHead, Section } from "@/app/(dashboard)/_components/ui";
import { addNumber, createResident, createVehicle, deleteHome, deleteNumber, deleteVehicle, setLevyPayer, updateResident } from "../../../actions";

export const metadata: Metadata = { title: "Home" };

const MAX_NUMBERS = 3;

export default async function HomePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();
  const [me, r] = await Promise.all([getMe(), load<HomeDetail>(`/v1/admin/homes/${id}`)]);
  const admin = me.role === "admin";
  // Who owes the levy is dues information: the Exco and the treasurer only (spec, dues privacy).
  const seesLevy = admin || me.role === "committee" || me.role === "treasurer";
  if (!r.ok && r.status === 404) notFound();

  return (
    <>
      <p className="dash-crumbs">
        <Link href="/dashboard/register">Register</Link> <span aria-hidden="true">/</span> {r.ok ? r.data.label : "Home"}
      </p>
      {!r.ok ? (
        <>
          <PageHead title="Home" />
          <ApiError error={r.error} />
        </>
      ) : (
        <HomeView home={r.data} admin={admin} seesLevy={seesLevy} />
      )}
    </>
  );
}

function HomeView({ home, admin, seesLevy }: { home: HomeDetail; admin: boolean; seesLevy: boolean }) {
  const used = home.residents.reduce((n, r) => n + r.numbers.length, 0);
  return (
    <>
      <PageHead
        title={home.address}
        actions={
          admin && home.residents.length === 0 ? (
            <ConfirmButton
              action={deleteHome}
              hidden={{ id: home.id, then: "register" }}
              label="Delete home"
              buttonClass="dash-btn dash-btn--ghost dash-btn--sm"
              title={`Delete ${home.address}?`}
              confirmLabel="Delete home"
            >
              <p>A home with gate history cannot be deleted.</p>
            </ConfirmButton>
          ) : undefined
        }
      >
        {home.residents.length} {home.residents.length === 1 ? "resident" : "residents"}. {used} of {MAX_NUMBERS} phone numbers used. Only
        registered numbers can announce guests or confirm callbacks.
      </PageHead>

      {seesLevy && <LevyPayer home={home} admin={admin} />}

      {home.residents.length === 0 && (
        <Empty title="Nobody registered here yet">{admin ? "Add the first resident below." : "An estate admin can add residents."}</Empty>
      )}

      <div className="dash-cards">
        {home.residents.map((r) => (
          <ResidentCard key={r.id} r={r} admin={admin} full={used >= MAX_NUMBERS} />
        ))}
      </div>

      {admin && (
        <details className="dash-details" open={home.residents.length === 0}>
          <summary>Add a resident</summary>
          <ActionForm action={createResident} hidden={{ home_id: home.id }} submit="Add resident">
            <div className="dash-grid2">
              <div className="dash-field">
                <label htmlFor="new-name">Full name</label>
                <input id="new-name" name="name" className="dash-input" required minLength={2} maxLength={120} />
              </div>
              <RelationField id="new-relation" />
              <div className="dash-field">
                <label htmlFor="new-pref">Prefers to be reached by</label>
                <select id="new-pref" name="contact_pref" className="dash-input" defaultValue="whatsapp">
                  <option value="whatsapp">WhatsApp</option>
                  <option value="sms">SMS</option>
                  <option value="call">Phone call</option>
                </select>
              </div>
              <div className="dash-field">
                <label htmlFor="new-number">Phone number (optional)</label>
                <input id="new-number" name="number" className="dash-input" inputMode="tel" autoComplete="off" placeholder="0803 123 4567" disabled={used >= MAX_NUMBERS} />
                {used >= MAX_NUMBERS && <span className="dash-hint">This home already has {MAX_NUMBERS} numbers.</span>}
              </div>
            </div>
            <Check name="callback_required" label="Callback required" hint="The gate calls this resident to confirm every guest, even one with a code." />
            <Check name="exit_notices" label="Tell them when guests leave" />
          </ActionForm>
        </details>
      )}

      <Vehicles home={home} admin={admin} />
    </>
  );
}

function RelationField({ id, value = "occupant" }: { id: string; value?: Relation }) {
  return (
    <div className="dash-field">
      <label htmlFor={id}>Landlord or occupant</label>
      <select id={id} name="relation" className="dash-input" defaultValue={value}>
        <option value="occupant">Occupant: lives here</option>
        <option value="landlord">Landlord: owns the home</option>
      </select>
    </div>
  );
}

function LevyPayer({ home, admin }: { home: HomeDetail; admin: boolean }) {
  return (
    <Section title="Who owes the levy" id="levy">
      {admin ? (
        <ActionForm action={setLevyPayer} hidden={{ id: home.id }} reset={false} className="dash-inline-form" submit="Save" submitClass="dash-btn dash-btn--ghost dash-btn--sm">
          <label htmlFor="levy-payer" className="sr-only">
            Who owes the levy
          </label>
          <select id="levy-payer" name="levy_payer" className="dash-input dash-input--sm" defaultValue={home.levy_payer}>
            <option value="landlord">Landlord</option>
            <option value="occupant">Occupant</option>
          </select>
        </ActionForm>
      ) : (
        <p>{RELATION[home.levy_payer]}</p>
      )}
      <p className="dash-hint">The association decides this, not Gatelog. It is shown to the Exco and treasurer only and never reaches the gate.</p>
    </Section>
  );
}

function Vehicles({ home, admin }: { home: HomeDetail; admin: boolean }) {
  return (
    <Section title="Vehicles" id="vehicles">
      <p className="dash-muted dash-small">The gate phone shows the guard a match when one of these plates is typed in. Plates are used only for the estate&rsquo;s own log.</p>
      {home.vehicles.length === 0 ? (
        <p className="dash-muted dash-small">No vehicles registered to this home.</p>
      ) : (
        <ul className="dash-rows">
          {home.vehicles.map((v) => (
            <li key={v.id} className="dash-rows__item">
              <span className="dash-rows__main">
                <span className="dash-plate">{v.plate}</span>
                {v.description && <span className="dash-hint">{v.description}</span>}
              </span>
              {admin && (
                <ConfirmButton action={deleteVehicle} hidden={{ id: v.id }} label="Remove" title={`Remove ${v.plate}?`} confirmLabel="Remove vehicle">
                  <p>The gate will no longer show this plate as belonging to {home.address}. Past entries keep the plate they were logged with.</p>
                </ConfirmButton>
              )}
            </li>
          ))}
        </ul>
      )}
      {admin && (
        <details className="dash-details">
          <summary>Add a vehicle</summary>
          <ActionForm action={createVehicle} hidden={{ home_id: home.id }} submit="Add vehicle">
            <div className="dash-grid2">
              <div className="dash-field">
                <label htmlFor="new-plate">Plate number</label>
                <input
                  id="new-plate"
                  name="plate"
                  className="dash-input"
                  required
                  minLength={3}
                  maxLength={20}
                  autoComplete="off"
                  autoCapitalize="characters"
                  spellCheck={false}
                  placeholder="KJA 456 XY"
                />
                <span className="dash-hint">Saved in capitals with no spaces, so KJA 456 XY becomes KJA456XY.</span>
              </div>
              <div className="dash-field">
                <label htmlFor="new-desc">Description (optional)</label>
                <input id="new-desc" name="description" className="dash-input" maxLength={80} placeholder="Black Toyota Corolla" />
              </div>
            </div>
          </ActionForm>
        </details>
      )}
    </Section>
  );
}

function Check({ name, label, hint, defaultChecked }: { name: string; label: string; hint?: string; defaultChecked?: boolean }) {
  return (
    <label className="dash-check">
      <input type="checkbox" name={name} defaultChecked={defaultChecked} />
      <span>
        {label}
        {hint && <span className="dash-hint">{hint}</span>}
      </span>
    </label>
  );
}

function ResidentCard({ r, admin, full }: { r: Resident; admin: boolean; full: boolean }) {
  return (
    <article className="dash-card dash-resident">
      <div className="dash-resident__head">
        <h2 className="dash-h3">{r.name}</h2>
        <div className="dash-badges">
          <Badge tone={r.relation === "landlord" ? "info" : "plain"}>{RELATION[r.relation]}</Badge>
          <Badge>Prefers {CONTACT[r.contact_pref]}</Badge>
          {r.callback_required && <Badge tone="info">Callback required</Badge>}
          {r.exit_notices && <Badge>Told when guests leave</Badge>}
          {!r.active && <Badge tone="warn">Inactive</Badge>}
        </div>
      </div>

      {r.numbers.length === 0 ? (
        <p className="dash-muted dash-small">No phone number yet. Without one, this resident cannot announce guests.</p>
      ) : (
        <ul className="dash-numbers">
          {r.numbers.map((n) => (
            <li key={n.id}>
              <span className="tnum dash-number">{n.masked}</span>
              {n.is_primary && <Badge>Main</Badge>}
              {n.verified_at ? <Badge tone="ok">Confirmed</Badge> : <Badge>Not confirmed yet</Badge>}
              {admin && (
                <ConfirmButton action={deleteNumber} hidden={{ id: n.id }} label="Remove" title={`Remove ${n.masked}?`} confirmLabel="Remove number">
                  <p>This number will no longer be able to announce guests or confirm callbacks for this home.</p>
                </ConfirmButton>
              )}
            </li>
          ))}
        </ul>
      )}

      {admin && (
        <div className="dash-resident__tools">
          <details className="dash-details dash-details--inline">
            <summary>Add a number</summary>
            <ActionForm action={addNumber} hidden={{ resident_id: r.id }} className="dash-form" submit="Add number" submitClass="dash-btn dash-btn--primary dash-btn--sm">
              {full && <p className="dash-hint">This home already has 3 numbers. Remove one first.</p>}
              <div className="dash-field">
                <label htmlFor={`num-${r.id}`}>Phone number</label>
                <input id={`num-${r.id}`} name="number" className="dash-input" inputMode="tel" autoComplete="off" placeholder="0803 123 4567" required />
              </div>
              <Check name="is_primary" label="Make this the main number" />
            </ActionForm>
          </details>

          <details className="dash-details dash-details--inline">
            <summary>Edit resident</summary>
            <ActionForm action={updateResident} hidden={{ id: r.id }} reset={false} submit="Save" submitClass="dash-btn dash-btn--primary dash-btn--sm">
              <div className="dash-field">
                <label htmlFor={`name-${r.id}`}>Full name</label>
                <input id={`name-${r.id}`} name="name" className="dash-input" defaultValue={r.name} required minLength={2} maxLength={120} />
              </div>
              <RelationField id={`relation-${r.id}`} value={r.relation} />
              <div className="dash-field">
                <label htmlFor={`pref-${r.id}`}>Prefers to be reached by</label>
                <select id={`pref-${r.id}`} name="contact_pref" className="dash-input" defaultValue={r.contact_pref}>
                  <option value="whatsapp">WhatsApp</option>
                  <option value="sms">SMS</option>
                  <option value="call">Phone call</option>
                </select>
              </div>
              <Check name="callback_required" label="Callback required" defaultChecked={r.callback_required} hint="The gate calls this resident to confirm every guest." />
              <Check name="exit_notices" label="Tell them when guests leave" defaultChecked={r.exit_notices} />
              <Check name="active" label="Active" defaultChecked={r.active} hint="Untick when someone moves out." />
            </ActionForm>
          </details>
        </div>
      )}
    </article>
  );
}
