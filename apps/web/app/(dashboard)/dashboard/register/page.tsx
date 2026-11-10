import type { Metadata } from "next";
import Link from "next/link";
import { getMe, load } from "@/app/(dashboard)/_lib/api";
import { canOpen } from "@/app/(dashboard)/_lib/roles";
import type { Resident, Visit, ZoneNode } from "@/app/(dashboard)/_lib/types";
import { ActionForm } from "@/app/(dashboard)/_components/ActionForm";
import { ConfirmButton } from "@/app/(dashboard)/_components/ConfirmButton";
import { InlineEdit } from "@/app/(dashboard)/_components/InlineEdit";
import { ApiError, Empty, Fold, More, NotForRole, PageHead } from "@/app/(dashboard)/_components/ui";
import { createHome, createStreet, createZone, deleteStreet, deleteZone, renameStreet, renameZone } from "../actions";
import { HomeCards, type HomeCardData } from "./HomeCards";

export const metadata: Metadata = { title: "Homes" };

export default async function HomesPage({ searchParams }: { searchParams: Promise<{ show?: string }> }) {
  const me = await getMe();
  if (!canOpen(me.role, "register")) return <NotForRole title="Homes" />;
  const { show } = await searchParams;
  const [register, residents, inside] = await Promise.all([
    load<ZoneNode[]>("/v1/admin/register"),
    load<Resident[]>("/v1/admin/residents"),
    load<Visit[]>("/v1/admin/visits?state=inside"),
  ]);
  if (!register.ok)
    return (
      <>
        <PageHead title="Homes" />
        <ApiError error={register.error} />
      </>
    );

  const byHome = new Map<string, Resident[]>();
  for (const r of residents.ok ? residents.data : []) byHome.set(r.home_id, [...(byHome.get(r.home_id) ?? []), r]);
  const insideAt = new Map<string, number>();
  for (const v of inside.ok ? inside.data : []) insideAt.set(v.address, (insideAt.get(v.address) ?? 0) + 1);

  const homes: HomeCardData[] = register.data.flatMap((z) =>
    z.streets.flatMap((st) =>
      st.homes.map((h) => {
        const rs = byHome.get(h.id) ?? [];
        const main = rs.find((r) => r.numbers.some((n) => n.is_primary)) ?? rs[0];
        const nums = rs.flatMap((r) => r.numbers);
        return {
          id: h.id,
          label: h.label,
          street: st.name,
          zone: z.name,
          resident: main?.name ?? null,
          numbers: nums.filter((n) => !n.pending).length,
          pending: nums.filter((n) => n.pending).length,
          inside: insideAt.get(h.address) ?? 0,
        };
      }),
    ),
  );
  const streets = register.data.flatMap((z) => z.streets.map((st) => ({ id: st.id, name: `${st.name}, ${z.name}` })));

  return (
    <>
      <PageHead
        title="Homes"
        actions={
          <>
            {streets.length > 0 && (
              <details className="dash-primary-fold">
                <summary className="dash-btn dash-btn--primary">Add a home</summary>
                <div className="dash-primary-fold__panel dash-glass">
                  <ActionForm action={createHome} submit="Add home">
                    <div className="dash-field">
                      <label htmlFor="new-home-street">Street</label>
                      <select id="new-home-street" name="street_id" className="dash-input" required>
                        {streets.map((s) => (
                          <option key={s.id} value={s.id}>
                            {s.name}
                          </option>
                        ))}
                      </select>
                    </div>
                    <div className="dash-field">
                      <label htmlFor="new-home-label">House number</label>
                      <input id="new-home-label" name="label" className="dash-input" placeholder="For example, 14B" required maxLength={40} />
                    </div>
                  </ActionForm>
                </div>
              </details>
            )}
            <More>
              <a href="#streets">Zones and streets</a>
              <Link href="/dashboard/import">Import a register from a spreadsheet</Link>
            </More>
          </>
        }
      >
        Tap a home to see who lives there, their numbers, vehicles and home PIN.
      </PageHead>

      {homes.length === 0 ? (
        <Empty title="No homes yet">Add a zone and a street below, then add homes. Or import your register from a spreadsheet.</Empty>
      ) : (
        <HomeCards homes={homes} onlyNoNumber={show === "no-number"} />
      )}
      {residents.ok && residents.data.length >= 200 && (
        <p className="dash-msg dash-msg--warn">Only the first 200 residents are counted on these cards, so some numbers may be missing here.</p>
      )}

      <div className="dash-mt" id="streets">
        <Fold title="Zones and streets" status={`${register.data.length} zones, ${streets.length} streets`} open={homes.length === 0}>
          <ul className="dash-plainlist">
            {register.data.map((z) => (
              <li key={z.id} className="dash-plainlist__item dash-plainlist__item--block">
                <span className="dash-plainlist__main">
                  <strong>{z.name}</strong>
                  <More label="Change">
                    <InlineEdit action={renameZone} hidden={{ id: z.id }} name="name" value={z.name} label={`New name for ${z.name}`} />
                    {z.streets.length === 0 && (
                      <ConfirmButton action={deleteZone} hidden={{ id: z.id }} label="Delete zone" title={`Delete ${z.name}?`} confirmLabel="Delete zone">
                        <p>This zone has no streets.</p>
                      </ConfirmButton>
                    )}
                  </More>
                </span>
                <ul className="dash-plainlist dash-plainlist--inner">
                  {z.streets.map((st) => (
                    <li key={st.id} className="dash-plainlist__item">
                      <span className="dash-plainlist__main">
                        {st.name} <span className="dash-muted dash-small">{st.homes.length} homes</span>
                      </span>
                      <More label="Change">
                        <InlineEdit action={renameStreet} hidden={{ id: st.id }} name="name" value={st.name} label={`New name for ${st.name}`} />
                        {st.homes.length === 0 && (
                          <ConfirmButton action={deleteStreet} hidden={{ id: st.id }} label="Delete street" title={`Delete ${st.name}?`} confirmLabel="Delete street">
                            <p>This street has no homes.</p>
                          </ConfirmButton>
                        )}
                      </More>
                    </li>
                  ))}
                </ul>
                <ActionForm action={createStreet} hidden={{ zone_id: z.id }} className="dash-inline-form" submit="Add street" submitClass="dash-btn dash-btn--ghost dash-btn--sm">
                  <label htmlFor={`street-${z.id}`} className="sr-only">
                    New street in {z.name}
                  </label>
                  <input id={`street-${z.id}`} name="name" className="dash-input dash-input--sm" placeholder={`New street in ${z.name}`} required maxLength={120} />
                </ActionForm>
              </li>
            ))}
          </ul>
          <ActionForm action={createZone} className="dash-inline-form dash-add" submit="Add zone" submitClass="dash-btn dash-btn--ghost dash-btn--sm">
            <label htmlFor="new-zone" className="sr-only">
              New zone or block
            </label>
            <input id="new-zone" name="name" className="dash-input dash-input--sm" placeholder="New zone or block, e.g. Block A" required maxLength={120} />
          </ActionForm>
        </Fold>
      </div>
    </>
  );
}
