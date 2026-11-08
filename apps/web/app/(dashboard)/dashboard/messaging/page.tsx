import type { Metadata } from "next";
import Form from "next/form";
import Link from "next/link";
import { getMe, load } from "@/app/(dashboard)/_lib/api";
import { addMonths, fmtCount, fmtMonth, fmtNaira, pct, thisMonthLagos } from "@/app/(dashboard)/_lib/format";
import type { Estate, MessagingUsage, Role } from "@/app/(dashboard)/_lib/types";
import { ApiError, Badge, Empty, PageHead, Section } from "@/app/(dashboard)/_components/ui";

export const metadata: Metadata = { title: "Messaging usage" };

const MONTH = /^\d{4}-(0[1-9]|1[0-2])$/;
const READERS: Role[] = ["admin", "committee", "treasurer", "security_head"];
// The spec's alert threshold: the treasurer is told when projected SMS passes 80% of the allowance.
const WARN_AT = 0.8;

export default async function MessagingPage({ searchParams }: { searchParams: Promise<{ month?: string }> }) {
  const me = await getMe();
  if (!READERS.includes(me.role)) {
    return (
      <>
        <PageHead title="Messaging usage" />
        <p className="dash-msg dash-msg--warn">This page is for the estate admin, committee, treasurer and security head.</p>
      </>
    );
  }

  const { month: raw } = await searchParams;
  const current = thisMonthLagos();
  const month = raw && MONTH.test(raw) && raw <= current ? raw : current;
  const isCurrent = month === current;

  const [usage, estate] = await Promise.all([
    load<MessagingUsage>(`/v1/reports/messaging?${new URLSearchParams({ month })}`),
    load<Estate>("/v1/admin/estate"),
  ]);

  return (
    <>
      <PageHead title="Messaging usage">
        Every WhatsApp and SMS message Gatelog sent for the estate, by purpose, so the bill is never a surprise. Counts only: no message
        contents and no phone numbers.
      </PageHead>

      <Form action="/dashboard/messaging" className="dash-filters">
        <div className="dash-field">
          <label htmlFor="month">Month</label>
          <input id="month" name="month" type="month" className="dash-input dash-input--sm" defaultValue={month} max={current} pattern="\d{4}-\d{2}" placeholder="YYYY-MM" />
        </div>
        <button type="submit" className="dash-btn dash-btn--primary dash-btn--sm">
          Show
        </button>
        <span className="dash-row-actions">
          <Link className="dash-btn dash-btn--quiet dash-btn--sm" href={`/dashboard/messaging?month=${addMonths(month, -1)}`}>
            Previous month
          </Link>
          {!isCurrent && (
            <Link className="dash-btn dash-btn--quiet dash-btn--sm" href={`/dashboard/messaging?month=${addMonths(month, 1)}`}>
              Next month
            </Link>
          )}
        </span>
      </Form>

      {!usage.ok ? (
        <ApiError error={usage.error} />
      ) : (
        <Usage u={usage.data} isCurrent={isCurrent} perHome={estate.ok ? estate.data.settings.sms_allowance_per_home : null} />
      )}
    </>
  );
}

function Usage({ u, isCurrent, perHome }: { u: MessagingUsage; isCurrent: boolean; perHome: number | null }) {
  const whatsapp = u.by_purpose.reduce((n, p) => n + p.whatsapp, 0);
  const sms = u.by_purpose.reduce((n, p) => n + p.sms, 0);
  const over = u.allowance_used != null && u.allowance_used > WARN_AT;

  return (
    <>
      <p className="dash-muted dash-small">
        {fmtMonth(u.month)}
        {isCurrent ? ", so far this month." : "."}
      </p>

      <Section title="SMS against your allowance" id="allowance">
        {u.sms_allowance == null ? (
          <p className="dash-msg dash-msg--warn">No SMS allowance set in your contract. The counts below are shown for your records.</p>
        ) : (
          <>
            <div className="dash-stats">
              <Figure label="Counted against the allowance" value={fmtCount(u.sms_counted)}>
                SMS sent {isCurrent ? "so far this month" : "in the month"}, leaving out SOS and emergency numbers.
              </Figure>
              <Figure label="Allowance" value={fmtCount(u.sms_allowance)}>
                {perHome != null ? `${fmtCount(perHome)} SMS per home per month, from your contract.` : "SMS a month, from your contract."}
              </Figure>
              <Figure label={isCurrent ? "Projected to month end" : "Used in the month"} value={fmtCount(u.sms_projected)} tone={over ? "warn" : "ok"}>
                {pct(u.allowance_used)} of the allowance.
                {isCurrent && <span className="dash-stat__rule">At the pace so far this month.</span>}
              </Figure>
              <Figure
                label={isCurrent ? "Projected overage" : "Overage"}
                value={u.projected_overage_naira == null ? "Not set" : fmtNaira(u.projected_overage_naira)}
                tone={u.projected_overage_naira ? "warn" : undefined}
              >
                {u.projected_overage_naira == null
                  ? "Your contract has no price for SMS over the allowance."
                  : u.projected_overage_naira > 0
                    ? "SMS over the allowance, at the contract rate."
                    : "Nothing over the allowance."}
              </Figure>
            </div>
            {over && (
              <p className="dash-msg dash-msg--warn">
                {isCurrent ? "Projected SMS use is past 80% of the allowance." : "SMS use went past 80% of the allowance this month."}
              </p>
            )}
          </>
        )}
      </Section>

      <Section title="By purpose" id="purpose">
        <p className="dash-muted dash-small">{u.note}</p>
        {u.by_purpose.length === 0 ? (
          <Empty title="No messages sent this month" />
        ) : (
          <div className="dash-table-wrap">
            <table className="dash-table dash-table--num dash-table--stack">
              <thead>
                <tr>
                  <th scope="col">Purpose</th>
                  <th scope="col">WhatsApp</th>
                  <th scope="col">SMS</th>
                </tr>
              </thead>
              <tbody>
                {u.by_purpose.map((p) => (
                  <tr key={p.purpose}>
                    <th scope="row">
                      {p.purpose}
                      {!p.billed && (
                        <>
                          {" "}
                          <Badge>Never counted or billed</Badge>
                        </>
                      )}
                    </th>
                    <td data-label="WhatsApp" className="tnum">
                      {fmtCount(p.whatsapp)}
                    </td>
                    <td data-label="SMS" className="tnum">
                      {fmtCount(p.sms)}
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot>
                <tr>
                  <th scope="row">Total</th>
                  <td data-label="WhatsApp" className="tnum">
                    {fmtCount(whatsapp)}
                  </td>
                  <td data-label="SMS" className="tnum">
                    {fmtCount(sms)}
                  </td>
                </tr>
              </tfoot>
            </table>
          </div>
        )}
      </Section>
    </>
  );
}

function Figure({ label, value, tone, children }: { label: string; value: string; tone?: "ok" | "warn"; children: React.ReactNode }) {
  return (
    <div className={`dash-stat${tone ? ` dash-stat--${tone}` : ""}`}>
      <p className="dash-stat__label">{label}</p>
      <p className="dash-stat__value tnum">{value}</p>
      <p className="dash-stat__note">{children}</p>
    </div>
  );
}
