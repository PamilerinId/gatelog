"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { AnimatePresence, m, useAnimate } from "motion/react";
import { tryIt } from "@/content/copy";
import { EASE, Item, Reveal } from "./motion/Reveal";

type Result = "idle" | "ok" | "bad" | "logged";
const KEYS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "del", "0", "check"] as const;

export function TryIt() {
  const [digits, setDigits] = useState("");
  const [online, setOnline] = useState(false);
  const [result, setResult] = useState<Result>("idle");
  const [rowScope, animateRow] = useAnimate<HTMLDivElement>();
  const typing = useRef<ReturnType<typeof setTimeout>[]>([]);

  const check = useCallback(
    (code: string) => {
      if (code.length < 6) return;
      if (code === tryIt.code) {
        setResult("ok");
      } else {
        setResult("bad");
        animateRow(rowScope.current, { x: [0, -10, 10, -8, 8, -4, 4, 0] }, { duration: 0.45 });
      }
    },
    [animateRow, rowScope],
  );

  const press = useCallback(
    (k: string) => {
      if (result === "ok" || result === "logged") return;
      if (k === "del") {
        setResult("idle");
        setDigits((d) => d.slice(0, -1));
        return;
      }
      if (k === "check") {
        check(digits);
        return;
      }
      if (result === "bad") {
        // a fresh digit after a refusal starts a new code
        setResult("idle");
        setDigits(k);
        return;
      }
      if (digits.length >= 6) return;
      const next = digits + k;
      setResult("idle");
      setDigits(next);
      if (next.length === 6) setTimeout(() => check(next), 180);
    },
    [digits, result, check],
  );

  const reset = () => {
    typing.current.forEach(clearTimeout);
    setDigits("");
    setResult("idle");
  };

  const fillHint = () => {
    reset();
    tryIt.code.split("").forEach((_, i) => {
      typing.current.push(setTimeout(() => setDigits(tryIt.code.slice(0, i + 1)), 120 + i * 130));
    });
    typing.current.push(setTimeout(() => check(tryIt.code), 120 + 6 * 130 + 200));
  };

  useEffect(() => () => typing.current.forEach(clearTimeout), []);

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (/^\d$/.test(e.key)) press(e.key);
    else if (e.key === "Backspace") press("del");
    else if (e.key === "Enter") press("check");
  };

  const status =
    result === "ok"
      ? `${tryIt.verified}. ${tryIt.guest}, ${tryIt.home}.`
      : result === "bad"
        ? tryIt.refused
        : result === "logged"
          ? "Entry logged."
          : "";

  return (
    <section className="section section--a tryit" id="try" aria-labelledby="try-title">
      <div className="wrap tryit__grid">
        <Reveal className="tryit__copy">
          <Item as="p" className="eyebrow">
            {tryIt.eyebrow}
          </Item>
          <Item as="h2" className="h2">
            <span id="try-title">{tryIt.title}</span>
          </Item>
          <Item as="p" className="lede">
            {tryIt.body}
          </Item>
          <Item>
            <button type="button" className="hint glass-lite" onClick={fillHint}>
              <span className="hint__label">{tryIt.hintLabel}</span>
              <span className="hint__code">482 917</span>
              <span className="hint__go">Use it</span>
            </button>
          </Item>
          <Item as="p" className="tryit__note">
            {tryIt.note}
          </Item>
        </Reveal>

        <m.div
          className="device glass"
          initial={{ opacity: 0, y: 40, rotate: -2 }}
          whileInView={{ opacity: 1, y: 0, rotate: 0 }}
          viewport={{ once: true, amount: 0.3 }}
          transition={{ duration: 0.9, ease: EASE }}
        >
          <div className="device__screen" tabIndex={0} onKeyDown={onKeyDown} aria-label="Guard’s code checker. Type digits, Enter to check.">
            <div className="device__top">
              <span className="device__gate">Main Gate</span>
              <button type="button" className="net" aria-pressed={online} onClick={() => setOnline((o) => !o)}>
                <span className="net__label">
                  {tryIt.network}: {online ? tryIt.on : tryIt.off}
                </span>
                <span className={online ? "net__track net__track--on" : "net__track"}>
                  <m.span className="net__knob" layout transition={{ type: "spring", stiffness: 600, damping: 32 }} />
                </span>
              </button>
            </div>

            <p className="device__label">Gate code</p>
            <div className="digits" ref={rowScope}>
              {Array.from({ length: 6 }).map((_, i) => {
                const d = digits[i];
                const active = i === digits.length && result === "idle";
                return (
                  <span
                    key={i}
                    className={
                      "digit" +
                      (d ? " digit--on" : "") +
                      (active ? " digit--active" : "") +
                      (result === "bad" ? " digit--bad" : "") +
                      (result === "ok" || result === "logged" ? " digit--ok" : "")
                    }
                  >
                    <AnimatePresence>
                      {d ? (
                        <m.span initial={{ y: 14, opacity: 0, scale: 0.8 }} animate={{ y: 0, opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.8 }} transition={{ type: "spring", stiffness: 520, damping: 26 }}>
                          {d}
                        </m.span>
                      ) : null}
                    </AnimatePresence>
                  </span>
                );
              })}
            </div>

            <div className="device__result" aria-live="polite">
              <span className="sr-only">{status}</span>
              <AnimatePresence mode="wait">
                {result === "ok" || result === "logged" ? (
                  <m.div
                    key="ok"
                    className="verdict verdict--ok"
                    initial={{ opacity: 0, y: 16, scale: 0.96 }}
                    animate={{ opacity: 1, y: 0, scale: 1 }}
                    exit={{ opacity: 0, y: -10 }}
                    transition={{ type: "spring", stiffness: 380, damping: 28 }}
                  >
                    <div className="verdict__head">
                      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                        <circle cx="12" cy="12" r="9" />
                        <m.path d="M8 12.5l2.8 2.8L16 9.8" initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ duration: 0.4, delay: 0.15 }} />
                      </svg>
                      <b>{tryIt.verified}</b>
                    </div>
                    <span className="verdict__name">{tryIt.guest}</span>
                    <span className="verdict__meta">{tryIt.home}</span>
                    <span className="verdict__meta">{online ? "Checked on this device." : "Checked on this device. No network used."}</span>
                  </m.div>
                ) : result === "bad" ? (
                  <m.div key="bad" className="verdict verdict--bad" initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -10 }}>
                    <div className="verdict__head">
                      <b>{tryIt.refused}</b>
                    </div>
                    <span className="verdict__meta">{tryIt.refusedBody}</span>
                  </m.div>
                ) : (
                  <m.p key="idle" className="device__idle" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
                    {online ? "Enter the six digits the guest shows you." : "The network is off. Enter the code anyway."}
                  </m.p>
                )}
              </AnimatePresence>
            </div>

            <AnimatePresence mode="wait" initial={false}>
              {result === "ok" || result === "logged" ? (
                <m.div key="actions" className="device__actions" initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }}>
                  <m.button
                    type="button"
                    className="btn btn--primary"
                    whileTap={{ scale: 0.97 }}
                    onClick={() => setResult("logged")}
                    disabled={result === "logged"}
                  >
                    {result === "logged" ? (online ? "Logged and synced" : "Logged · will sync") : tryIt.admit}
                  </m.button>
                  <button type="button" className="btn btn--line" onClick={reset}>
                    {tryIt.reset}
                  </button>
                </m.div>
              ) : (
                <m.div key="pad" className="keypad" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
                  {KEYS.map((k) => (
                    <m.button
                      key={k}
                      type="button"
                      className={k === "check" ? "key key--go" : k === "del" ? "key key--soft" : "key"}
                      whileTap={{ scale: 0.9 }}
                      onClick={() => press(k)}
                      aria-label={k === "del" ? "Delete" : k === "check" ? "Check code" : k}
                    >
                      {k === "del" ? "⌫" : k === "check" ? "Check" : k}
                    </m.button>
                  ))}
                </m.div>
              )}
            </AnimatePresence>
          </div>
        </m.div>
      </div>
    </section>
  );
}
