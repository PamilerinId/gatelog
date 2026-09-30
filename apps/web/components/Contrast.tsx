"use client";

import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import { AnimatePresence, m, useInView, useReducedMotion } from "motion/react";
import { contrast } from "@/content/copy";
import { GateMark } from "./ui/icons";
import { EASE } from "./motion/ease";
import { SceneArrival, SceneBook, SceneCall } from "./story/Scenes";
import { Phone } from "./story/Phone";
import { NetworkLines } from "./story/NetworkLines";

// Line drawings stand in until the illustrations are in public/images/scenes/.
const PLACEHOLDERS = [SceneArrival, SceneCall, SceneBook];
// how long each phone screen holds before the next, in ms
const HOLD = [4400, 4200, 4000];

/**
 * Before and after as one picture: three comic panels of the evening without Gatelog
 * form a small network into the mark, which feeds the phone and its three screens.
 */
export function Contrast({ art }: { art: (string | null)[] }) {
  const box = useRef<HTMLDivElement>(null);
  const panels = useRef<(HTMLDivElement | null)[]>([]);
  const hub = useRef<HTMLSpanElement>(null);
  const phone = useRef<HTMLDivElement>(null);

  const inView = useInView(box, { amount: 0.3 });
  const reduce = useReducedMotion() ?? false;
  const [step, setStep] = useState(0);
  const [manual, setManual] = useState(false);
  const run = inView && !reduce;
  const auto = run && !manual;

  useEffect(() => {
    if (!auto) return;
    const t = setTimeout(() => setStep((s) => (s + 1) % 3), HOLD[step]);
    return () => clearTimeout(t);
  }, [auto, step]);

  const pick = (i: number) => {
    setManual(true);
    setStep(i);
  };

  const row = contrast.rows[step];

  return (
    <section className="section contrast" id="gate" aria-labelledby="contrast-title">
      <div className="wrap">
        <div className="story" ref={box}>
          <NetworkLines box={box} nodes={panels} hub={hub} phone={phone} run={run} />

          <header className="story__intro">
            <p className="stamp">{contrast.stamp}</p>
            <h2 className="h2" id="contrast-title">
              {contrast.title}
            </h2>
          </header>

          <div className="story__scenes">
            <p className="story__label story__label--without">{contrast.without}</p>
            <ol className="panels">
              {contrast.rows.map((r, i) => {
                const Art = PLACEHOLDERS[i];
                const src = art[i];
                return (
                  <li className="panel-item" key={r.label}>
                    <div
                      className="comic"
                      ref={(el) => {
                        panels.current[i] = el;
                      }}
                    >
                      {src ? <Image src={src} alt={r.before.body} fill sizes="(max-width: 719px) 30vw, 260px" quality={80} /> : <Art label={r.before.body} />}
                    </div>
                    <p className="narration">
                      <b>{r.time[0]}</b>
                      {r.before.title}
                    </p>
                  </li>
                );
              })}
            </ol>
          </div>

          <div className="story__hub" aria-hidden="true">
            <span className="hub" ref={hub}>
              {run ? (
                <m.span className="hub__ring" initial={{ opacity: 0.55, scale: 1 }} animate={{ opacity: 0, scale: 1.7 }} transition={{ duration: 1.8, ease: "easeOut", repeat: Infinity }} />
              ) : null}
              <GateMark size={26} />
            </span>
          </div>

          <div className="story__phone">
            <p className="story__label story__label--with">{contrast.with}</p>
            <div ref={phone}>
              <Phone step={step} />
            </div>
          </div>

          <div className="story__after">
            <div className="steps" role="group" aria-label={contrast.phone.choose}>
              {contrast.phone.labels.map((label, i) => (
                <button key={label} type="button" className="step" aria-pressed={step === i} onClick={() => pick(i)}>
                  <span className="step__bar">
                    {step === i ? (
                      <m.span
                        key={`${i}-${auto}`}
                        initial={{ scaleX: auto ? 0 : 1 }}
                        animate={{ scaleX: 1 }}
                        transition={{ duration: auto ? HOLD[i] / 1000 : 0, ease: "linear" }}
                      />
                    ) : null}
                  </span>
                  {label}
                </button>
              ))}
            </div>
            <AnimatePresence mode="wait" initial={false}>
              <m.div
                key={step}
                className="story__caption"
                aria-hidden="true"
                initial={{ opacity: 0, y: 6 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0 }}
                transition={{ duration: 0.25, ease: EASE }}
              >
                <span className="story__time">{row.time[1]}</span>
                <h3>{row.after.title}</h3>
                <p>{row.after.body}</p>
              </m.div>
            </AnimatePresence>
            {/* the whole "with" sequence for screen readers, not just the visible step */}
            <ol className="sr-only">
              {contrast.rows.map((r) => (
                <li key={r.label}>
                  {r.time[1]}. {r.after.title} {r.after.body}
                </li>
              ))}
            </ol>
          </div>
        </div>
      </div>
    </section>
  );
}
