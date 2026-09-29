"use client";

import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import { AnimatePresence, m, useReducedMotion, useScroll, useTransform } from "motion/react";
import { hero } from "@/content/copy";
import { ArrowRight } from "./ui/icons";
import { EASE } from "./motion/Reveal";
import { useMedia } from "./motion/useMedia";

const DIGITS = ["4", "8", "2", "9", "1", "7"];
type Phase = "typing" | "checking" | "verified";

/** The chip over the photo replays a real verification: digits in, check, result. */
function VerifyChip() {
  const reduce = useReducedMotion();
  const [count, setCount] = useState(reduce ? 6 : 0);
  const [phase, setPhase] = useState<Phase>(reduce ? "verified" : "typing");

  useEffect(() => {
    if (reduce) return;
    let timers: ReturnType<typeof setTimeout>[] = [];
    const run = () => {
      timers.forEach(clearTimeout);
      timers = [];
      setPhase("typing");
      setCount(0);
      DIGITS.forEach((_, i) => timers.push(setTimeout(() => setCount(i + 1), 900 + i * 170)));
      timers.push(setTimeout(() => setPhase("checking"), 900 + 6 * 170 + 150));
      timers.push(setTimeout(() => setPhase("verified"), 900 + 6 * 170 + 900));
      timers.push(setTimeout(run, 9500));
    };
    run();
    return () => timers.forEach(clearTimeout);
  }, [reduce]);

  return (
    <m.div
      className="hero__chip"
      aria-hidden="true"
      initial={{ opacity: 0, y: 20, scale: 0.96 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      transition={{ delay: 0.7, duration: 0.8, ease: EASE }}
    >
      <div className="chip__top">
        <span className="chip__gate">Main Gate</span>
        <span className="chip__net">No network</span>
      </div>
      <div className="chip__digits">
        {DIGITS.map((d, i) => (
          <span key={i} className={i < count ? "chip__digit chip__digit--on" : "chip__digit"}>
            <AnimatePresence>
              {i < count ? (
                <m.span initial={{ y: 12, opacity: 0 }} animate={{ y: 0, opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 0.18 }}>
                  {d}
                </m.span>
              ) : null}
            </AnimatePresence>
          </span>
        ))}
      </div>
      <div className="chip__result">
        <AnimatePresence mode="wait" initial={false}>
          {phase === "verified" ? (
            <m.div key="ok" className="chip__ok" initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }}>
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
                <circle cx="12" cy="12" r="9" />
                <m.path d="M8 12.5l2.8 2.8L16 9.8" initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ duration: 0.45, delay: 0.1 }} />
              </svg>
              <div>
                <b>{hero.chip.label}</b>
                <span>{hero.chip.name}</span>
              </div>
            </m.div>
          ) : (
            <m.div key="wait" className="chip__wait" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
              <span className={phase === "checking" ? "spinner" : "spinner spinner--idle"} />
              {phase === "checking" ? "Checking signature on this device" : "Guard enters the code"}
            </m.div>
          )}
        </AnimatePresence>
      </div>
    </m.div>
  );
}

export function Hero() {
  const ref = useRef<HTMLElement>(null);
  const wide = useMedia("(min-width: 901px)");
  const { scrollYProgress } = useScroll({ target: ref, offset: ["start start", "end start"] });
  const imgScale = useTransform(scrollYProgress, [0, 1], [1.02, 1.18]);
  const imgY = useTransform(scrollYProgress, [0, 1], ["0%", "12%"]);
  const copyY = useTransform(scrollYProgress, [0, 1], [0, wide ? -80 : 0]);
  const copyOpacity = useTransform(scrollYProgress, [0, 0.7], [1, wide ? 0 : 1]);

  const lead = hero.titleLead.split(" ");
  const accent = hero.titleAccent.split(" ");

  return (
    <section className="hero" id="top" ref={ref} aria-labelledby="hero-title">
      <m.div className="hero__media" style={{ scale: imgScale, y: imgY }}>
        <Image
          className="hero__img"
          src="/images/hero-gate-phone.jpg"
          alt="A resident holds a phone at the entrance of a gated estate at dusk. On screen, the Gatelog chat: a guest announced, a gate code issued, and the arrival confirmed."
          fill
          priority
          sizes="100vw"
          quality={82}
        />
      </m.div>
      <div className="hero__shade" aria-hidden="true" />

      <VerifyChip />

      <m.div className="hero__inner" style={{ y: copyY, opacity: copyOpacity }}>
        <m.div className="hero__copy" initial="hidden" animate="show" variants={{ show: { transition: { staggerChildren: 0.05, delayChildren: 0.15 } } }}>
          <m.p className="hero__badge" variants={{ hidden: { opacity: 0, y: 10 }, show: { opacity: 1, y: 0 } }}>
            <span className="dot pulse" aria-hidden="true" />
            {hero.eyebrow}
          </m.p>
          <h1 id="hero-title" aria-label={`${hero.titleLead} ${hero.titleAccent}`}>
            {[...lead.map((w) => ({ w, a: false })), ...accent.map((w) => ({ w, a: true }))].map(({ w, a }, i) => (
              <span className="word" key={i} aria-hidden="true">
                <m.span
                  className={a ? "word__in word__in--accent" : "word__in"}
                  variants={{ hidden: { y: "110%" }, show: { y: "0%", transition: { duration: 0.8, ease: EASE } } }}
                >
                  {w}
                </m.span>
              </span>
            ))}
          </h1>
          <m.p className="hero__body" variants={{ hidden: { opacity: 0, y: 14 }, show: { opacity: 1, y: 0, transition: { duration: 0.7, ease: EASE } } }}>
            {hero.body}
          </m.p>
          <m.div className="hero__ctas" variants={{ hidden: { opacity: 0, y: 14 }, show: { opacity: 1, y: 0, transition: { duration: 0.7, ease: EASE } } }}>
            <m.a className="btn btn--primary" href="#demo" whileHover={{ y: -2 }} whileTap={{ scale: 0.97 }}>
              {hero.primary}
            </m.a>
            <a className="btn btn--ghost" href="#gate">
              See the difference
              <ArrowRight />
            </a>
          </m.div>
        </m.div>

        <m.ul
          className="hero__facts"
          role="list"
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 1.1, duration: 0.8, ease: EASE }}
        >
          {hero.facts.map((f) => (
            <li className="hero__fact" key={f.v}>
              <strong>{f.k}</strong>
              <span>{f.v}</span>
            </li>
          ))}
        </m.ul>
      </m.div>
    </section>
  );
}
