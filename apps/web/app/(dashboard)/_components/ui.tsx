import Link from "next/link";
import type { ReactNode } from "react";

export function PageHead({ title, children, actions }: { title: string; children?: ReactNode; actions?: ReactNode }) {
  return (
    <header className="dash-head">
      <div>
        <h1 className="dash-h1">{title}</h1>
        {children && <p className="dash-lede">{children}</p>}
      </div>
      {actions && <div className="dash-head__actions">{actions}</div>}
    </header>
  );
}

export function ApiError({ error }: { error: string }) {
  return (
    <p className="dash-msg dash-msg--error" role="alert">
      {error}
    </p>
  );
}

export function Empty({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="dash-empty">
      <p className="dash-empty__title">{title}</p>
      {children && <p className="dash-muted">{children}</p>}
    </div>
  );
}

export function Badge({ tone = "plain", children }: { tone?: "plain" | "ok" | "warn" | "bad" | "info"; children: ReactNode }) {
  return <span className={`dash-badge dash-badge--${tone}`}>{children}</span>;
}

export function Section({ title, children, aside, id }: { title: string; children: ReactNode; aside?: ReactNode; id?: string }) {
  return (
    <section className="dash-section" aria-labelledby={id}>
      <div className="dash-section__head">
        <h2 className="dash-h2" id={id}>
          {title}
        </h2>
        {aside}
      </div>
      {children}
    </section>
  );
}

/** Shown when a role opens a page that is not for it. */
export function NotForRole({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <>
      <PageHead title={title} />
      <div className="dash-empty">
        <p className="dash-empty__title">This page is for someone else&rsquo;s job.</p>
        <p className="dash-muted">{children ?? "Use the menu at the top to find your screens."}</p>
      </div>
    </>
  );
}

/** Secondary actions, out of the way until asked for. One per card or page. */
export function More({ label = "More", children, align = "end" }: { label?: string; children: ReactNode; align?: "start" | "end" }) {
  return (
    <details className={`dash-more dash-more--${align}`}>
      <summary className="dash-more__btn">{label}</summary>
      <div className="dash-more__menu">{children}</div>
    </details>
  );
}

/** A section that stays quiet until opened, with one line saying what is inside. */
export function Fold({
  title,
  status,
  tone,
  children,
  open,
  id,
  group,
}: {
  title: string;
  status?: ReactNode;
  tone?: "warn" | "bad";
  children: ReactNode;
  open?: boolean;
  id?: string;
  /** Folds sharing a group open one at a time. */
  group?: string;
}) {
  return (
    <details className="dash-fold" open={open} id={id} name={group}>
      <summary className="dash-fold__head">
        <span className="dash-fold__title">{title}</span>
        {status != null && <span className={`dash-fold__status${tone ? ` is-${tone}` : ""}`}>{status}</span>}
      </summary>
      <div className="dash-fold__body">{children}</div>
    </details>
  );
}

/** A big number with a plain label under it. */
export function BigNumber({ value, label, tone, href }: { value: ReactNode; label: string; tone?: "warn" | "bad"; href?: string }) {
  const inner = (
    <>
      <span className={`dash-big__value tnum${tone ? ` is-${tone}` : ""}`}>{value}</span>
      <span className="dash-big__label">{label}</span>
    </>
  );
  return href ? (
    <Link className="dash-big" href={href}>
      {inner}
    </Link>
  ) : (
    <div className="dash-big">{inner}</div>
  );
}
