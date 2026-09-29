"use client";

import { m } from "motion/react";
import { realities } from "@/content/copy";
import { EASE, Item, Reveal } from "./motion/Reveal";

const card = {
  hidden: { opacity: 0, y: 30 },
  show: { opacity: 1, y: 0, transition: { duration: 0.45, ease: EASE, delayChildren: 0.2, staggerChildren: 0.18 } },
};
const strike = { hidden: { scaleX: 0 }, show: { scaleX: 1, transition: { duration: 0.45, delay: 0.25, ease: EASE } } };
const dim = { hidden: { opacity: 1 }, show: { opacity: 0.55, transition: { duration: 0.4, delay: 0.45 } } };
const fix = { hidden: { opacity: 0, y: 12 }, show: { opacity: 1, y: 0, transition: { duration: 0.5, delay: 0.35, ease: EASE } } };

export function Realities() {
  return (
    <section className="section section--b" aria-labelledby="realities-title">
      <div className="wrap">
        <Reveal className="section-head">
          <Item as="p" className="eyebrow">
            {realities.eyebrow}
          </Item>
          <Item as="h2" className="h2">
            <span id="realities-title">{realities.title}</span>
          </Item>
        </Reveal>

        <ul className="realities">
          {realities.items.map((r) => (
            <m.li
              key={r.problem}
              className="reality glass"
              variants={card}
              initial="hidden"
              whileInView="show"
              viewport={{ once: true, amount: 0.5 }}
            >
              <m.p className="reality__problem" variants={dim}>
                <span className="reality__tag">Problem</span>
                <span className="reality__struck">
                  {r.problem}
                  <m.span className="reality__line" variants={strike} aria-hidden="true" />
                </span>
              </m.p>
              <m.p className="reality__fix" variants={fix}>
                <span className="reality__tag reality__tag--ok">Gatelog</span>
                {r.fix}
              </m.p>
            </m.li>
          ))}
        </ul>
      </div>
    </section>
  );
}
