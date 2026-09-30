"use client";

import Image from "next/image";
import { useRef, useState } from "react";
import { m } from "motion/react";
import { already, screens } from "@/content/copy";

export function Screens() {
  const track = useRef<HTMLDivElement>(null);
  const [active, setActive] = useState(0);

  const onScroll = () => {
    const el = track.current;
    if (!el) return;
    const i = Math.round(el.scrollLeft / (el.scrollWidth / screens.items.length));
    setActive(Math.min(screens.items.length - 1, Math.max(0, i)));
  };
  const go = (i: number) => {
    const el = track.current;
    if (!el) return;
    el.scrollTo({ left: (el.scrollWidth / screens.items.length) * i, behavior: "smooth" });
  };

  return (
    <section className="section" id="screens" aria-labelledby="screens-title">
      <div className="wrap">
        <header className="section-head indent">
          <h2 className="h2" id="screens-title">
            {screens.title}
          </h2>
          <p className="lede">{screens.body}</p>
        </header>
      </div>

      <div className="screens" ref={track} onScroll={onScroll}>
        {screens.items.map((s) => (
          <figure className="screen" key={s.label}>
            <div className="screen__frame">
              <Image src={s.src} alt={s.alt} width={1140} height={2220} sizes="(max-width: 900px) 78vw, 400px" quality={85} />
            </div>
            <figcaption>
              <span className="screen__label">{s.label}</span>
              <p>{s.body}</p>
            </figcaption>
          </figure>
        ))}
      </div>
      <div className="dots" role="group" aria-label={screens.choose}>
        {screens.items.map((s, i) => (
          <button key={s.label} type="button" className="dots__btn" aria-label={s.label} aria-current={active === i} onClick={() => go(i)}>
            {active === i ? <m.span layoutId="dot-active" className="dots__active" /> : <span className="dots__dot" />}
          </button>
        ))}
      </div>
    </section>
  );
}

export function Already() {
  return (
    <section className="section" aria-labelledby="already-title">
      <div className="wrap">
        <header className="section-head indent">
          <h2 className="h2" id="already-title">
            {already.title}
          </h2>
        </header>
        <ul className="tiles">
          {already.items.map((t) => (
            <li className="tile" key={t.k}>
              <h3>{t.k}</h3>
              <p>{t.v}</p>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
