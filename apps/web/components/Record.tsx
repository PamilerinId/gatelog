"use client";

import { useEffect, useRef, useState } from "react";
import { animate, m, useInView, useReducedMotion } from "motion/react";
import { record } from "@/content/copy";
import { GateMark } from "./ui/icons";
import { EASE, Item, Reveal } from "./motion/Reveal";

function CountUp({ to }: { to: number }) {
  const ref = useRef<HTMLSpanElement>(null);
  const inView = useInView(ref, { once: true, amount: 0.6 });
  const reduce = useReducedMotion();
  const [v, setV] = useState(0);
  useEffect(() => {
    if (!inView) return;
    if (reduce) {
      setV(to);
      return;
    }
    const c = animate(0, to, { duration: 1.4, ease: EASE, onUpdate: (x) => setV(Math.round(x)) });
    return () => c.stop();
  }, [inView, to, reduce]);
  return <span ref={ref}>{v}</span>;
}

const HOURS = ["10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "20", "21"];

function ArrivalsChart({ values }: { values: number[] }) {
  const W = 640;
  const top = 10;
  const base = 170;
  const left = 36;
  const max = 30;
  const step = (W - left) / values.length;
  const barW = step * 0.62;
  const y = (v: number) => base - (v / max) * (base - top);
  const peakFrom = left + step * 6;
  const peakTo = left + step * 9;

  return (
    <svg
      className="chart"
      viewBox={`0 0 ${W} 200`}
      role="img"
      aria-label="Sample chart of arrivals by hour on a Friday: low through the morning, rising from 14:00, peaking at 27 arrivals in the 17:00 hour, then falling after 19:00."
    >
      <g stroke="rgba(180,225,200,0.14)" strokeWidth={1}>
        {[0, 10, 20, 30].map((t) => (
          <line key={t} x1={left} x2={W} y1={y(t)} y2={y(t)} />
        ))}
      </g>
      <g fill="#a3b8ac" fontFamily="DM Mono, monospace" fontSize={11}>
        {[10, 20, 30].map((t) => (
          <text key={t} x={0} y={y(t) + 4}>
            {t}
          </text>
        ))}
      </g>
      <rect x={peakFrom} y={top} width={peakTo - peakFrom} height={base - top} fill="rgba(232,176,117,0.07)" rx={6} />
      <line x1={peakFrom} x2={peakTo} y1={top} y2={top} stroke="#E8B075" strokeDasharray="5 6" strokeOpacity={0.8} />
      <g fill="#6FD8A6">
        {values.map((v, i) => (
          <m.rect
            key={i}
            className="cbar"
            x={left + i * step + (step - barW) / 2}
            y={y(v)}
            width={barW}
            height={base - y(v)}
            rx={4}
            initial={{ scaleY: 0 }}
            whileInView={{ scaleY: 1 }}
            viewport={{ once: true, amount: 0.5 }}
            transition={{ duration: 0.7, delay: 0.1 + i * 0.05, ease: EASE }}
          />
        ))}
      </g>
      <g fill="#a3b8ac" fontFamily="DM Mono, monospace" fontSize={11} textAnchor="middle">
        {HOURS.map((h, i) =>
          i % 3 === 0 ? (
            <text key={h} x={left + i * step + step / 2} y={194}>
              {h}:00
            </text>
          ) : null,
        )}
      </g>
    </svg>
  );
}

function Sparkline() {
  return (
    <svg viewBox="0 0 120 26" aria-hidden="true" style={{ width: "100%", height: 26 }}>
      <m.polyline
        points="0,20 15,17 30,19 45,12 60,14 75,8 90,10 105,5 120,6"
        fill="none"
        stroke="#6FD8A6"
        strokeWidth={2}
        strokeLinecap="round"
        strokeLinejoin="round"
        initial={{ pathLength: 0 }}
        whileInView={{ pathLength: 1 }}
        viewport={{ once: true }}
        transition={{ duration: 1.2, ease: EASE }}
      />
    </svg>
  );
}

function OfflineRing({ pct }: { pct: number }) {
  const r = 48;
  return (
    <svg viewBox="0 0 120 120" role="img" aria-label={`Sample: ${pct}% of entries this week were verified with no network at the gate.`}>
      <circle cx="60" cy="60" r={r} fill="none" stroke="rgba(180,225,200,0.16)" strokeWidth={13} />
      <m.circle
        cx="60"
        cy="60"
        r={r}
        fill="none"
        stroke="#E8B075"
        strokeWidth={13}
        strokeLinecap="round"
        transform="rotate(-90 60 60)"
        initial={{ pathLength: 0 }}
        whileInView={{ pathLength: pct / 100 }}
        viewport={{ once: true, amount: 0.6 }}
        transition={{ duration: 1.2, ease: EASE }}
      />
      <text x="60" y="60" textAnchor="middle" fill="#EAF3EC" fontFamily="Manrope Variable, sans-serif" fontWeight={800} fontSize={26}>
        {pct}%
      </text>
      <text x="60" y="78" textAnchor="middle" fill="#a3b8ac" fontFamily="DM Mono, monospace" fontSize={9} letterSpacing={1}>
        OFFLINE
      </text>
    </svg>
  );
}

export function Record() {
  return (
    <section className="section section--a" id="record" aria-labelledby="record-title" style={{ background: "rgba(246,245,240,0.18)" }}>
      <div className="wrap">
        <Reveal className="section-head">
          <Item as="p" className="eyebrow">
            {record.eyebrow}
          </Item>
          <Item as="h2" className="h2">
            <span id="record-title">{record.title}</span>
          </Item>
          <Item as="p" className="lede">
            {record.body}
          </Item>
        </Reveal>

        <m.div
          className="console glass-dark"
          role="group"
          aria-label="Estate dashboard preview, sample data"
          initial={{ opacity: 0, y: 60, scale: 0.97 }}
          whileInView={{ opacity: 1, y: 0, scale: 1 }}
          viewport={{ once: true, amount: 0.15 }}
          transition={{ duration: 0.9, ease: EASE }}
        >
          <div className="console__bar">
            <div className="console__tabs" aria-hidden="true">
              <span className="console__logo">
                <GateMark size={17} />
              </span>
              {record.tabs.map((t, i) => (
                <span key={t} className={i === 0 ? "console__tab console__tab--on" : "console__tab"}>
                  {t}
                </span>
              ))}
            </div>
            <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
              <span className="chip chip--line">This week</span>
              <span className="chip chip--warn">Sample data</span>
            </div>
          </div>

          <div className="console__grid">
            <div className="console__main">
              <div className="stats">
                {record.stats.map((s) => (
                  <div className="stat glass-dark-card" key={s.label}>
                    <span className="mono-label">{s.label}</span>
                    <span className={"warn" in s && s.warn ? "stat__value stat__value--warn" : "stat__value"}>
                      <CountUp to={Number(s.value)} />
                      <small>{s.unit}</small>
                    </span>
                    {s.kind === "spark" ? <Sparkline /> : null}
                    {s.kind === "bar" ? (
                      <div className="meter" aria-hidden="true">
                        <m.span initial={{ width: 0 }} whileInView={{ width: `${s.pct}%` }} viewport={{ once: true }} transition={{ duration: 1.2, ease: EASE }} />
                      </div>
                    ) : null}
                    {s.kind === "note" ? <span className="stat__note">{s.note}</span> : null}
                  </div>
                ))}
              </div>

              <div className="panel glass-dark-card">
                <div className="panel__head">
                  <div style={{ display: "flex", alignItems: "baseline", gap: 12 }}>
                    <span className="panel__title">Arrivals by hour</span>
                    <span className="mono-label">Friday</span>
                  </div>
                  <span className="mono-label legend">
                    <i aria-hidden="true" />
                    Evening peak
                  </span>
                </div>
                <ArrivalsChart values={record.arrivals} />
                <p className="panel__note">{record.arrivalsNote}</p>
              </div>
            </div>

            <div className="console__side">
              <div className="panel glass-dark-card">
                <span className="mono-label">Gates</span>
                {record.gates.map((g) => (
                  <div className="gate-row" key={g.name}>
                    <div>
                      <b>{g.name}</b>
                      {g.sync ? <em>{g.sync}</em> : null}
                    </div>
                    <span className={g.online ? "status" : "status status--off"}>
                      <span className="dot pulse" aria-hidden="true" />
                      {g.online ? "Online" : "Offline"}
                    </span>
                  </div>
                ))}
                <p className="panel__note divider">{record.gatesNote}</p>
              </div>

              <div className="panel glass-dark-card ring">
                <OfflineRing pct={record.offlinePct} />
                <p className="panel__note">{record.offlineNote}</p>
              </div>

              <div className="panel glass-dark-card">
                <div className="panel__head">
                  <span className="mono-label">Live feed</span>
                  <span className="dot pulse" aria-hidden="true" />
                </div>
                {record.feed.map((f) => (
                  <div className="feed-row" key={f.name}>
                    <div>
                      <b>{f.name}</b>
                      <span>{f.home}</span>
                    </div>
                    <time>{f.time}</time>
                  </div>
                ))}
              </div>
            </div>
          </div>

          <div className="console__foot">
            <span className="mono-label">{record.footer}</span>
            <button type="button" className="btn" tabIndex={-1} aria-hidden="true">
              {record.export}
            </button>
          </div>
        </m.div>
      </div>
    </section>
  );
}
