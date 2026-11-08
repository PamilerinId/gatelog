import type { Metadata } from "next";
import Link from "next/link";
import { getMe, load } from "@/app/(dashboard)/_lib/api";
import type { ZoneNode } from "@/app/(dashboard)/_lib/types";
import { ActionForm } from "@/app/(dashboard)/_components/ActionForm";
import { ConfirmButton } from "@/app/(dashboard)/_components/ConfirmButton";
import { InlineEdit } from "@/app/(dashboard)/_components/InlineEdit";
import { ApiError, Empty, PageHead } from "@/app/(dashboard)/_components/ui";
import { createHome, createStreet, createZone, deleteHome, deleteStreet, deleteZone, renameHome, renameStreet, renameZone } from "../actions";

export const metadata: Metadata = { title: "Register" };

function plural(n: number, one: string, many = `${one}s`) {
  return `${n} ${n === 1 ? one : many}`;
}

export default async function RegisterPage() {
  const [me, r] = await Promise.all([getMe(), load<ZoneNode[]>("/v1/admin/register")]);
  const admin = me.role === "admin";

  return (
    <>
      <PageHead
        title="Register"
        actions={
          admin ? (
            <Link href="/dashboard/import" className="dash-btn dash-btn--ghost">
              Import from a spreadsheet
            </Link>
          ) : undefined
        }
      >
        Every home in the estate, by zone and street. Open a home to see its residents and their numbers.
      </PageHead>

      {!r.ok ? (
        <ApiError error={r.error} />
      ) : (
        <>
          {admin && (
            <ActionForm action={createZone} className="dash-inline-form dash-add" submit="Add zone" submitClass="dash-btn dash-btn--primary dash-btn--sm">
              <label htmlFor="new-zone" className="dash-inline-label">
                New zone or block
              </label>
              <input id="new-zone" name="name" className="dash-input dash-input--sm" placeholder="For example, Block A" required maxLength={120} />
            </ActionForm>
          )}

          {r.data.length === 0 && (
            <Empty title="No zones yet">
              {admin ? "Add your first zone above, or import your register from a spreadsheet." : "An estate admin has not set up the register yet."}
            </Empty>
          )}

          <div className="dash-tree">
            {r.data.map((z) => {
              const homes = z.streets.reduce((n, st) => n + st.homes.length, 0);
              return (
                <section key={z.id} className="dash-zone" aria-labelledby={`zone-${z.id}`}>
                  <div className="dash-zone__head">
                    <h2 className="dash-h2" id={`zone-${z.id}`}>
                      {z.name}
                    </h2>
                    <span className="dash-muted dash-small">
                      {plural(z.streets.length, "street")}, {plural(homes, "home")}
                    </span>
                    {admin && (
                      <span className="dash-row-actions">
                        <InlineEdit action={renameZone} hidden={{ id: z.id }} name="name" value={z.name} label={`New name for ${z.name}`} />
                        {z.streets.length === 0 && (
                          <ConfirmButton action={deleteZone} hidden={{ id: z.id }} label="Delete" title={`Delete ${z.name}?`} confirmLabel="Delete zone">
                            <p>This zone has no streets.</p>
                          </ConfirmButton>
                        )}
                      </span>
                    )}
                  </div>

                  {z.streets.length === 0 && <p className="dash-muted dash-small dash-indent">No streets in this zone yet.</p>}

                  {z.streets.map((st) => (
                    <div key={st.id} className="dash-street">
                      <div className="dash-street__head">
                        <h3 className="dash-h3">{st.name}</h3>
                        <span className="dash-muted dash-small">{plural(st.homes.length, "home")}</span>
                        {admin && (
                          <span className="dash-row-actions">
                            <InlineEdit action={renameStreet} hidden={{ id: st.id }} name="name" value={st.name} label={`New name for ${st.name}`} />
                            {st.homes.length === 0 && (
                              <ConfirmButton action={deleteStreet} hidden={{ id: st.id }} label="Delete" title={`Delete ${st.name}?`} confirmLabel="Delete street">
                                <p>This street has no homes.</p>
                              </ConfirmButton>
                            )}
                          </span>
                        )}
                      </div>

                      {st.homes.length > 0 ? (
                        <ul className="dash-homes">
                          {st.homes.map((h) => (
                            <li key={h.id} className="dash-home">
                              <Link href={`/dashboard/register/homes/${h.id}`} className="dash-home__link">
                                <span className="dash-home__label">{h.label}</span>
                                <span className="dash-muted dash-small">{plural(h.residents, "resident")}</span>
                              </Link>
                              {admin && (
                                <span className="dash-row-actions">
                                  <InlineEdit action={renameHome} hidden={{ id: h.id }} name="label" value={h.label} label={`New label for ${h.label}`} maxLength={40} />
                                  {h.residents === 0 && (
                                    <ConfirmButton action={deleteHome} hidden={{ id: h.id }} label="Delete" title={`Delete ${h.address}?`} confirmLabel="Delete home">
                                      <p>A home with gate history cannot be deleted.</p>
                                    </ConfirmButton>
                                  )}
                                </span>
                              )}
                            </li>
                          ))}
                        </ul>
                      ) : (
                        <p className="dash-muted dash-small">No homes on this street yet.</p>
                      )}

                      {admin && (
                        <ActionForm action={createHome} hidden={{ street_id: st.id }} className="dash-inline-form" submit="Add home" submitClass="dash-btn dash-btn--ghost dash-btn--sm">
                          <label htmlFor={`home-${st.id}`} className="sr-only">
                            New home on {st.name}
                          </label>
                          <input id={`home-${st.id}`} name="label" className="dash-input dash-input--sm dash-input--short" placeholder="House, e.g. 14B" required maxLength={40} />
                        </ActionForm>
                      )}
                    </div>
                  ))}

                  {admin && (
                    <ActionForm action={createStreet} hidden={{ zone_id: z.id }} className="dash-inline-form dash-indent" submit="Add street" submitClass="dash-btn dash-btn--ghost dash-btn--sm">
                      <label htmlFor={`street-${z.id}`} className="sr-only">
                        New street in {z.name}
                      </label>
                      <input id={`street-${z.id}`} name="name" className="dash-input dash-input--sm" placeholder="New street, close or court" required maxLength={120} />
                    </ActionForm>
                  )}
                </section>
              );
            })}
          </div>
        </>
      )}
    </>
  );
}
