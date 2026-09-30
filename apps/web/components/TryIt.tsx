"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { AnimatePresence, m, useAnimate } from "motion/react";
import { tryIt } from "@/content/copy";

type Result = "idle" | "ok" | "bad";

/**
 * Friday at the barrier, reduced to the idea: six digits, no network, one answer.
 * A real input sits invisibly over the slots, so phones open the number pad and paste works.
 * Runs entirely in the browser and accepts only the demo code.
 */
export function TryIt() {
  const [digits, setDigits] = useState("");
  const [online, setOnline] = useState(false);
  const [result, setResult] = useState<Result>("idle");
  const [slotsScope, animateSlots] = useAnimate<HTMLDivElement>();
  const input = useRef<HTMLInputElement>(null);
  const typing = useRef<ReturnType<typeof setTimeout>[]>([]);

  const check = useCallback(
    (code: string) => {
      if (code === tryIt.code) {
        setResult("ok");
      } else {
        setResult("bad");
        animateSlots(slotsScope.current, { x: [0, -8, 8, -6, 6, -3, 3, 0] }, { duration: 0.4 });
      }
    },
    [animateSlots, slotsScope],
  );

  const stopTyping = () => {
    typing.current.forEach(clearTimeout);
    typing.current = [];
  };

  const onChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    stopTyping();
    const next = e.target.value.replace(/\D/g, "").slice(0, 6);
    setDigits(next);
    if (next.length === 6) check(next);
    else setResult("idle");
  };

  const fillCode = () => {
    stopTyping();
    setDigits("");
    setResult("idle");
    tryIt.code.split("").forEach((_, i) => {
      typing.current.push(setTimeout(() => setDigits(tryIt.code.slice(0, i + 1)), 100 + i * 120));
    });
    typing.current.push(setTimeout(() => check(tryIt.code), 100 + 6 * 120 + 150));
  };

  const clear = () => {
    stopTyping();
    setDigits("");
    setResult("idle");
    input.current?.focus();
  };

  useEffect(() => stopTyping, []);

  const slotClass = (i: number) =>
    "check__slot" +
    (digits[i] ? " check__slot--on" : "") +
    (i === digits.length && result === "idle" ? " check__slot--next" : "") +
    (result === "ok" ? " check__slot--ok" : "") +
    (result === "bad" ? " check__slot--bad" : "");

  return (
    <section className="section band--navy tryit" id="try" aria-labelledby="try-title">
      <div className="wrap tryit__grid indent">
        <div className="tryit__copy hang">
          <p className="stamp">{tryIt.stamp}</p>
          <h2 className="h2" id="try-title">
            {tryIt.title}
          </h2>
          <p className="lede">{tryIt.body}</p>
          <p className="tryit__note">{tryIt.note}</p>
        </div>

        <div className="check">
          <div className="check__top">
            <label className="check__label" htmlFor="try-code">
              {tryIt.codeLabel}
            </label>
            <button type="button" className="net" aria-pressed={online} onClick={() => setOnline((o) => !o)}>
              <span className={online ? "net__track net__track--on" : "net__track"} aria-hidden="true">
                <m.span className="net__knob" layout transition={{ type: "spring", stiffness: 600, damping: 36 }} />
              </span>
              {tryIt.network}: {online ? tryIt.on : tryIt.off}
            </button>
          </div>

          <div className="check__slots" ref={slotsScope}>
            <input
              ref={input}
              id="try-code"
              className="check__input"
              type="text"
              inputMode="numeric"
              autoComplete="one-time-code"
              maxLength={6}
              value={digits}
              onChange={onChange}
              aria-describedby="try-result"
            />
            {Array.from({ length: 6 }).map((_, i) => (
              <span key={i} className={slotClass(i)} aria-hidden="true">
                <AnimatePresence>
                  {digits[i] ? (
                    <m.span initial={{ y: 10, opacity: 0 }} animate={{ y: 0, opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 0.15 }}>
                      {digits[i]}
                    </m.span>
                  ) : null}
                </AnimatePresence>
              </span>
            ))}
          </div>

          <div className="check__result" id="try-result" aria-live="polite">
            <AnimatePresence mode="wait" initial={false}>
              {result === "ok" ? (
                <m.p key="ok" className="check__verdict check__verdict--ok" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
                  <b>{tryIt.verified}</b>
                  <span>
                    {tryIt.guestLine}
                    {online ? null : ` ${tryIt.noNetwork}`}
                  </span>
                </m.p>
              ) : result === "bad" ? (
                <m.p key="bad" className="check__verdict check__verdict--bad" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
                  <b>{tryIt.refused}</b>
                  <span>{tryIt.refusedBody}</span>
                </m.p>
              ) : (
                <m.p key={online ? "on" : "off"} className="check__idle" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
                  {online ? tryIt.idleOnline : tryIt.idleOffline}
                </m.p>
              )}
            </AnimatePresence>
          </div>

          <div className="check__foot">
            <button type="button" className="link" onClick={fillCode}>
              {tryIt.useCode}
            </button>
            {digits ? (
              <button type="button" className="link check__clear" onClick={clear}>
                {tryIt.clear}
              </button>
            ) : null}
          </div>
        </div>
      </div>
    </section>
  );
}
