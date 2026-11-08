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
