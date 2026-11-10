import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getEstate, getMe, load } from "@/app/(dashboard)/_lib/api";
import { CONTACT, RELATION, fmtDate } from "@/app/(dashboard)/_lib/format";
import type { HomeDetail, Relation, Resident, ResidentCard } from "@/app/(dashboard)/_lib/types";
import { ActionForm } from "@/app/(dashboard)/_components/ActionForm";
import { ConfirmButton } from "@/app/(dashboard)/_components/ConfirmButton";
import { ApiError, Badge, Empty, PageHead, Section } from "@/app/(dashboard)/_components/ui";
import { addNumber, createResident, createVehicle, deleteHome, deleteNumber, deleteVehicle, revokeCard, setLevyPayer, updateResident } from "../../../actions";
import { HouseCodeButton } from "./HouseCode";

export const metadata: Metadata = { title: "Home" };

const MAX_NUMBERS = 3;

export default async function HomePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();
  const [me, r, estate] = await Promise.all([getMe(), load<HomeDetail>(`/v1/admin/homes/${id}`), getEstate()]);
  const shuttle = estate.ok && estate.data.settings.shuttle_enabled;
  const cards = shuttle ? await load<ResidentCard[]>(`/v1/admin/cards?home_id=${id}`) : null;
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
        <>
          <HomeView home={r.data} admin={admin} seesLevy={seesLevy} shuttle={shuttle} />
          {shuttle && <ShuttleSection admin={admin} cards={cards} />}
        </>
      )}
    </>
  );
}

function HomeView({ home, admin, seesLevy, shuttle }: { home: HomeDetail; admin: boolean; seesLevy: boolean; shuttle: boolean }) {
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

      <HomePin home={home} admin={admin} shuttle={shuttle} />

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
            <li key={n.id} className={n.pending ? "dash-number--pending" : undefined}>
              <span className="tnum dash-number">{n.masked}</span>
              {n.pending ? (
                <>
                  <Badge tone="warn">Waiting for the home to confirm</Badge>
                  <span className="dash-hint">Offered at the gate. It works only after someone in the home replies YES.</span>
                </>
              ) : (
                <>
                  {n.is_primary && <Badge>Main</Badge>}
                  {n.verified_at ? <Badge tone="ok">Confirmed</Badge> : <Badge>Not confirmed yet</Badge>}
                </>
              )}
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

function ShuttleSection({
  admin,
  cards,
}: {
  admin: boolean;
  cards: { ok: true; data: ResidentCard[] } | { ok: false; error: string } | null;
}) {
  return (
    <Section title="Shuttle: estate cards" id="shuttle">
      <p className="dash-muted dash-small">
        Riders record who they carried with a resident&rsquo;s estate card or the home PIN. The CSO issues cards on a gate phone. A card only
        identifies the resident; it cannot pay for anything.
      </p>
      {!cards ? null : !cards.ok ? (
        <ApiError error={cards.error} />
      ) : cards.data.length === 0 ? (
        <p className="dash-muted dash-small">No estate cards issued for this home.</p>
      ) : (
        <div className="dash-table-wrap">
          <table className="dash-table dash-table--stack">
            <thead>
              <tr>
                <th scope="col">Resident</th>
                <th scope="col">Card</th>
                <th scope="col">Issued</th>
                <th scope="col">Status</th>
              </tr>
            </thead>
            <tbody>
              {cards.data.map((c) => (
                <tr key={c.id}>
                  <td data-label="Resident">{c.resident ?? <span className="dash-muted">Unknown</span>}</td>
                  <td data-label="Card" className="tnum">
                    Ends {c.uid_last4}
                  </td>
                  <td data-label="Issued">
                    <span className="tnum">{fmtDate(c.issued_at)}</span>
                    {c.issued_by && <span className="dash-hint">By {c.issued_by}</span>}
                  </td>
                  <td data-label="Status">
                    <span className="dash-row-actions">
                      {c.revoked_at ? (
                        <>
                          <Badge tone="bad">Revoked</Badge>
                          <span className="dash-hint">{fmtDate(c.revoked_at)}</span>
                        </>
                      ) : (
                        <Badge tone="ok">Working</Badge>
                      )}
                      {admin && !c.revoked_at && (
                        <ConfirmButton action={revokeCard} hidden={{ id: c.id }} label="Revoke" title={`Revoke the card ending ${c.uid_last4}?`} confirmLabel="Revoke card">
                          <p>Use this when a card is lost or the resident has moved out.</p>
                          <ul>
                            <li>It stops identifying {c.resident ?? "the resident"} when each rider phone next syncs.</li>
                            <li>A revoked card cannot be turned back on. The CSO can issue a new one.</li>
                          </ul>
                        </ConfirmButton>
                      )}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Section>
  );
}

function HomePin({ home, admin, shuttle }: { home: HomeDetail; admin: boolean; shuttle: boolean }) {
  return (
    <Section title="Home PIN" id="home-pin" aside={admin ? <HouseCodeButton homeId={home.id} address={home.address} /> : undefined}>
      <p className="dash-muted dash-small">
        A 4-digit PIN for the home, for the resident&rsquo;s printed card. A caller who rings the gate about a guest and gives it is let in as
        PIN verified{shuttle ? ", and a shuttle rider can use it to record who rode" : ""}. Residents can also get it by sending HOME PIN from a
        registered number. Gatelog never shows it again after it is made.
      </p>
    </Section>
  );
}
