"use client";

import { LazyMotion, MotionConfig, domMax } from "motion/react";

/** One place for motion settings: honour the OS reduced-motion setting, load only the DOM feature set. */
export function MotionProvider({ children }: { children: React.ReactNode }) {
  return (
    <LazyMotion features={domMax} strict>
      <MotionConfig reducedMotion="user" transition={{ type: "spring", stiffness: 260, damping: 30 }}>
        {children}
      </MotionConfig>
    </LazyMotion>
  );
}
