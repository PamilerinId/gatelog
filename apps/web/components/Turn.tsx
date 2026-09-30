import { turn } from "@/content/copy";

export function Turn() {
  return (
    <section className="section turn-section">
      <div className="wrap indent">
        <p className="turn">{turn.text}</p>
      </div>
    </section>
  );
}
