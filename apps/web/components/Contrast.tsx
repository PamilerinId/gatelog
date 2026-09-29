"use client";

import { useEffect, useRef, useState } from "react";
import { AnimatePresence, m, useInView } from "motion/react";
import { contrast } from "@/content/copy";
import { EASE, Item, Reveal } from "./motion/Reveal";

type Mode = "before" | "after";

function Glyph({ mode }: { mode: Mode }) {
  return (
    <AnimatePresence mode="wait" initial={false}>
      <m.span
        key={mode}
        className={mode === "after" ? "glyph glyph--ok" : "glyph glyph--warn"}
        initial={{ scale: 0.4, opacity: 0, rotate: -40 }}
        animate={{ scale: 1, opacity: 1, rotate: 0 }}
        exit={{ scale: 0.4, opacity: 0, rotate: 40 }}
        transition={{ type: "spring", stiffness: 420, damping: 22 }}
        aria-hidden="true"
      >
        {mode === "after" ? (
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round">
            <path d="M5 12.5l4.5 4.5L19 7.5" />
          </svg>
        ) : (
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round">
            <path d="M12 7v6" />
            <path d="M12 17h.01" />
          </svg>
        )}
      </m.span>
    </AnimatePresence>
  );
}

export function Contrast() {
  const [mode, setMode] = useState<Mode>("before");
  const touched = useRef(false);
  const ref = useRef<HTMLDivElement>(null);
  const seen = useInView(ref, { amount: 0.5, once: true });

  // First time the reader reaches the cards, flip once to show the change, unless they already did.
  useEffect(() => {
    if (!seen) return;
    const t = setTimeout(() => {
      if (!touched.current) setMode("after");
    }, 3200);
    return () => clearTimeout(t);
  }, [seen]);

  const pick = (next: Mode) => {
    touched.current = true;
    setMode(next);
  };

  return (
    <section className={`section contrast contrast--${mode}`} id="gate" aria-labelledby="contrast-title">
      <m.div
        className="contrast__tint"
        aria-hidden="true"
        animate={{ opacity: mode === "after" ? 1 : 0 }}
        transition={{ duration: 0.9, ease: EASE }}
      />
      <div className="wrap">
        <Reveal className="section-head">
          <Item as="p" className="eyebrow">
            {contrast.eyebrow}
          </Item>
          <Item as="h2" className="h2">
            <span id="contrast-title">{contrast.title}</span>
          </Item>
        </Reveal>

        <div className="switch-wrap">
          <div className="switch glass" role="group" aria-label="Compare the evening without and with Gatelog">
            {(["before", "after"] as const).map((k) => (
              <button key={k} type="button" className="switch__btn" aria-pressed={mode === k} onClick={() => pick(k)}>
                {mode === k ? (
                  <m.span layoutId="switch-pill" className={k === "after" ? "switch__pill switch__pill--ok" : "switch__pill"} transition={{ type: "spring", stiffness: 420, damping: 34 }} />
                ) : null}
                <span className="switch__label">{k === "before" ? contrast.without : contrast.with}</span>
              </button>
            ))}
          </div>
        </div>

        <div ref={ref} className="contrast__rows" aria-live="polite">
          {contrast.rows.map((r, i) => {
            const side = mode === "after" ? r.after : r.before;
            const time = r.time[mode === "after" ? 1 : 0];
            return (
              <m.article
                key={r.label}
                className="row glass"
                initial={{ opacity: 0, y: 30 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, amount: 0.3 }}
                transition={{ duration: 0.7, delay: i * 0.08, ease: EASE }}
              >
                <div className="row__meta">
                  <Glyph mode={mode} />
                  <span className="row__label">{r.label}</span>
                  <span className="row__time">
                    <AnimatePresence mode="popLayout" initial={false}>
                      <m.span key={time} initial={{ y: 14, opacity: 0 }} animate={{ y: 0, opacity: 1 }} exit={{ y: -14, opacity: 0 }} transition={{ duration: 0.3 }}>
                        {time}
                      </m.span>
                    </AnimatePresence>
                  </span>
                </div>
                <AnimatePresence mode="wait" initial={false}>
                  <m.div
                    key={mode}
                    className="row__text"
                    initial={{ opacity: 0, y: mode === "after" ? 18 : -18, filter: "blur(6px)" }}
                    animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
                    exit={{ opacity: 0, y: mode === "after" ? -18 : 18, filter: "blur(6px)" }}
                    transition={{ duration: 0.38, delay: i * 0.06, ease: EASE }}
                  >
                    <h3>{side.title}</h3>
                    <p>{side.body}</p>
                  </m.div>
                </AnimatePresence>
              </m.article>
            );
          })}
        </div>
      </div>
    </section>
  );
}
