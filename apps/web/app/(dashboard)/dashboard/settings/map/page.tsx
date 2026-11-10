import type { Metadata } from "next";
import { getMap, getMe, load } from "@/app/(dashboard)/_lib/api";
import type { ZoneNode } from "@/app/(dashboard)/_lib/types";
import { ApiError, PageHead } from "@/app/(dashboard)/_components/ui";
import { MapEditor } from "@/app/(dashboard)/_map/MapEditor";

export const metadata: Metadata = { title: "Estate map" };

export default async function MapEditorPage() {
  const me = await getMe();
  if (me.role !== "admin") {
    return (
      <>
        <PageHead title="Estate map" />
        <p className="dash-msg dash-msg--warn">Only an estate admin can change the estate map.</p>
      </>
    );
  }
  const [map, register] = await Promise.all([getMap(), load<ZoneNode[]>("/v1/admin/register")]);
  if (!map.ok)
    return (
      <>
        <PageHead title="Estate map" />
        <ApiError error={map.error} />
      </>
    );
  const homes = register.ok
    ? register.data.flatMap((z) => z.streets.flatMap((st) => st.homes.map((h) => ({ id: h.id, address: h.address, group: `${z.name}, ${st.name}` }))))
    : [];

  return <MapEditor data={map.data} homes={homes} />;
}
