"use client";

import { m, type Variants } from "motion/react";

export const EASE = [0.2, 0.7, 0.2, 1] as const;

export const rise: Variants = {
  hidden: { opacity: 0, y: 28 },
  show: { opacity: 1, y: 0, transition: { duration: 0.7, ease: EASE } },
};

export const stagger = (gap = 0.08, delay = 0): Variants => ({
  hidden: {},
  show: { transition: { staggerChildren: gap, delayChildren: delay } },
});

/** Fades and lifts its children in as the block scrolls into view. */
export function Reveal({
  children,
  className,
  as = "div",
  gap = 0.08,
  delay = 0,
  amount = 0.25,
}: {
  children: React.ReactNode;
  className?: string;
  as?: "div" | "ul" | "ol" | "section" | "header";
  gap?: number;
  delay?: number;
  amount?: number;
}) {
  const Comp = m[as];
  return (
    <Comp className={className} variants={stagger(gap, delay)} initial="hidden" whileInView="show" viewport={{ once: true, amount }}>
      {children}
    </Comp>
  );
}

export function Item({ children, className, as = "div" }: { children: React.ReactNode; className?: string; as?: "div" | "li" | "p" | "h2" | "span" | "figure" }) {
  const Comp = m[as];
  return (
    <Comp className={className} variants={rise}>
      {children}
    </Comp>
  );
}
