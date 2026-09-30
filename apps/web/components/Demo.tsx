import { demo, footer, site } from "@/content/copy";
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
          <p className="demo__contact">
            <span>{site.contactEmail}</span>
            <span>{site.whatsapp}</span>
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
