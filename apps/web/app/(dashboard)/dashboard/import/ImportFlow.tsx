"use client";

import Link from "next/link";
import { useState, useTransition, type FormEvent } from "react";
import { CONTACT } from "@/app/(dashboard)/_lib/format";
import type { ImportBatch } from "@/app/(dashboard)/_lib/types";
import { runAction } from "@/app/(dashboard)/_components/ActionForm";
import { commitImport, discardImport } from "../actions";

export function ImportFlow() {
  const [batch, setBatch] = useState<ImportBatch | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [onlyProblems, setOnlyProblems] = useState(false);
  const [pending, start] = useTransition();

  function upload(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    setError(null);
    start(async () => {
      try {
        const res = await fetch("/dashboard/import/upload", { method: "POST", body: fd });
        const body = (await res.json()) as { batch?: ImportBatch; error?: string; signedOut?: boolean };
        if (body.signedOut) {
          window.location.href = "/sign-in?expired=1";
          return;
        }
        if (!res.ok || !body.batch) setError(body.error ?? "The upload did not work. Try again.");
        else {
          setBatch(body.batch);
          setOnlyProblems((body.batch.summary.errors ?? 0) > 0);
        }
      } catch {
        setError("The upload did not work. Check your connection and try again.");
      }
    });
  }

  function decide(kind: "commit" | "discard") {
    if (!batch) return;
    const fd = new FormData();
    fd.set("id", batch.id);
    setError(null);
    start(async () => {
      const r = await runAction(kind === "commit" ? commitImport : discardImport, fd);
      if (!r?.ok) setError(r?.error ?? "That did not work.");
      else setBatch(r.data as ImportBatch);
    });
  }

  if (!batch || batch.status === "discarded") {
    return (
      <div className="dash-card">
        {batch?.status === "discarded" && (
          <p className="dash-msg dash-msg--ok" role="status">
            Import discarded. Nothing was saved.
          </p>
        )}
        <form className="dash-form" onSubmit={upload}>
          <div className="dash-field">
            <label htmlFor="file">Spreadsheet</label>
            <input id="file" name="file" type="file" className="dash-file" accept=".csv,.xlsx,.xlsm,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" required />
          </div>
          <button type="submit" className="dash-btn dash-btn--primary" disabled={pending}>
            {pending ? "Checking the file..." : "Upload and check"}
          </button>
          {error && (
            <p className="dash-msg dash-msg--error" role="alert">
              {error}
            </p>
          )}
        </form>
      </div>
    );
  }

  const s = batch.summary;
  if (batch.status === "committed" && batch.result) {
    const c = batch.result.created;
    return (
      <div className="dash-card">
        <h2 className="dash-h2">Import saved</h2>
        <p className="dash-muted">From {batch.filename}.</p>
        <dl className="dash-figures">
          <Fig label="Zones created" value={c.zones} />
          <Fig label="Streets created" value={c.streets} />
          <Fig label="Homes created" value={c.homes} />
          <Fig label="Residents created" value={c.residents} />
          <Fig label="Numbers added" value={c.numbers} />
        </dl>
        {batch.result.skipped.length > 0 && (
          <>
            <h3 className="dash-h3">Skipped ({batch.result.skipped.length})</h3>
            <ul className="dash-list">
              {batch.result.skipped.map((k, i) => (
                <li key={i}>
                  Row {k.line}: {k.reason}
                </li>
              ))}
            </ul>
          </>
        )}
        <div className="dash-actions">
          <Link href="/dashboard/register" className="dash-btn dash-btn--primary">
            Open the register
          </Link>
          <button type="button" className="dash-btn dash-btn--ghost" onClick={() => setBatch(null)}>
            Import another file
          </button>
        </div>
      </div>
    );
  }

  const rows = onlyProblems ? batch.rows.filter((r) => r.errors.length || r.warnings.length) : batch.rows;
  const good = (s.rows ?? 0) - (s.errors ?? 0);

  return (
    <div className="dash-card">
      <h2 className="dash-h2">Check before saving</h2>
      <p className="dash-muted">
        {batch.filename}: {s.rows ?? 0} rows read. Rows with errors are left out when you commit.
      </p>
      <dl className="dash-figures">
        <Fig label="Rows" value={s.rows} />
        <Fig label="Rows with errors" value={s.errors} tone={s.errors ? "bad" : undefined} />
        <Fig label="New zones" value={s.new_zones} />
        <Fig label="New streets" value={s.new_streets} />
        <Fig label="New homes" value={s.new_homes} />
        <Fig label="Residents" value={s.residents} />
        <Fig label="Numbers" value={s.numbers} />
      </dl>

      <label className="dash-check">
        <input type="checkbox" checked={onlyProblems} onChange={(e) => setOnlyProblems(e.target.checked)} />
        <span>Show only rows with errors or warnings</span>
      </label>

      {rows.length === 0 ? (
        <p className="dash-muted">{onlyProblems ? "No problems found." : "No rows."}</p>
      ) : (
        <div className="dash-table-wrap">
          <table className="dash-table dash-table--stack">
            <thead>
              <tr>
                <th scope="col">Row</th>
                <th scope="col">Address</th>
                <th scope="col">Resident</th>
                <th scope="col">Numbers</th>
                <th scope="col">Contact</th>
                <th scope="col">Problems</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.line} className={r.errors.length ? "dash-row--bad" : undefined}>
                  <td data-label="Row" className="tnum">
                    {r.line}
                  </td>
                  <td data-label="Address">{[r.house, r.street, r.zone].filter(Boolean).join(", ") || "Empty"}</td>
                  <td data-label="Resident">{r.resident || <span className="dash-muted">None</span>}</td>
                  <td data-label="Numbers" className="tnum">
                    {r.phones.join(", ") || <span className="dash-muted">None</span>}
                  </td>
                  <td data-label="Contact">
                    {CONTACT[r.contact_pref]}
                    {r.callback_required ? ", callback" : ""}
                  </td>
                  <td data-label="Problems">
                    {r.errors.map((e, i) => (
                      <span key={`e${i}`} className="dash-problem dash-problem--bad">
                        {e}
                      </span>
                    ))}
                    {r.warnings.map((w, i) => (
                      <span key={`w${i}`} className="dash-problem dash-problem--warn">
                        {w}
                      </span>
                    ))}
                    {!r.errors.length && !r.warnings.length && <span className="dash-muted">None</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {error && (
        <p className="dash-msg dash-msg--error" role="alert">
          {error}
        </p>
      )}
      <div className="dash-actions">
        <button type="button" className="dash-btn dash-btn--primary" disabled={pending || good === 0} onClick={() => decide("commit")}>
          {pending ? "Working..." : `Commit ${good} ${good === 1 ? "row" : "rows"}`}
        </button>
        <button type="button" className="dash-btn dash-btn--ghost" disabled={pending} onClick={() => decide("discard")}>
          Discard
        </button>
      </div>
    </div>
  );
}

function Fig({ label, value, tone }: { label: string; value: number | undefined; tone?: "bad" }) {
  return (
    <div className={`dash-fig${tone ? ` dash-fig--${tone}` : ""}`}>
      <dt>{label}</dt>
      <dd className="tnum">{value ?? 0}</dd>
    </div>
  );
}
