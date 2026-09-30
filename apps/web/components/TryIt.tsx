"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { AnimatePresence, m, useAnimate } from "motion/react";
import { tryIt } from "@/content/copy";

type Result = "idle" | "ok" | "bad" | "logged";
const KEYS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "del", "0", "check"] as const;

/** Friday at the barrier: the guard's check, runnable in the browser. Accepts only the demo code. */
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
        animateRow(rowScope.current, { x: [0, -8, 8, -6, 6, -3, 3, 0] }, { duration: 0.4 });
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

  const verified = result === "ok" || result === "logged";
  const status = verified
    ? result === "logged"
      ? tryIt.logged
      : `${tryIt.verified}. ${tryIt.guest}, ${tryIt.home}.`
    : result === "bad"
      ? tryIt.refused
      : "";

  return (
    <section className="section band--navy tryit" id="try" aria-labelledby="try-title">
      <div className="wrap tryit__grid indent">
        <div className="tryit__copy hang">
          <p className="stamp">{tryIt.stamp}</p>
          <h2 className="h2" id="try-title">
            {tryIt.title}
          </h2>
          <p className="lede">{tryIt.body}</p>
          <button type="button" className="hint" onClick={fillHint}>
            <span className="hint__label">{tryIt.hintLabel}</span>
            <span className="hint__code">482 917</span>
            <span className="hint__go">{tryIt.useIt}</span>
          </button>
          <p className="tryit__note">{tryIt.note}</p>
        </div>

        <div className="device">
          <div className="device__screen" tabIndex={0} onKeyDown={onKeyDown} aria-label={tryIt.deviceLabel}>
            <div className="device__top">
              <span className="device__gate">{tryIt.gate}</span>
              <button type="button" className="net" aria-pressed={online} onClick={() => setOnline((o) => !o)}>
                <span className="net__label">
                  {tryIt.network}: {online ? tryIt.on : tryIt.off}
                </span>
                <span className={online ? "net__track net__track--on" : "net__track"}>
                  <m.span className="net__knob" layout transition={{ type: "spring", stiffness: 600, damping: 36 }} />
                </span>
              </button>
            </div>

            <p className="device__label">{tryIt.codeLabel}</p>
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
                      (verified ? " digit--ok" : "")
                    }
                  >
                    <AnimatePresence>
                      {d ? (
                        <m.span initial={{ y: 12, opacity: 0 }} animate={{ y: 0, opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 0.16 }}>
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
                {verified ? (
                  <m.div key="ok" className="verdict verdict--ok" initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }} transition={{ duration: 0.25 }}>
                    <div className="verdict__head">
                      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="square" aria-hidden="true">
                        <rect x="3" y="3" width="18" height="18" rx="1" />
                        <m.path d="M7.5 12.5l3 3 6-6.5" initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ duration: 0.35, delay: 0.1 }} />
                      </svg>
                      <b>{tryIt.verified}</b>
                    </div>
                    <span className="verdict__name">{tryIt.guest}</span>
                    <span className="verdict__meta">{tryIt.home}</span>
                    <span className="verdict__meta">{online ? tryIt.checkedOnline : tryIt.checkedOffline}</span>
                  </m.div>
                ) : result === "bad" ? (
                  <m.div key="bad" className="verdict verdict--bad" initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }} transition={{ duration: 0.25 }}>
                    <div className="verdict__head">
                      <b>{tryIt.refused}</b>
                    </div>
                    <span className="verdict__meta">{tryIt.refusedBody}</span>
                  </m.div>
                ) : (
                  <m.p key="idle" className="device__idle" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
                    {online ? tryIt.idleOnline : tryIt.idleOffline}
                  </m.p>
                )}
              </AnimatePresence>
            </div>

            <AnimatePresence mode="wait" initial={false}>
              {verified ? (
                <m.div key="actions" className="device__actions" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
                  <button type="button" className="btn btn--light" onClick={() => setResult("logged")} disabled={result === "logged"}>
                    {result === "logged" ? (online ? tryIt.loggedOnline : tryIt.loggedOffline) : tryIt.admit}
                  </button>
                  <button type="button" className="btn btn--line" onClick={reset}>
                    {tryIt.reset}
                  </button>
                </m.div>
              ) : (
                <m.div key="pad" className="keypad" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
                  {KEYS.map((k) => (
                    <button
                      key={k}
                      type="button"
                      className={k === "check" ? "key key--go" : k === "del" ? "key key--soft" : "key"}
                      onClick={() => press(k)}
                      aria-label={k === "del" ? tryIt.keyDelete : k === "check" ? tryIt.keyCheckLabel : k}
                    >
                      {k === "del" ? "⌫" : k === "check" ? tryIt.keyCheck : k}
                    </button>
                  ))}
                </m.div>
              )}
            </AnimatePresence>
          </div>
        </div>
      </div>
    </section>
  );
}
