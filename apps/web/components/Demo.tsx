import { demo, site } from "@/content/copy";
import { DemoForm } from "./DemoForm";
import { GateMark } from "./ui/icons";

export function Demo() {
  return (
    <section className="section section--a" id="demo" aria-labelledby="demo-title">
      <div className="wrap">
        <div className="demo glass reveal-settle">
          <div className="demo__copy">
            <p className="eyebrow">{demo.eyebrow}</p>
            <h2 id="demo-title">{demo.title}</h2>
            <p className="lede">{demo.body}</p>
            <p className="demo__contact">
              {site.contactEmail} · {site.whatsapp}
            </p>
          </div>
          <DemoForm />
        </div>
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
          <a href="#screens">The screens</a>
          <a href="#demo">Book a demo</a>
          <a href={site.privacyHref}>{site.privacyLabel}</a>
        </nav>
        <p>© {new Date().getFullYear()} Gatelog. Built by PI Technologies.</p>
      </div>
    </footer>
  );
}
