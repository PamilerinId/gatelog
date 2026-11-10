import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getEstate, getMe, load } from "@/app/(dashboard)/_lib/api";
import { CONTACT, RELATION, fmtDate } from "@/app/(dashboard)/_lib/format";
import { canOpen } from "@/app/(dashboard)/_lib/roles";
import type { HomeDetail, Relation, Resident, ResidentCard } from "@/app/(dashboard)/_lib/types";
import { ActionForm } from "@/app/(dashboard)/_components/ActionForm";
import { ConfirmButton } from "@/app/(dashboard)/_components/ConfirmButton";
import { InlineEdit } from "@/app/(dashboard)/_components/InlineEdit";
import { ApiError, Badge, Fold, More, NotForRole } from "@/app/(dashboard)/_components/ui";
import {
  addNumber,
  createResident,
  createVehicle,
  deleteHome,
  deleteNumber,
  deleteVehicle,
  renameHome,
  revokeCard,
  setLevyPayer,
  updateResident,
} from "../../../actions";
import { HouseCodeButton } from "./HouseCode";

export const metadata: Metadata = { title: "Home" };

const MAX_NUMBERS = 3;

// One home, for the estate office. Each part stays folded with a one-line summary until opened.

export default async function HomePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();
  const me = await getMe();
  if (!canOpen(me.role, "register")) return <NotForRole title="Home" />;
  const [r, estate] = await Promise.all([load<HomeDetail>(`/v1/admin/homes/${id}`), getEstate()]);
  if (!r.ok && r.status === 404) notFound();
  const shuttle = estate.ok && estate.data.settings.shuttle_enabled;
  const cards = shuttle ? await load<ResidentCard[]>(`/v1/admin/cards?home_id=${id}`) : null;

  return (
    <>
      <p className="dash-crumbs">
        <Link href="/dashboard/register">Homes</Link> <span aria-hidden="true">/</span> {r.ok ? r.data.label : "Home"}
      </p>
      {!r.ok ? <ApiError error={r.error} /> : <HomeView home={r.data} shuttle={shuttle} cards={cards} />}
    </>
  );
}

type CardsResult = { ok: true; data: ResidentCard[] } | { ok: false; error: string } | null;

function HomeView({ home, shuttle, cards }: { home: HomeDetail; shuttle: boolean; cards: CardsResult }) {
  const numbers = home.residents.flatMap((r) => r.numbers);
  const working = numbers.filter((n) => !n.pending).length;
  const pending = numbers.length - working;
  const live = cards?.ok ? cards.data.filter((c) => !c.revoked_at).length : 0;

  return (
    <>
      <header className="dash-head">
        <div>
          <p className="dash-homehead__no tnum">{home.label}</p>
          <h1 className="dash-h1">{home.address}</h1>
        </div>
        <div className="dash-head__actions">
          <More>
            <InlineEdit action={renameHome} hidden={{ id: home.id }} name="label" value={home.label} label="New house number" buttonLabel="Change the house number" maxLength={40} />
            {home.residents.length === 0 ? (
              <ConfirmButton action={deleteHome} hidden={{ id: home.id, then: "register" }} label="Delete this home" title={`Delete ${home.address}?`} confirmLabel="Delete home">
                <p>A home with gate history cannot be deleted.</p>
              </ConfirmButton>
            ) : (
              <span className="dash-hint">A home with residents cannot be deleted.</span>
            )}
          </More>
        </div>
      </header>

      <div className="dash-folds">
        <Fold
          title="Who lives here"
          open={home.residents.length === 0}
          tone={working === 0 ? "warn" : undefined}
          status={
            home.residents.length === 0
              ? "Nobody registered"
              : `${home.residents.length} ${home.residents.length === 1 ? "person" : "people"} · ${working === 0 ? "no number" : `${working} ${working === 1 ? "number" : "numbers"}`}${pending ? ` · ${pending} waiting` : ""}`
          }
        >
          <p className="dash-muted dash-small">
            Only registered numbers can announce guests or confirm callbacks. A home can have {MAX_NUMBERS} numbers. {numbers.length} used.
          </p>
          <div className="dash-cards">
            {home.residents.map((r) => (
              <ResidentCardView key={r.id} r={r} full={numbers.length >= MAX_NUMBERS} />
            ))}
          </div>
          <details className="dash-details">
            <summary>Add a resident</summary>
            <ActionForm action={createResident} hidden={{ home_id: home.id }} submit="Add resident">
              <div className="dash-grid2">
                <div className="dash-field">
                  <label htmlFor="new-name">Full name</label>
                  <input id="new-name" name="name" className="dash-input" required minLength={2} maxLength={120} />
                </div>
                <RelationField id="new-relation" />
                <ContactField id="new-pref" />
                <div className="dash-field">
                  <label htmlFor="new-number">Phone number (optional)</label>
                  <input id="new-number" name="number" className="dash-input" inputMode="tel" autoComplete="off" placeholder="0803 123 4567" disabled={numbers.length >= MAX_NUMBERS} />
                  {numbers.length >= MAX_NUMBERS && <span className="dash-hint">This home already has {MAX_NUMBERS} numbers.</span>}
                </div>
              </div>
              <Check name="callback_required" label="Call them to confirm every guest" hint="The gate calls this resident to confirm every guest, even one with a code." />
              <Check name="exit_notices" label="Tell them when guests leave" />
            </ActionForm>
          </details>
        </Fold>

        <Fold title="Home PIN" status="For the resident's printed card">
          <p className="dash-small">
            A 4-digit PIN for the home. A caller who rings the gate about a guest and gives it is let in as PIN verified
            {shuttle ? ", and a shuttle rider can use it to record who rode" : ""}. Residents can also get it by sending HOME PIN from a registered
            number. Gatelog never shows it again after it is made.
          </p>
          <HouseCodeButton homeId={home.id} address={home.address} />
        </Fold>

        <Fold title="Vehicles" status={home.vehicles.length === 0 ? "None" : `${home.vehicles.length} ${home.vehicles.length === 1 ? "vehicle" : "vehicles"}`}>
          <p className="dash-muted dash-small">The gate phone shows the guard a match when one of these plates is typed in. Used only for the estate&rsquo;s own log.</p>
          {home.vehicles.length > 0 && (
            <ul className="dash-plainlist">
              {home.vehicles.map((v) => (
                <li key={v.id} className="dash-plainlist__item">
                  <span className="dash-plainlist__main">
                    <span className="dash-plate">{v.plate}</span>
                    {v.description && <span className="dash-hint">{v.description}</span>}
                  </span>
                  <ConfirmButton action={deleteVehicle} hidden={{ id: v.id }} label="Remove" title={`Remove ${v.plate}?`} confirmLabel="Remove vehicle">
                    <p>The gate will no longer show this plate as belonging to {home.address}. Past entries keep the plate they were logged with.</p>
                  </ConfirmButton>
                </li>
              ))}
            </ul>
          )}
          <details className="dash-details">
            <summary>Add a vehicle</summary>
            <ActionForm action={createVehicle} hidden={{ home_id: home.id }} submit="Add vehicle">
              <div className="dash-grid2">
                <div className="dash-field">
                  <label htmlFor="new-plate">Plate number</label>
                  <input id="new-plate" name="plate" className="dash-input" required minLength={3} maxLength={20} autoComplete="off" autoCapitalize="characters" spellCheck={false} placeholder="KJA 456 XY" />
                  <span className="dash-hint">Saved in capitals with no spaces, so KJA 456 XY becomes KJA456XY.</span>
                </div>
                <div className="dash-field">
                  <label htmlFor="new-desc">Description (optional)</label>
                  <input id="new-desc" name="description" className="dash-input" maxLength={80} placeholder="Black Toyota Corolla" />
                </div>
              </div>
            </ActionForm>
          </details>
        </Fold>

        {shuttle && (
          <Fold title="Estate cards" status={cards?.ok ? (live ? `${live} working` : "None issued") : undefined}>
            <EstateCards cards={cards} />
          </Fold>
        )}

        <Fold title="Who owes the levy" status={RELATION[home.levy_payer]}>
          <ActionForm action={setLevyPayer} hidden={{ id: home.id }} reset={false} className="dash-inline-form" submit="Save" submitClass="dash-btn dash-btn--ghost dash-btn--sm">
            <label htmlFor="levy-payer" className="sr-only">
              Who owes the levy
            </label>
            <select id="levy-payer" name="levy_payer" className="dash-input dash-input--sm" defaultValue={home.levy_payer}>
              <option value="landlord">Landlord</option>
              <option value="occupant">Occupant</option>
            </select>
          </ActionForm>
          <p className="dash-hint">The association decides this, not Gatelog. It is shown to the Exco and treasurer only and never reaches the gate.</p>
        </Fold>
      </div>
    </>
  );
}

function EstateCards({ cards }: { cards: CardsResult }) {
  if (!cards) return null;
  if (!cards.ok) return <ApiError error={cards.error} />;
  return (
    <>
      <p className="dash-muted dash-small">
        Riders record who they carried with a resident&rsquo;s estate card or the home PIN. The CSO issues cards on a gate phone. A card only
        identifies the resident; it cannot pay for anything.
      </p>
      {cards.data.length === 0 ? (
        <p className="dash-muted dash-small">No estate cards issued for this home.</p>
      ) : (
        <ul className="dash-plainlist">
          {cards.data.map((c) => (
            <li key={c.id} className="dash-plainlist__item">
              <span className="dash-plainlist__main">
                {c.resident ?? "Unknown resident"} <span className="tnum">· card ending {c.uid_last4}</span>
                <span className="dash-hint">
                  Issued {fmtDate(c.issued_at)}
                  {c.issued_by ? ` by ${c.issued_by}` : ""}
                  {c.revoked_at ? `. Revoked ${fmtDate(c.revoked_at)}.` : ""}
                </span>
              </span>
              {c.revoked_at ? (
                <Badge tone="bad">Revoked</Badge>
              ) : (
                <ConfirmButton action={revokeCard} hidden={{ id: c.id }} label="Revoke" title={`Revoke the card ending ${c.uid_last4}?`} confirmLabel="Revoke card">
                  <p>Use this when a card is lost or the resident has moved out.</p>
                  <ul>
                    <li>It stops identifying {c.resident ?? "the resident"} when each rider phone next syncs.</li>
                    <li>A revoked card cannot be turned back on. The CSO can issue a new one.</li>
                  </ul>
                </ConfirmButton>
              )}
            </li>
          ))}
        </ul>
      )}
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

function ContactField({ id, value = "whatsapp" }: { id: string; value?: string }) {
  return (
    <div className="dash-field">
      <label htmlFor={id}>Prefers to be reached by</label>
      <select id={id} name="contact_pref" className="dash-input" defaultValue={value}>
        <option value="whatsapp">WhatsApp</option>
        <option value="sms">SMS</option>
        <option value="call">Phone call</option>
      </select>
    </div>
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

function ResidentCardView({ r, full }: { r: Resident; full: boolean }) {
  return (
    <article className="dash-card dash-resident">
      <div className="dash-resident__head">
        <h3 className="dash-h3">{r.name}</h3>
        <More label="Change">
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
            <summary>Edit {r.name.split(" ")[0]}</summary>
            <ActionForm action={updateResident} hidden={{ id: r.id }} reset={false} submit="Save" submitClass="dash-btn dash-btn--primary dash-btn--sm">
              <div className="dash-field">
                <label htmlFor={`name-${r.id}`}>Full name</label>
                <input id={`name-${r.id}`} name="name" className="dash-input" defaultValue={r.name} required minLength={2} maxLength={120} />
              </div>
              <RelationField id={`relation-${r.id}`} value={r.relation} />
              <ContactField id={`pref-${r.id}`} value={r.contact_pref} />
              <Check name="callback_required" label="Call them to confirm every guest" defaultChecked={r.callback_required} />
              <Check name="exit_notices" label="Tell them when guests leave" defaultChecked={r.exit_notices} />
              <Check name="active" label="Lives here now" defaultChecked={r.active} hint="Untick when someone moves out." />
            </ActionForm>
          </details>
        </More>
      </div>
      <p className="dash-small dash-muted">
        {RELATION[r.relation]} · prefers {CONTACT[r.contact_pref]}
        {r.callback_required ? " · called to confirm every guest" : ""}
        {r.exit_notices ? " · told when guests leave" : ""}
        {!r.active ? " · moved out" : ""}
      </p>
      {r.numbers.length === 0 ? (
        <p className="dash-warn-text dash-small">No phone number yet. Without one, this resident cannot announce guests.</p>
      ) : (
        <ul className="dash-numbers">
          {r.numbers.map((n) => (
            <li key={n.id} className={n.pending ? "dash-number--pending" : undefined}>
              <span className="tnum dash-number">{n.masked}</span>
              {n.pending ? (
                <span className="dash-warn-text dash-small">Waiting for the home to confirm. It works once someone in the home replies YES.</span>
              ) : (
                <span className="dash-small dash-muted">
                  {n.is_primary ? "Main · " : ""}
                  {n.verified_at ? "confirmed ✓" : "not confirmed yet"}
                </span>
              )}
              <ConfirmButton action={deleteNumber} hidden={{ id: n.id }} label="Remove" title={`Remove ${n.masked}?`} confirmLabel="Remove number">
                <p>This number will no longer be able to announce guests or confirm callbacks for this home.</p>
              </ConfirmButton>
            </li>
          ))}
        </ul>
      )}
    </article>
  );
}
