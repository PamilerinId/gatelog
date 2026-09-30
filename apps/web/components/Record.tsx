import Image from "next/image";
import { record } from "@/content/copy";
import { GateMark } from "./ui/icons";

// Chart colours follow the page tokens: navy for data, amber only for offline.
const NAVY = "#0d2a52";
const SLATE = "#4a5d78";
const GRID = "rgba(13,42,82,0.12)";
const LAMP = "#b9802e";
const FONT = "Archivo Variable, Archivo, sans-serif";

const HOURS = ["10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "20", "21"];

/** Drawn at two widths so the axis labels stay readable: SVG text scales with the viewBox, not the page. */
function ArrivalsChart({ values, W, className }: { values: number[]; W: number; className: string }) {
  const top = 10;
  const base = 170;
  const left = 36;
  const max = 30;
  const step = (W - left) / values.length;
  const barW = step * 0.56;
  const y = (v: number) => base - (v / max) * (base - top);
  const peakFrom = left + step * 6;
  const peakTo = left + step * 9;

  return (
    <svg
      className={className}
      viewBox={`0 0 ${W} 200`}
      role="img"
      aria-label="Sample chart of arrivals by hour on a Friday: low through the morning, rising from 14:00, peaking at 27 arrivals in the 17:00 hour, then falling after 19:00."
    >
      <g stroke={GRID} strokeWidth={1}>
        {[0, 10, 20, 30].map((t) => (
          <line key={t} x1={left} x2={W} y1={y(t)} y2={y(t)} />
        ))}
      </g>
      <g fill={SLATE} fontFamily={FONT} fontSize={12} style={{ fontVariantNumeric: "tabular-nums" }}>
        {[10, 20, 30].map((t) => (
          <text key={t} x={0} y={y(t) + 4}>
            {t}
          </text>
        ))}
      </g>
      <rect x={peakFrom} y={top} width={peakTo - peakFrom} height={base - top} fill="rgba(13,42,82,0.05)" />
      <line x1={peakFrom} x2={peakTo} y1={top} y2={top} stroke={NAVY} strokeDasharray="4 5" strokeOpacity={0.7} />
      <g>
        {values.map((v, i) => {
          const x = left + i * step;
          const inPeak = x >= peakFrom && x < peakTo;
          return <rect key={i} x={x + (step - barW) / 2} y={y(v)} width={barW} height={base - y(v)} rx={1} fill={NAVY} fillOpacity={inPeak ? 1 : 0.55} />;
        })}
      </g>
      <g fill={SLATE} fontFamily={FONT} fontSize={12} textAnchor="middle" style={{ fontVariantNumeric: "tabular-nums" }}>
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
      <polyline points="0,20 15,17 30,19 45,12 60,14 75,8 90,10 105,5 120,6" fill="none" stroke={NAVY} strokeWidth={1.75} strokeLinejoin="miter" />
    </svg>
  );
}

function OfflineRing({ pct }: { pct: number }) {
  const r = 48;
  const c = 2 * Math.PI * r;
  return (
    <svg viewBox="0 0 120 120" role="img" aria-label={`Sample: ${pct}% of entries this week were verified with no network at the gate.`}>
      <circle cx="60" cy="60" r={r} fill="none" stroke={GRID} strokeWidth={10} />
      <circle
        cx="60"
        cy="60"
        r={r}
        fill="none"
        stroke={LAMP}
        strokeWidth={10}
        strokeDasharray={`${(c * pct) / 100} ${c}`}
        transform="rotate(-90 60 60)"
      />
      <text x="60" y="60" textAnchor="middle" fill={NAVY} fontFamily={FONT} fontWeight={600} fontSize={28}>
        {pct}%
      </text>
      <text x="60" y="81" textAnchor="middle" fill={SLATE} fontFamily={FONT} fontWeight={500} fontSize={15}>
        {record.offlineWord}
      </text>
    </svg>
  );
}

/** Monday morning: the estate office's view of the weekend, over the dawn photo. Sample data, labelled as such. */
export function Record() {
  return (
    <section className="section record" id="record" aria-labelledby="record-title">
      <div className="record__photo" aria-hidden="true">
        <Image src="/images/backdrop-gate-dawn.jpg" alt="" fill sizes="100vw" quality={70} />
      </div>

      <div className="wrap">
        <header className="section-head indent hang">
          <p className="stamp">{record.stamp}</p>
          <h2 className="h2" id="record-title">
            {record.title}
          </h2>
          <p className="lede">{record.body}</p>
        </header>

        <div className="console glass" role="group" aria-label={`Estate dashboard preview, ${record.sample.toLowerCase()}`}>
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
            <div className="chips">
              <span className="chip">{record.range}</span>
              <span className="chip chip--sample">{record.sample}</span>
            </div>
          </div>

          <div className="stats">
            {record.stats.map((s) => (
              <div className="stat" key={s.label}>
                <span className="label">{s.label}</span>
                <span className={"warn" in s && s.warn ? "stat__value stat__value--warn" : "stat__value"}>
                  {s.value}
                  <small>{s.unit}</small>
                </span>
                {s.kind === "spark" ? <Sparkline /> : null}
                {s.kind === "bar" ? (
                  <div className="meter" aria-hidden="true">
                    <span style={{ width: `${s.pct}%` }} />
                  </div>
                ) : null}
                {s.kind === "note" ? <span className="stat__note">{s.note}</span> : null}
              </div>
            ))}
          </div>

          <div className="console__grid">
            <div className="panel panel--chart">
              <div className="panel__head">
                <div style={{ display: "flex", alignItems: "baseline", gap: 12 }}>
                  <span className="panel__title">{record.arrivalsTitle}</span>
                  <span className="label">{record.arrivalsDay}</span>
                </div>
                <span className="label legend">
                  <i aria-hidden="true" />
                  {record.peak}
                </span>
              </div>
              <ArrivalsChart values={record.arrivals} W={640} className="chart chart--wide" />
              <ArrivalsChart values={record.arrivals} W={340} className="chart chart--narrow" />
              <p className="panel__note">{record.arrivalsNote}</p>
            </div>

            <div className="console__side">
              <div className="panel">
                <span className="panel__title">{record.gatesTitle}</span>
                {record.gates.map((g) => (
                  <div className="gate-row" key={g.name}>
                    <div>
                      <b>{g.name}</b>
                      {g.sync ? <em>{g.sync}</em> : null}
                    </div>
                    <span className={g.online ? "status" : "status status--off"}>
                      <i aria-hidden="true" />
                      {g.online ? record.online : record.offline}
                    </span>
                  </div>
                ))}
                <p className="panel__note divider">{record.gatesNote}</p>
              </div>

              <div className="panel ring">
                <OfflineRing pct={record.offlinePct} />
                <p className="panel__note">{record.offlineNote}</p>
              </div>
            </div>
          </div>

          <div className="console__foot">
            <span className="label">{record.footer}</span>
            <button type="button" className="btn btn--primary btn--sm" tabIndex={-1} aria-hidden="true">
              {record.export}
            </button>
          </div>
        </div>
      </div>
    </section>
  );
}
