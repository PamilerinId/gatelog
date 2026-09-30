"use client";

import Image from "next/image";
import { useEffect, useState } from "react";
import { AnimatePresence, m, useReducedMotion } from "motion/react";
import { hero } from "@/content/copy";
import { EASE } from "./motion/ease";

const DIGITS = ["4", "8", "2", "9", "1", "7"];
type Phase = "typing" | "checking" | "verified";

/** The chip over the photo replays a real verification: digits in, check, result. The page's one unprompted motion. */
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
      timers.push(setTimeout(() => setPhase("verified"), 900 + 6 * 170 + 950));
      timers.push(setTimeout(run, 9500));
    };
    run();
    return () => timers.forEach(clearTimeout);
  }, [reduce]);

  return (
    <m.div
      className="hero__chip glass glass--navy"
      aria-hidden="true"
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.6, duration: 0.8, ease: EASE }}
    >
      <div className="chip__top">
        <span>{hero.chip.gate}</span>
        <span className="chip__net">
          <i />
          {hero.chip.net}
        </span>
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
            <m.div key="ok" className="chip__ok" initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }}>
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="square" strokeLinejoin="miter">
                <rect x="3" y="3" width="18" height="18" rx="1" />
                <m.path d="M7.5 12.5l3 3 6-6.5" initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ duration: 0.4, delay: 0.1 }} />
              </svg>
              <div>
                <b>{hero.chip.label}</b>
                <span>{hero.chip.name}</span>
              </div>
            </m.div>
          ) : (
            <m.div key="wait" className="chip__wait" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
              {phase === "checking" ? hero.chip.checking : hero.chip.waiting}
              <span className="chip__bar">
                <m.span
                  initial={{ scaleX: 0 }}
                  animate={{ scaleX: phase === "checking" ? 1 : 0 }}
                  transition={{ duration: phase === "checking" ? 0.75 : 0, ease: "linear" }}
                />
              </span>
            </m.div>
          )}
        </AnimatePresence>
      </div>
    </m.div>
  );
}

export function Hero() {
  return (
    <section className="hero" id="top" aria-labelledby="hero-title">
      <div className="hero__media">
        <Image
          className="hero__img"
          src="/images/hero-gate-phone.jpg"
          alt="A resident holds a phone at the entrance of a gated estate at dusk. On screen, the Gatelog chat: a guest announced, a gate code issued, and the arrival confirmed."
          fill
          priority
          sizes="100vw"
          quality={82}
        />
      </div>
      <div className="hero__shade" aria-hidden="true" />

      <VerifyChip />

      <div className="hero__inner">
        <div className="hero__copy">
          <p className="hero__kicker">{hero.eyebrow}</p>
          <h1 id="hero-title">{hero.title}</h1>
          <p className="hero__body">{hero.body}</p>
          <div className="hero__ctas">
            <a className="btn btn--light" href="#demo">
              {hero.primary}
            </a>
            <a className="link" href="#gate">
              {hero.secondary}
            </a>
          </div>
        </div>
      </div>
    </section>
  );
}
