import { realities } from "@/content/copy";

export function Realities() {
  const [objectionCol, fixCol] = realities.cols;
  return (
    <section className="section section--alt" aria-labelledby="realities-title">
      <div className="wrap">
        <header className="section-head indent">
          <h2 className="h2" id="realities-title">
            {realities.title}
          </h2>
        </header>

        <div className="indent">
          <div className="objections__head" aria-hidden="true">
            <span>{objectionCol}</span>
            <span>{fixCol}</span>
          </div>
          <ul className="objections">
            {realities.items.map((r) => (
              <li key={r.problem} className="objection">
                <p className="objection__problem">
                  <span className="sr-only">{objectionCol}: </span>
                  {r.problem}
                </p>
                <p className="objection__fix">
                  <span className="sr-only">{fixCol}: </span>
                  {r.fix}
                </p>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </section>
  );
}
