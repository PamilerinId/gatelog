"use client";

import { useEffect, useRef, useState } from "react";
import { AnimatePresence, m, useInView } from "motion/react";
import { contrast } from "@/content/copy";
import { EASE } from "./motion/ease";

type Mode = "before" | "after";

function Glyph({ mode }: { mode: Mode }) {
  return (
    <span className={mode === "after" ? "glyph glyph--ok" : "glyph glyph--warn"} aria-hidden="true">
      {mode === "after" ? (
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="square">
          <path d="M5 12.5l4.5 4.5L19 7.5" />
        </svg>
      ) : (
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="square">
          <path d="M12 6v8" />
          <path d="M12 18v.01" />
        </svg>
      )}
    </span>
  );
}

/** The same three moments, logged twice: the evening without Gatelog and the evening with it. */
export function Contrast() {
  const [mode, setMode] = useState<Mode>("before");
  const touched = useRef(false);
  const ref = useRef<HTMLOListElement>(null);
  const seen = useInView(ref, { amount: 0.5, once: true });

  // First time the reader reaches the ledger, flip once to show the change, unless they already did.
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
    <section className="section contrast" id="gate" aria-labelledby="contrast-title">
      <div className="wrap">
        <header className="section-head indent hang">
          <p className="stamp">{contrast.stamp}</p>
          <h2 className="h2" id="contrast-title">
            {contrast.title}
          </h2>
        </header>

        <div className="switch-wrap">
          <div className="switch" role="group" aria-label={contrast.group}>
            {(["before", "after"] as const).map((k) => (
              <button key={k} type="button" className="switch__btn" aria-pressed={mode === k} onClick={() => pick(k)}>
                {mode === k ? <m.span layoutId="switch-pill" className="switch__pill" transition={{ type: "spring", stiffness: 420, damping: 36 }} /> : null}
                <span className="switch__label">{k === "before" ? contrast.without : contrast.with}</span>
              </button>
            ))}
          </div>
        </div>

        <ol ref={ref} className="ledger" aria-live="polite">
          {contrast.rows.map((r, i) => {
            const side = mode === "after" ? r.after : r.before;
            const time = r.time[mode === "after" ? 1 : 0];
            return (
              <li key={r.label} className="ledger__row">
                <span className="ledger__time">
                  <AnimatePresence mode="popLayout" initial={false}>
                    <m.span
                      key={time}
                      initial={{ y: "100%", opacity: 0 }}
                      animate={{ y: 0, opacity: 1 }}
                      exit={{ y: "-100%", opacity: 0 }}
                      transition={{ duration: 0.35, delay: i * 0.06, ease: EASE }}
                    >
                      {time}
                    </m.span>
                  </AnimatePresence>
                </span>
                <div className="ledger__main">
                  <p className="ledger__label">
                    <Glyph mode={mode} />
                    {r.label}
                  </p>
                  <AnimatePresence mode="wait" initial={false}>
                    <m.div
                      key={mode}
                      className="ledger__text"
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 1 }}
                      exit={{ opacity: 0 }}
                      transition={{ duration: 0.25, delay: i * 0.06 }}
                    >
                      <h3>{side.title}</h3>
                      <p>{side.body}</p>
                    </m.div>
                  </AnimatePresence>
                </div>
              </li>
            );
          })}
        </ol>
      </div>
    </section>
  );
}
