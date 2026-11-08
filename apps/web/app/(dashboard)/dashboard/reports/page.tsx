import type { Metadata } from "next";
import Link from "next/link";
import { load } from "@/app/(dashboard)/_lib/api";
import { ENTRY_METHOD, fmtDate, fmtDay, pct } from "@/app/(dashboard)/_lib/format";
import type { EntryMethod, Summary } from "@/app/(dashboard)/_lib/types";
import { ApiError, Empty, PageHead, Section } from "@/app/(dashboard)/_components/ui";

export const metadata: Metadata = { title: "Reports" };

const PERIODS = [7, 30, 90] as const;
// Same order as the API. Walk-ins count as admitted but are not part of the phone share.
const METHODS: EntryMethod[] = ["code", "phone_announced", "callback_confirmed", "walk_in_admitted", "refused"];

export default async function ReportsPage({ searchParams }: { searchParams: Promise<{ days?: string }> }) {
  const { days: raw } = await searchParams;
  const days = PERIODS.find((p) => String(p) === raw) ?? 30;
  const since = new Date(Date.now() - days * 86_400_000).toISOString();
  const r = await load<Summary>(`/v1/reports/summary?${new URLSearchParams({ since })}`);

  return (
    <>
      <PageHead
        title="Reports"
        actions={
          <>
            <a className="dash-btn dash-btn--ghost dash-btn--sm" href={`/dashboard/reports/export?view=summary&days=${days}`} download>
              Download summary (Excel)
            </a>
            <a className="dash-btn dash-btn--ghost dash-btn--sm" href={`/dashboard/reports/export?view=entries&days=${days}`} download>
              Download all entries (Excel)
            </a>
          </>
        }
      >
        What happened at the gate, for committee meetings.
      </PageHead>

      <nav className="dash-tabs" aria-label="Period">
        {PERIODS.map((p) => (
          <Link key={p} href={`/dashboard/reports?days=${p}`} className="dash-tab" aria-current={p === days ? "page" : undefined}>
            Last {p} days
          </Link>
        ))}
      </nav>

      {!r.ok ? <ApiError error={r.error} /> : <Report s={r.data} />}
    </>
  );
}

function Report({ s }: { s: Summary }) {
  const totals = METHODS.reduce((acc, m) => ({ ...acc, [m]: s.entries.by_method[m] ?? 0 }), {} as Record<EntryMethod, number>);
  return (
    <>
      <p className="dash-muted dash-small">
        {fmtDate(s.since)} to {fmtDate(s.until)}.
      </p>

      <Section title="At a glance">
        <div className="dash-table-wrap">
          <table className="dash-table dash-table--kv">
            <tbody>
              <tr>
                <th scope="row">Entries</th>
                <td className="tnum">
                  {s.entries.total} ({s.entries.admitted} let in)
                </td>
              </tr>
              <tr>
                <th scope="row">Entries by phone</th>
                <td>
                  <span className="tnum">{pct(s.phone_share)}</span>
                  <span className="dash-hint">Codes are not being adopted if this is over 40% by phone after 8 weeks.</span>
                </td>
              </tr>
              <tr>
                <th scope="row">Exit capture rate</th>
                <td>
                  <span className="tnum">{pct(s.exits.capture_rate)}</span>
                  <span className="dash-hint">
                    {s.exits.gate_confirmed} of {s.exits.measurable_entries} guests had their exit confirmed at the gate. Should be at least 70%.
                  </span>
                </td>
              </tr>
              <tr>
                <th scope="row">Confirmed by the resident</th>
                <td className="tnum">{s.exits.resident_confirmed}</td>
              </tr>
              <tr>
                <th scope="row">Missed exits</th>
                <td className="tnum">{s.exits.missed}</td>
              </tr>
              <tr>
                <th scope="row">Exits with no entry</th>
                <td className="tnum">{s.exits.unmatched_exits}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </Section>

      <Section title="Entries by day">
        {s.entries_by_day.length === 0 ? (
          <Empty title="No entries in this period" />
        ) : (
          <div className="dash-table-wrap">
            <table className="dash-table dash-table--num dash-table--matrix">
              <thead>
                <tr>
                  <th scope="col">Day</th>
                  {METHODS.map((m) => (
                    <th key={m} scope="col">
                      {ENTRY_METHOD[m]}
                    </th>
                  ))}
                  <th scope="col">Total</th>
                </tr>
              </thead>
              <tbody>
                {s.entries_by_day.map((d) => (
                  <tr key={d.date}>
                    <th scope="row" data-label="Day">
                      {fmtDay(d.date)}
                    </th>
                    {METHODS.map((m) => (
                      <td key={m} data-label={ENTRY_METHOD[m]} className="tnum">
                        {d[m] ?? 0}
                      </td>
                    ))}
                    <td data-label="Total" className="tnum">
                      {METHODS.reduce((n, m) => n + (d[m] ?? 0), 0)}
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot>
                <tr>
                  <th scope="row" data-label="Period">
                    Total
                  </th>
                  {METHODS.map((m) => (
                    <td key={m} data-label={ENTRY_METHOD[m]} className="tnum">
                      {totals[m]}
                    </td>
                  ))}
                  <td data-label="Total" className="tnum">
                    {s.entries.total}
                  </td>
                </tr>
              </tfoot>
            </table>
          </div>
        )}
      </Section>

      <Section title="Entries by gate">
        {s.entries_by_gate.length === 0 ? (
          <Empty title="No entries in this period" />
        ) : (
          <div className="dash-table-wrap">
            <table className="dash-table dash-table--num">
              <thead>
                <tr>
                  <th scope="col">Gate</th>
                  <th scope="col">Entries</th>
                </tr>
              </thead>
              <tbody>
                {s.entries_by_gate.map((g) => (
                  <tr key={g.gate}>
                    <th scope="row">{g.gate}</th>
                    <td className="tnum">{g.count}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Section>

      <Section title="Guests still inside at night">
        <p className="dash-muted dash-small">
          Each night Gatelog lists guests still inside past their expected time. Anyone still on the list at morning handover counts as a missed exit.
        </p>
        {s.overstays_by_night.length === 0 ? (
          <Empty title="No night lists in this period" />
        ) : (
          <div className="dash-table-wrap">
            <table className="dash-table dash-table--stack dash-table--num">
              <thead>
                <tr>
                  <th scope="col">Night</th>
                  <th scope="col">On the night list</th>
                  <th scope="col">Closed by morning</th>
                  <th scope="col">Missed</th>
                </tr>
              </thead>
              <tbody>
                {s.overstays_by_night.map((n) => (
                  <tr key={n.date}>
                    <th scope="row" data-label="Night">
                      {fmtDay(n.date)}
                    </th>
                    <td data-label="On the night list" className="tnum">
                      {n.open_at_rollup}
                    </td>
                    <td data-label="Closed by morning" className="tnum">
                      {n.closed_by_morning ?? "Not yet"}
                    </td>
                    <td data-label="Missed" className="tnum">
                      {n.missed ?? "Not yet"}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Section>
    </>
  );
}
