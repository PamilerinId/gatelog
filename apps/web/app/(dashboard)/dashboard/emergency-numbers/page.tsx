import type { Metadata } from "next";
import { getMe, load } from "@/app/(dashboard)/_lib/api";
import { canOpen, persona } from "@/app/(dashboard)/_lib/roles";
import { CATEGORY, fmtDate } from "@/app/(dashboard)/_lib/format";
import type { DirectoryCategory, DirectoryEntry } from "@/app/(dashboard)/_lib/types";
import { ActionForm } from "@/app/(dashboard)/_components/ActionForm";
import { ConfirmButton } from "@/app/(dashboard)/_components/ConfirmButton";
import { ApiError, Badge, Empty, More, NotForRole, PageHead } from "@/app/(dashboard)/_components/ui";
import { createDirectoryEntry, deleteDirectoryEntry, reportDirectoryEntry, updateDirectoryEntry, verifyDirectoryEntry } from "../actions";

export const metadata: Metadata = { title: "Emergency numbers" };

const ORDER: DirectoryCategory[] = ["estate", "crime", "fire", "medical", "utilities"];
const SCOPE = { estate: "Estate", state: "State", lga: "Local government" } as const;

export default async function EmergencyNumbersPage() {
  const me = await getMe();
  if (!canOpen(me.role, "emergency-numbers")) return <NotForRole title="Emergency numbers" />;
  const r = await load<DirectoryEntry[]>("/v1/admin/directory");
  const admin = me.role === "admin";
  // The Exco reads; the office and the security head can say a number did not work.
  const canReport = persona(me.role) !== "exco";

  return (
    <>
      <PageHead title="Emergency numbers">
        The list residents and guards get when they ask for help. Your estate&rsquo;s own numbers are yours to keep right. State and local
        government numbers are maintained by Gatelog. Every number should be test-called at least every three months.
      </PageHead>

      {!r.ok ? (
        <ApiError error={r.error} />
      ) : (
        <>
          {r.data.length === 0 && <Empty title="No numbers yet">{admin ? "Add the estate's own numbers below: security office, clinic, facility manager." : undefined}</Empty>}
          {ORDER.map((cat) => {
            const rows = r.data.filter((e) => e.category === cat);
            if (rows.length === 0) return null;
            return (
              <section key={cat} className="dash-section" aria-labelledby={`cat-${cat}`}>
                <h2 className="dash-h2" id={`cat-${cat}`}>
                  {CATEGORY[cat]}
                </h2>
                <div className="dash-cards">
                  {rows.map((e) => (
                    <NumberCard key={e.id} e={e} admin={admin} canReport={canReport} />
                  ))}
                </div>
              </section>
            );
          })}

          {admin && (
            <details className="dash-details" open={r.data.every((e) => !e.editable)}>
              <summary>Add an estate number</summary>
              <ActionForm action={createDirectoryEntry} submit="Add number">
                <DirectoryFields />
              </ActionForm>
            </details>
          )}
        </>
      )}
    </>
  );
}

function DirectoryFields({ e }: { e?: DirectoryEntry }) {
  const p = e?.id ?? "new";
  return (
    <div className="dash-grid2">
      <div className="dash-field">
        <label htmlFor={`${p}-name`}>Name</label>
        <input id={`${p}-name`} name="name" className="dash-input" defaultValue={e?.name} placeholder="For example, Estate security office" required minLength={2} maxLength={120} />
      </div>
      <div className="dash-field">
        <label htmlFor={`${p}-number`}>Number</label>
        <input id={`${p}-number`} name="number" className="dash-input" inputMode="tel" defaultValue={e?.number} placeholder="08031234567 or 112" required />
      </div>
      <div className="dash-field">
        <label htmlFor={`${p}-cat`}>Kind of help</label>
        <select id={`${p}-cat`} name="category" className="dash-input" defaultValue={e?.category ?? "estate"}>
          {ORDER.map((c) => (
            <option key={c} value={c}>
              {CATEGORY[c]}
            </option>
          ))}
        </select>
      </div>
      <div className="dash-field">
        <label htmlFor={`${p}-rank`}>Order in the list</label>
        <input id={`${p}-rank`} name="rank" type="number" min={1} max={1000} className="dash-input" defaultValue={e?.rank ?? 100} />
        <span className="dash-hint">Lower numbers come first.</span>
      </div>
    </div>
  );
}

function NumberCard({ e, admin, canReport }: { e: DirectoryEntry; admin: boolean; canReport: boolean }) {
  return (
    <article className="dash-card dash-dir">
      <div className="dash-dir__head">
        <div>
          <h3 className="dash-h3">{e.name}</h3>
          <p className="dash-dir__number tnum">{e.number}</p>
        </div>
        <div className="dash-badges">
          <Badge>{SCOPE[e.scope]}</Badge>
          {e.reported_not_working && <Badge tone="bad">Reported not working</Badge>}
          {e.overdue && <Badge tone="warn">Test call overdue</Badge>}
        </div>
      </div>
      <p className="dash-small">
        {e.verified_at ? (
          <>
            Last verified {fmtDate(e.verified_at)}
            {e.verification_note ? `: ${e.verification_note}` : "."}
          </>
        ) : (
          <span className="dash-muted">Never verified by a test call.</span>
        )}
      </p>
      {!e.editable && <p className="dash-hint">Gatelog maintains this number. If it did not work, report it so Gatelog can test it again.</p>}

      {admin && e.editable ? (
        <More label="Change">
            <details className="dash-details dash-details--inline">
              <summary>Mark verified</summary>
              <ActionForm action={verifyDirectoryEntry} hidden={{ id: e.id }} submit="Mark verified today" submitClass="dash-btn dash-btn--primary dash-btn--sm">
                <div className="dash-field">
                  <label htmlFor={`${e.id}-note`}>Who answered?</label>
                  <input id={`${e.id}-note`} name="note" className="dash-input" maxLength={280} placeholder="For example, Sgt Musa at the front desk" />
                  <span className="dash-hint">Call the number first. Only mark it verified if someone answered.</span>
                </div>
              </ActionForm>
            </details>
            <details className="dash-details dash-details--inline">
              <summary>Edit</summary>
              <ActionForm action={updateDirectoryEntry} hidden={{ id: e.id }} reset={false} submit="Save" submitClass="dash-btn dash-btn--primary dash-btn--sm">
                <DirectoryFields e={e} />
              </ActionForm>
            </details>
            <ConfirmButton action={deleteDirectoryEntry} hidden={{ id: e.id }} label="Delete" title={`Delete ${e.name}?`} confirmLabel="Delete number">
              <p>It will no longer be sent to residents and guards who ask for help.</p>
            </ConfirmButton>
        </More>
      ) : canReport ? (
        <ActionForm action={reportDirectoryEntry} hidden={{ id: e.id }} className="dash-inline-form" submit="This number didn't work" submitClass="dash-btn dash-btn--quiet dash-btn--sm" />
      ) : null}
    </article>
  );
}
