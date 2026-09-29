import Image from "next/image";
import { hero } from "@/content/copy";
import { ArrowRight, CheckCircle } from "./ui/icons";

export function Hero() {
  return (
    <section className="hero" id="top" aria-labelledby="hero-title">
      <Image
        className="hero__img"
        src="/images/hero-gate-phone.jpg"
        alt="A resident holds a phone at the entrance of a gated estate at dusk. On screen, the Gatelog chat: a guest announced, a gate code issued, and the arrival confirmed."
        fill
        priority
        sizes="100vw"
        quality={82}
      />
      <div className="hero__shade" aria-hidden="true" />

      <div className="hero__chip" aria-hidden="true">
        <CheckCircle />
        <div>
          <b>{hero.chip.label}</b>
          <span>{hero.chip.name}</span>
          <small>{hero.chip.meta}</small>
        </div>
      </div>

      <div className="hero__inner">
        <div className="hero__copy">
          <p className="hero__badge">
            <span className="dot pulse" aria-hidden="true" />
            {hero.eyebrow}
          </p>
          <h1 id="hero-title">
            {hero.titleLead} <span>{hero.titleAccent}</span>
          </h1>
          <p className="hero__body">{hero.body}</p>
          <div className="hero__ctas">
            <a className="btn btn--primary" href="#demo">
              {hero.primary}
            </a>
            <a className="btn btn--ghost" href="#screens">
              {hero.secondary}
              <ArrowRight />
            </a>
          </div>
        </div>

        <ul className="hero__facts" role="list" style={{ listStyle: "none", margin: 0, padding: 0 }}>
          {hero.facts.map((f) => (
            <li className="hero__fact" key={f.v}>
              <strong>{f.k}</strong>
              <span>{f.v}</span>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
