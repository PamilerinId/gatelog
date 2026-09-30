"use client";

import { useEffect, useState } from "react";
import { AnimatePresence, m } from "motion/react";
import { contrast } from "@/content/copy";
import { GateMark } from "../ui/icons";
import { EASE } from "../motion/ease";

const P = contrast.phone;

function Bars({ on }: { on: number }) {
  return (
    <span className="ps__bars" aria-hidden="true">
      {[4, 6, 8, 10].map((h, i) => (
        <i key={h} style={{ height: h }} className={i < on ? "is-on" : undefined} />
      ))}
    </span>
  );
}

function StatusBar({ time, offline }: { time: string; offline?: boolean }) {
  return (
    <div className="ps__status">
      <span className="ps__time">{time}</span>
      <span className="ps__icons">
        <Bars on={offline ? 0 : 4} />
        <span className="ps__battery" />
      </span>
    </div>
  );
}

/** 16:04. The resident's WhatsApp: the guest announced, the code sent back. */
function ChatScreen() {
  // typing dots, then the reply takes their place
  const [replied, setReplied] = useState(false);
  useEffect(() => {
    const t = setTimeout(() => setReplied(true), 1900);
    return () => clearTimeout(t);
  }, []);

  return (
    <div className="ps ps--chat">
      <div className="chat__head">
        <span className="chat__back" aria-hidden="true">‹</span>
        <span className="chat__avatar">
          <GateMark size={16} />
        </span>
        <span>
          <b>{P.chat.name}</b>
          <small>{P.chat.status}</small>
        </span>
      </div>
      <div className="chat__body">
        <m.p className="bubble bubble--out" initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.35, duration: 0.35, ease: EASE }}>
          {P.chat.out}
          <small>{P.chat.sent} ✓✓</small>
        </m.p>
        <AnimatePresence mode="wait">
          {replied ? (
            <m.p key="reply" className="bubble bubble--in" initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.3, ease: EASE }}>
              {P.chat.replyLead}
              <b>{P.chat.replyCode}</b>
              {P.chat.replyTail}
              <small>{P.chat.sent}</small>
            </m.p>
          ) : (
            <m.p key="typing" className="bubble bubble--typing" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ delay: 0.9, duration: 0.2 }}>
              <i />
              <i />
              <i />
            </m.p>
          )}
        </AnimatePresence>
      </div>
      <div className="chat__input">
        <span>{P.chat.input}</span>
        <i />
      </div>
    </div>
  );
}

/** 16:05. The guard's phone, no network: six digits in, one answer out. */
function GuardScreen() {
  return (
    <div className="ps ps--guard">
      <p className="guard__net">{P.guard.net}</p>
      <p className="guard__label">{P.guard.code}</p>
      <div className="guard__digits">
        {P.guard.digits.split("").map((d, i) => (
          <span key={i}>
            <m.span initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.3 + i * 0.16, duration: 0.18 }}>
              {d}
            </m.span>
          </span>
        ))}
      </div>
      <m.div className="guard__ok" initial={{ opacity: 0, scale: 0.96 }} animate={{ opacity: 1, scale: 1 }} transition={{ delay: 1.45, duration: 0.35, ease: EASE }}>
        <span>{P.guard.verified}</span>
        <b>{P.guard.guest}</b>
        <span>{P.guard.home}</span>
      </m.div>
      <m.div className="guard__actions" initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 1.8, duration: 0.3 }}>
        <span className="guard__admit">{P.guard.admit}</span>
        <span className="guard__away">{P.guard.away}</span>
      </m.div>
    </div>
  );
}

/** 16:06. The estate office log: the entry lands against the home it was for. */
function OfficeScreen() {
  return (
    <div className="ps ps--office">
      <p className="office__title">{P.office.title}</p>
      <m.div
        className="office__entry"
        initial={{ opacity: 0, y: -16, backgroundColor: "#dcebd2" }}
        animate={{ opacity: 1, y: 0, backgroundColor: ["#dcebd2", "#dcebd2", "#ffffff"] }}
        transition={{ delay: 0.4, duration: 0.45, ease: EASE, backgroundColor: { delay: 0.4, duration: 2.4, times: [0, 0.5, 1] } }}
      >
        <div className="office__row">
          <b>{P.office.name}</b>
          <span>{P.office.time}</span>
        </div>
        <span>{P.office.home}</span>
        <span>{P.office.gate}</span>
      </m.div>
      <p className="office__earlier">{P.office.earlier}</p>
      {[0, 1].map((k) => (
        <div className="office__ghost" key={k} aria-hidden="true">
          <i />
          <i />
        </div>
      ))}
      <div className="office__tabs" aria-hidden="true">
        <i className="is-on" />
        <i />
        <i />
        <i />
      </div>
    </div>
  );
}

const SCREENS = [ChatScreen, GuardScreen, OfficeScreen];

/** A generic current phone: thin bezel, island, side buttons. No maker's name or mark. */
export function Phone({ step }: { step: number }) {
  const Screen = SCREENS[step];
  const time = contrast.rows[step].time[1];
  return (
    <div className="phone" aria-hidden="true">
      <span className="phone__btn phone__btn--action" />
      <span className="phone__btn phone__btn--vol-up" />
      <span className="phone__btn phone__btn--vol-down" />
      <span className="phone__btn phone__btn--power" />
      <span className="phone__btn phone__btn--camera" />
      <div className="phone__screen">
        <span className="phone__island" />
        <StatusBar time={time} offline={step === 1} />
        <AnimatePresence mode="wait" initial={false}>
          <m.div
            key={step}
            className="phone__view"
            initial={{ opacity: 0, x: 18 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -18 }}
            transition={{ duration: 0.3, ease: EASE }}
          >
            <Screen />
          </m.div>
        </AnimatePresence>
        <span className="phone__home" />
      </div>
    </div>
  );
}
