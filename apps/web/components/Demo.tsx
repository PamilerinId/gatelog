import { already, demo, footer, site } from "@/content/copy";
import { DemoForm } from "./DemoForm";
import { GateMark } from "./ui/icons";

export function Demo() {
  return (
    <section className="section section--alt" id="demo" aria-labelledby="demo-title">
      <div className="wrap demo indent">
        <div className="demo__copy">
          <h2 className="h2" id="demo-title">
            {demo.title}
          </h2>
          <p className="lede">{demo.body}</p>
          <div className="have">
            <h3 className="have__title">{already.title}</h3>
            <ul className="have__list">
              {already.items.map((t) => (
                <li className="have__item" key={t.k}>
                  <b>{t.k}</b>
                  <span>{t.v}</span>
                </li>
              ))}
            </ul>
          </div>
          <p className="demo__contact">
            <a href={`mailto:${site.contactEmail}`}>{site.contactEmail}</a>
            <a href={site.whatsappHref} target="_blank" rel="noopener noreferrer">
              {demo.whatsappLabel} {site.whatsapp}
            </a>
          </p>
        </div>
        <DemoForm />
      </div>
    </section>
  );
}

export function Footer() {
  return (
    <footer className="footer">
      <div className="wrap footer__inner">
        <div>
          <a className="brand" href="#top">
            <GateMark size={22} />
            <span>Gatelog</span>
          </a>
          <p>{site.tagline}</p>
        </div>
        <nav aria-label="Footer">
          {footer.links.map((l) => (
            <a key={l.href} href={l.href}>
              {l.label}
            </a>
          ))}
          <a href={site.privacyHref}>{site.privacyLabel}</a>
        </nav>
        <p>
          © {new Date().getFullYear()} {footer.credit}
        </p>
      </div>
    </footer>
  );
}
