"use client";

import { useEffect, useState } from "react";
import { AnimatePresence, m, useMotionValueEvent, useScroll } from "motion/react";

/** Phones only: a glass bar with the one action, shown after the hero and hidden once the form is on screen. */
export function StickyCta() {
  const { scrollY } = useScroll();
  const [past, setPast] = useState(false);
  const [atForm, setAtForm] = useState(false);

  useMotionValueEvent(scrollY, "change", (y) => setPast(y > window.innerHeight * 0.9));

  useEffect(() => {
    const el = document.getElementById("demo");
    if (!el) return;
    const io = new IntersectionObserver(([e]) => setAtForm(e.isIntersecting), { threshold: 0.15 });
    io.observe(el);
    return () => io.disconnect();
  }, []);

  const show = past && !atForm;

  return (
    <AnimatePresence>
      {show ? (
        <m.div
          className="sticky-cta glass"
          initial={{ y: 90, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          exit={{ y: 90, opacity: 0 }}
          transition={{ type: "spring", stiffness: 380, damping: 32 }}
        >
          <a className="sticky-cta__try" href="#try">
            Try the code check
          </a>
          <a className="btn btn--primary" href="#demo">
            Book a demo
          </a>
        </m.div>
      ) : null}
    </AnimatePresence>
  );
}
