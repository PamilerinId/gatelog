import type { Metadata } from "next";
import { getEstate, getMe, load } from "@/app/(dashboard)/_lib/api";
import { canOpen } from "@/app/(dashboard)/_lib/roles";
import type { Guard } from "@/app/(dashboard)/_lib/types";
import { ApiError, Empty, NotForRole, PageHead } from "@/app/(dashboard)/_components/ui";
import { GuardCard } from "../gate/GuardCards";

export const metadata: Metadata = { title: "Guards" };

/** The security head's view of the people on the gate. Changes, including a PIN reset, are made
 * by the estate admin (the API allows them to the admin only). */
export default async function GuardsPage() {
  const me = await getMe();
  if (!canOpen(me.role, "guards")) return <NotForRole title="Guards" />;
  const [guards, estate] = await Promise.all([load<Guard[]>("/v1/admin/guards"), getEstate()]);
  const shuttle = estate.ok && estate.data.settings.shuttle_enabled;
  const people = guards.ok ? guards.data.filter((g) => g.active) : [];
  const gone = guards.ok ? guards.data.filter((g) => !g.active) : [];

  return (
    <>
      <PageHead title="Guards">
        Everyone who works a gate phone. To add someone, change a job, record consent or reset a forgotten PIN, ask the estate office.
      </PageHead>
      {!guards.ok ? (
        <ApiError error={guards.error} />
      ) : people.length === 0 ? (
        <Empty title="No guards yet" />
      ) : (
        <ul className="dash-personcards">
          {people.map((g) => (
            <GuardCard key={g.id} g={g} admin={false} shuttle={shuttle} />
          ))}
        </ul>
      )}
      {gone.length > 0 && (
        <p className="dash-muted dash-small dash-mt">
          {gone.length} {gone.length === 1 ? "person no longer has" : "people no longer have"} access: {gone.map((g) => g.name).join(", ")}.
        </p>
      )}
    </>
  );
}
