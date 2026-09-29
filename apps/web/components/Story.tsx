import { gateToday, turn } from "@/content/copy";

export function GateToday() {
  return (
    <section className="section section--b" id="gate" aria-labelledby="gate-title">
      <div className="wrap">
        <div className="section-head reveal">
          <p className="eyebrow">{gateToday.eyebrow}</p>
          <h2 className="h2" id="gate-title">
            {gateToday.title}
          </h2>
        </div>

        <div className="story">
          <div className="spine" aria-hidden="true">
            <div className="spine__fill" />
          </div>
          <ol className="story__beats" style={{ listStyle: "none", margin: 0, padding: 0 }}>
            {gateToday.beats.map((b) => (
              <li className="beat glass reveal-settle" key={b.time}>
                <div className="beat__text">
                  <span className={b.warn ? "beat__time beat__time--warn" : "beat__time"}>{b.time}</span>
                  <h3>{b.title}</h3>
                  <p>{b.body}</p>
                </div>
                {b.book ? (
                  <div className="book glass-lite" aria-label="A page from the visitors’ book">
                    <span className="book__head">Visitors’ book</span>
                    {b.book.map((line) => (
                      <span key={line}>{line}</span>
                    ))}
                  </div>
                ) : null}
              </li>
            ))}
          </ol>
        </div>
      </div>
    </section>
  );
}

export function Turn() {
  return (
    <section className="section section--a" style={{ paddingTop: "clamp(40px, 5vw, 80px)", paddingBottom: "clamp(40px, 5vw, 80px)" }}>
      <div className="wrap">
        <div className="turn glass reveal-settle">
          <div className="turn__sheen" aria-hidden="true" />
          <p>
            {turn.lead} <span>{turn.accent}</span> {turn.tail}
          </p>
        </div>
      </div>
    </section>
  );
}
