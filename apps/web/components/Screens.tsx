import Image from "next/image";
import { screens, already } from "@/content/copy";

export function Screens() {
  return (
    <section className="section section--b" id="screens" aria-labelledby="screens-title">
      <div className="wrap">
        <div className="section-head reveal">
          <p className="eyebrow">{screens.eyebrow}</p>
          <h2 className="h2" id="screens-title" style={{ maxWidth: "22ch" }}>
            {screens.title}
          </h2>
          <p className="lede">{screens.body}</p>
        </div>

        <div className="screens">
          {screens.items.map((s) => (
            <figure className="screen reveal-settle" key={s.label} style={{ margin: 0 }}>
              <div className="screen__frame glass">
                <Image src={s.src} alt={s.alt} width={1140} height={2220} sizes="(max-width: 900px) 90vw, 340px" quality={85} />
              </div>
              <figcaption>
                <span className="screen__label">{s.label}</span>
                <p>{s.body}</p>
              </figcaption>
            </figure>
          ))}
        </div>
      </div>
    </section>
  );
}

export function Already() {
  return (
    <section className="section section--b" aria-labelledby="already-title">
      <div className="wrap">
        <div className="section-head reveal">
          <h2 className="h2" id="already-title">
            {already.title}
          </h2>
        </div>
        <ul className="tiles" style={{ listStyle: "none", margin: 0, padding: 0 }}>
          {already.items.map((t) => (
            <li className="tile glass reveal-settle" key={t.k}>
              <b>{t.k}</b>
              <p>{t.v}</p>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
