import { demo, site } from "@/content/copy";
import { DemoForm } from "./DemoForm";
import { GateMark } from "./ui/icons";
import { Item, Reveal } from "./motion/Reveal";

export function Demo() {
  return (
    <section className="section section--a" id="demo" aria-labelledby="demo-title">
      <div className="wrap">
        <Reveal className="demo glass" amount={0.2}>
          <div className="demo__copy">
            <Item as="p" className="eyebrow">
              {demo.eyebrow}
            </Item>
            <Item as="h2">
              <span id="demo-title">{demo.title}</span>
            </Item>
            <Item as="p" className="lede">
              {demo.body}
            </Item>
            <Item as="p" className="demo__contact">
              {site.contactEmail} · {site.whatsapp}
            </Item>
          </div>
          <Item>
            <DemoForm />
          </Item>
        </Reveal>
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
