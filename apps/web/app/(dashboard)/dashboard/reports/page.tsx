import type { Metadata } from "next";
import Link from "next/link";
import { load } from "@/app/(dashboard)/_lib/api";
import { ENTRY_METHOD, TRUST, fmtDate, fmtDateTime, fmtDay, pct } from "@/app/(dashboard)/_lib/format";
import type { EntryMethod, EntryTrust, Summary, TrustSplit } from "@/app/(dashboard)/_lib/types";
import { ApiError, Badge, Empty, PageHead, Section } from "@/app/(dashboard)/_components/ui";

export const metadata: Metadata = { title: "Reports" };

const PERIODS = [7, 30, 90] as const;
// Same order as the API. Walk-ins count as admitted but are not part of the phone share.
const METHODS: EntryMethod[] = ["code", "phone_announced", "callback_confirmed", "pin_confirmed", "walk_in_admitted", "refused"];
const LEVELS: EntryTrust[] = ["verified", "pin_verified", "unverified"];

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

      {s.trust && <TrustSection t={s.trust} />}

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

function TrustRow({ label, split }: { label: string; split: TrustSplit }) {
  const total = LEVELS.reduce((n, l) => n + (split[l] ?? 0), 0);
  return (
    <tr>
      <th scope="row">{label}</th>
      {LEVELS.map((l) => (
        <td key={l} data-label={TRUST[l].label} className={`tnum${l === "unverified" && split[l] > 0 ? " dash-warn-text" : ""}`}>
          {split[l] ?? 0}
        </td>
      ))}
      <td data-label="Total" className="tnum">
        {total}
      </td>
    </tr>
  );
}

function TrustTable({ caption, first, rows }: { caption: string; first: string; rows: { label: string; split: TrustSplit }[] }) {
  return (
    <div className="dash-table-wrap">
      <table className="dash-table dash-table--num dash-table--stack">
        <caption className="sr-only">{caption}</caption>
        <thead>
          <tr>
            <th scope="col">{first}</th>
            {LEVELS.map((l) => (
              <th key={l} scope="col">
                {TRUST[l].label}
              </th>
            ))}
            <th scope="col">Total</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <TrustRow key={r.label} label={r.label} split={r.split} />
          ))}
        </tbody>
      </table>
    </div>
  );
}

function TrustSection({ t }: { t: NonNullable<Summary["trust"]> }) {
  return (
    <Section title="Trust">
      <p className="dash-muted dash-small">
        How well each guest let in was verified. Verified: a code, or a callback the resident confirmed. PIN verified: the caller gave the
        home PIN. Unverified: let in on a description, or on a phone call alone; the home is texted &ldquo;Not you? Reply NO&rdquo; at once.
        Phone entries are everyone let in without a code.
      </p>
      <TrustTable
        caption="Entries by trust level"
        first="Entries"
        rows={[
          { label: "Everyone let in", split: t.admitted },
          { label: "Phone entries", split: t.phone_entries },
        ]}
      />
      {t.phone_by_gate.length > 0 && (
        <>
          <h3 className="dash-h3 dash-mt">Phone entries by gate</h3>
          <TrustTable caption="Phone entries by gate" first="Gate" rows={t.phone_by_gate.map(({ gate, ...split }) => ({ label: gate, split }))} />
        </>
      )}
      {t.phone_by_guard.length > 0 && (
        <>
          <h3 className="dash-h3 dash-mt">Phone entries by guard</h3>
          <TrustTable caption="Phone entries by guard" first="Guard" rows={t.phone_by_guard.map(({ guard, ...split }) => ({ label: guard, split }))} />
        </>
      )}
      <h3 className="dash-h3 dash-mt">Home said NO</h3>
      {t.disputes.length === 0 ? (
        <p className="dash-muted dash-small">No home replied NO to an entry in this period.</p>
      ) : (
        <div className="dash-table-wrap">
          <table className="dash-table dash-table--stack">
            <thead>
              <tr>
                <th scope="col">Let in</th>
                <th scope="col">Guest</th>
                <th scope="col">Gate</th>
                <th scope="col">Home said NO</th>
              </tr>
            </thead>
            <tbody>
              {t.disputes.map((d) => (
                <tr key={d.entry_id} className="dash-row--bad">
                  <td data-label="Let in" className="tnum dash-nowrap">
                    {fmtDateTime(d.at)}
                  </td>
                  <td data-label="Guest">{d.guest_name === "Voice clip" ? <span className="dash-muted">Name in a voice clip</span> : d.guest_name}</td>
                  <td data-label="Gate">{d.gate ?? "Unknown gate"}</td>
                  <td data-label="Home said NO">
                    <Badge tone="bad">Home said NO</Badge>
                    <span className="dash-hint tnum">{fmtDateTime(d.disputed_at)}</span>
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
