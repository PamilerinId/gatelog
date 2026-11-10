import type { Metadata } from "next";
import { getMe, load } from "@/app/(dashboard)/_lib/api";
import { GUARD_ROLE, SELFIE, SHIFT_END, fmtDateTime } from "@/app/(dashboard)/_lib/format";
import { canOpen, seesMedia } from "@/app/(dashboard)/_lib/roles";
import type { Shift } from "@/app/(dashboard)/_lib/types";
import { ApiError, Empty, NotForRole, PageHead } from "@/app/(dashboard)/_components/ui";
import { SelfieButton } from "../gate/SelfieButton";

export const metadata: Metadata = { title: "Shifts" };

const DAYS = 14;

export default async function ShiftsPage() {
  const me = await getMe();
  if (!canOpen(me.role, "shifts")) return <NotForRole title="Shifts" />;
  const since = new Date(Date.now() - DAYS * 86_400_000).toISOString();
  const shifts = await load<Shift[]>(`/v1/admin/shifts?${new URLSearchParams({ since })}`);
  const selfies = seesMedia(me.role);
  const open = shifts.ok ? shifts.data.filter((s) => !s.ended_at) : [];
  const done = shifts.ok ? shifts.data.filter((s) => s.ended_at) : [];

  return (
    <>
      <PageHead title="Shifts">Who worked the gate in the last {DAYS} days, newest first. Selfies are kept 30 days and every viewing is recorded.</PageHead>
      {!shifts.ok ? (
        <ApiError error={shifts.error} />
      ) : shifts.data.length === 0 ? (
        <Empty title="No shifts yet">Shifts appear once someone starts one on a gate phone and the phone syncs.</Empty>
      ) : (
        <>
          {open.length > 0 && (
            <>
              <h2 className="dash-h2">On shift now</h2>
              <ul className="dash-shiftlist">
                {open.map((s) => (
                  <ShiftItem key={s.id} s={s} selfies={selfies} />
                ))}
              </ul>
            </>
          )}
          <h2 className="dash-h2 dash-mt">Earlier shifts</h2>
          {done.length === 0 ? (
            <p className="dash-muted dash-small">None in the last {DAYS} days.</p>
          ) : (
            <ul className="dash-shiftlist">
              {done.map((s) => (
                <ShiftItem key={s.id} s={s} selfies={selfies} />
              ))}
            </ul>
          )}
        </>
      )}
    </>
  );
}

function ShiftItem({ s, selfies }: { s: Shift; selfies: boolean }) {
  const who = s.guard ?? "Unknown";
  const h = s.handover;
  const selfie = SELFIE[s.selfie];
  return (
    <li className="dash-shift">
      <div className="dash-shift__main">
        <span className="dash-shift__who">
          {who} <span className="dash-muted">· {s.role ? GUARD_ROLE[s.role] : "Guard"} · {s.gate ?? "Unknown gate"}</span>
        </span>
        <span className="dash-shift__when tnum">
          {fmtDateTime(s.started_at)}
          {s.ended_at ? ` to ${fmtDateTime(s.ended_at)}` : ", on shift now"}
        </span>
        {s.end_reason && (
          <span className="dash-hint">
            {SHIFT_END[s.end_reason]}
            {s.handed_to ? `, to ${s.handed_to}` : ""}
            {h ? `. At handover: ${h.inside ?? 0} inside, ${h.unsynced ?? 0} not synced${h.night_list_open != null ? `, ${h.night_list_open} on the night list` : ""}.` : ""}
          </span>
        )}
      </div>
      <div className="dash-shift__side">
        {selfies && s.selfie === "available" ? (
          <SelfieButton shiftId={s.id} who={who} when={fmtDateTime(s.started_at)} />
        ) : (
          <span className="dash-small dash-muted">Selfie: {selfie.label.toLowerCase()}</span>
        )}
      </div>
    </li>
  );
}
