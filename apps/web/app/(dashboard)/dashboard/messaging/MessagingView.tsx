import Link from "next/link";
import { load } from "@/app/(dashboard)/_lib/api";
import { addMonths, fmtCount, fmtMonth, fmtNaira, pct, thisMonthLagos } from "@/app/(dashboard)/_lib/format";
import type { Estate, MessagingUsage } from "@/app/(dashboard)/_lib/types";
import { ApiError, Badge, Empty, PageHead } from "@/app/(dashboard)/_components/ui";

// Messages: the treasurer's first screen, and the same page for the estate office and the Exco.
// One big number first (SMS used against the allowance), then the breakdown.

// The spec's alert threshold: the treasurer is told when projected SMS passes 80% of the allowance.
const WARN_AT = 0.8;

export async function MessagingView({ month, base }: { month: string; base: string }) {
  const current = thisMonthLagos();
  const isCurrent = month === current;
  const [usage, estate] = await Promise.all([
    load<MessagingUsage>(`/v1/reports/messaging?${new URLSearchParams({ month })}`),
    load<Estate>("/v1/admin/estate"),
  ]);
  const perHome = estate.ok ? estate.data.settings.sms_allowance_per_home : null;

  return (
    <>
      <PageHead title="Messages">
        {fmtMonth(month)}
        {isCurrent ? ", so far" : ""}. Every WhatsApp and SMS Gatelog sent for the estate. Counts only: no message contents and no phone numbers.
      </PageHead>
      <nav className="dash-monthnav" aria-label="Month">
        <Link href={`${base}?month=${addMonths(month, -1)}`}>Previous month</Link>
        {!isCurrent && <Link href={`${base}?month=${addMonths(month, 1)}`}>Next month</Link>}
      </nav>
      {!usage.ok ? <ApiError error={usage.error} /> : <Usage u={usage.data} isCurrent={isCurrent} perHome={perHome} />}
    </>
  );
}

function Usage({ u, isCurrent, perHome }: { u: MessagingUsage; isCurrent: boolean; perHome: number | null }) {
  const whatsapp = u.by_purpose.reduce((n, p) => n + p.whatsapp, 0);
  const sms = u.by_purpose.reduce((n, p) => n + p.sms, 0);
  const over = u.allowance_used != null && u.allowance_used > WARN_AT;

  return (
    <>
      <section className="dash-hero" aria-label="SMS against the allowance">
        <p className={`dash-hero__value tnum${over ? " is-warn" : ""}`}>
          {fmtCount(u.sms_counted)}
          {u.sms_allowance != null && <span className="dash-hero__of"> of {fmtCount(u.sms_allowance)}</span>}
        </p>
        <p className="dash-hero__label">
          {u.sms_allowance != null ? "SMS used against the allowance" : "SMS sent, counted towards a bill"}
          {isCurrent ? " so far this month" : ""}
        </p>
        {u.sms_allowance != null && (
          <div className="dash-meter" role="img" aria-label={`${pct(u.allowance_used)} of the allowance used`}>
            <span className={`dash-meter__fill${over ? " is-warn" : ""}`} style={{ width: `${Math.min(100, Math.round((u.sms_counted / Math.max(1, u.sms_allowance)) * 100))}%` }} />
          </div>
        )}
        <p className="dash-hero__note">
          {u.sms_allowance == null
            ? "Your contract has no SMS allowance, so these counts are for your records."
            : isCurrent
              ? `At this pace, about ${fmtCount(u.sms_projected)} by the end of the month (${pct(u.allowance_used)} of the allowance).`
              : `${pct(u.allowance_used)} of the allowance was used.`}
          {u.projected_overage_naira != null && u.projected_overage_naira > 0 && ` Expected cost over the allowance: ${fmtNaira(u.projected_overage_naira)}.`}
          {perHome != null && ` The allowance is ${fmtCount(perHome)} SMS per home per month.`}
        </p>
        {over && (
          <p className="dash-msg dash-msg--warn">
            {isCurrent ? "SMS use is heading past 80% of the allowance." : "SMS use went past 80% of the allowance this month."}
          </p>
        )}
      </section>

      <h2 className="dash-h2 dash-mt">What was sent</h2>
      <p className="dash-muted dash-small">{u.note}</p>
      {u.by_purpose.length === 0 ? (
        <Empty title="No messages sent this month" />
      ) : (
        <ul className="dash-plainlist">
          {u.by_purpose.map((p) => (
            <li key={p.purpose} className="dash-plainlist__item">
              <span className="dash-plainlist__main">
                {p.purpose}
                {!p.billed && (
                  <>
                    {" "}
                    <Badge>Never counted or billed</Badge>
                  </>
                )}
              </span>
              <span className="dash-plainlist__side tnum">
                {fmtCount(p.whatsapp)} WhatsApp · {fmtCount(p.sms)} SMS
              </span>
            </li>
          ))}
          <li className="dash-plainlist__item dash-plainlist__item--total">
            <span className="dash-plainlist__main">Total</span>
            <span className="dash-plainlist__side tnum">
              {fmtCount(whatsapp)} WhatsApp · {fmtCount(sms)} SMS
            </span>
          </li>
        </ul>
      )}
    </>
  );
}
