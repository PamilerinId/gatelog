"use client";

import { useRef } from "react";
import { m, useScroll, useTransform, type MotionValue } from "motion/react";
import { turn } from "@/content/copy";

function Word({ word, i, n, progress, accent }: { word: string; i: number; n: number; progress: MotionValue<number>; accent: boolean }) {
  const start = i / n;
  const opacity = useTransform(progress, [start, start + 1 / n], [0.16, 1]);
  return (
    <m.span className={accent ? "tw tw--accent" : "tw"} style={{ opacity }}>
      {word}{" "}
    </m.span>
  );
}

/** The sentence lights up word by word as you scroll through it. */
export function Turn() {
  const ref = useRef<HTMLParagraphElement>(null);
  const { scrollYProgress } = useScroll({ target: ref, offset: ["start 0.9", "end 0.5"] });
  const words = [
    ...turn.lead.split(" ").map((w) => ({ w, a: false })),
    { w: turn.accent, a: true },
    ...turn.tail.split(" ").map((w) => ({ w, a: false })),
  ];

  return (
    <section className="section section--a turn-section">
      <div className="wrap">
        <div className="turn glass">
          <p ref={ref}>
            {words.map(({ w, a }, i) => (
              <Word key={i} word={w} i={i} n={words.length} progress={scrollYProgress} accent={a} />
            ))}
          </p>
        </div>
      </div>
    </section>
  );
}
