"use client";

import Image from "next/image";
import { useRef, useState } from "react";
import { m, useMotionValue, useSpring, useTransform } from "motion/react";
import { already, screens } from "@/content/copy";
import { EASE, Item, Reveal } from "./motion/Reveal";

function TiltFrame({ children }: { children: React.ReactNode }) {
  const x = useMotionValue(0);
  const y = useMotionValue(0);
  const rx = useSpring(useTransform(y, [-0.5, 0.5], [7, -7]), { stiffness: 200, damping: 20 });
  const ry = useSpring(useTransform(x, [-0.5, 0.5], [-9, 9]), { stiffness: 200, damping: 20 });
  const glareX = useTransform(x, [-0.5, 0.5], ["20%", "80%"]);

  return (
    <m.div
      className="screen__frame glass"
      style={{ rotateX: rx, rotateY: ry, transformPerspective: 900 }}
      onPointerMove={(e) => {
        if (e.pointerType !== "mouse") return;
        const r = e.currentTarget.getBoundingClientRect();
        x.set((e.clientX - r.left) / r.width - 0.5);
        y.set((e.clientY - r.top) / r.height - 0.5);
      }}
      onPointerLeave={() => {
        x.set(0);
        y.set(0);
      }}
    >
      {children}
      <m.span className="screen__glare" style={{ left: glareX }} aria-hidden="true" />
    </m.div>
  );
}

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
    <section className="section section--b" id="screens" aria-labelledby="screens-title">
      <div className="wrap">
        <Reveal className="section-head">
          <Item as="p" className="eyebrow">
            {screens.eyebrow}
          </Item>
          <Item as="h2" className="h2">
            <span id="screens-title">{screens.title}</span>
          </Item>
          <Item as="p" className="lede">
            {screens.body}
          </Item>
        </Reveal>
      </div>

      <div className="screens" ref={track} onScroll={onScroll}>
        {screens.items.map((s, i) => (
          <m.figure
            className="screen"
            key={s.label}
            initial={{ opacity: 0, y: 50 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true, amount: 0.25 }}
            transition={{ duration: 0.8, delay: i * 0.12, ease: EASE }}
          >
            <TiltFrame>
              <Image src={s.src} alt={s.alt} width={1140} height={2220} sizes="(max-width: 900px) 78vw, 340px" quality={85} />
            </TiltFrame>
            <figcaption>
              <span className="screen__label">{s.label}</span>
              <p>{s.body}</p>
            </figcaption>
          </m.figure>
        ))}
      </div>
      <div className="dots" role="group" aria-label="Choose a screen">
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
    <section className="section section--b" aria-labelledby="already-title">
      <div className="wrap">
        <Reveal className="section-head">
          <Item as="h2" className="h2">
            <span id="already-title">{already.title}</span>
          </Item>
        </Reveal>
        <Reveal as="ul" className="tiles" gap={0.1}>
          {already.items.map((t) => (
            <Item as="li" className="tile glass" key={t.k}>
              <b>{t.k}</b>
              <p>{t.v}</p>
            </Item>
          ))}
        </Reveal>
      </div>
    </section>
  );
}
