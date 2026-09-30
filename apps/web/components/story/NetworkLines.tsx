"use client";

import { useEffect, useId, useState, type RefObject } from "react";
import { m } from "motion/react";

type Geo = { w: number; h: number; ins: string[]; out: string };

/**
 * The lines between the scenes, the mark and the phone, drawn from where they actually sit.
 * Beside each other (desktop) the lines run left to right, starting at each panel's centre and
 * passing under it, so they appear to leave its edge. Stacked (phones) they run top to bottom,
 * from below each panel's caption to just above the phone's label.
 */
export function NetworkLines({
  box,
  nodes,
  hub,
  phone,
  run,
}: {
  box: RefObject<HTMLElement | null>;
  nodes: RefObject<(HTMLElement | null)[]>;
  hub: RefObject<HTMLElement | null>;
  phone: RefObject<HTMLElement | null>;
  run: boolean;
}) {
  const arrow = useId();
  const [geo, setGeo] = useState<Geo | null>(null);

  useEffect(() => {
    const b = box.current;
    const h = hub.current;
    const p = phone.current;
    if (!b || !h || !p) return;

    const measure = () => {
      const B = b.getBoundingClientRect();
      const H = h.getBoundingClientRect();
      const P = p.getBoundingClientRect();
      const hx = H.left + H.width / 2 - B.left;
      const hy = H.top + H.height / 2 - B.top;
      const across = P.left >= H.right;

      const ins = nodes.current.flatMap((el) => {
        if (!el) return [];
        const r = el.getBoundingClientRect();
        const x = r.left + r.width / 2 - B.left;
        if (across) {
          const y = r.top + r.height / 2 - B.top;
          return [`M${x} ${y} C${(x + hx) / 2} ${y} ${(x + hx) / 2} ${hy} ${hx} ${hy}`];
        }
        const y = (el.parentElement ?? el).getBoundingClientRect().bottom - B.top + 6;
        return [`M${x} ${y} C${x} ${(y + hy) / 2} ${hx} ${(y + hy) / 2} ${hx} ${hy}`];
      });

      let out: string;
      if (across) {
        const px = P.left - B.left - 6;
        const py = P.top + P.height / 2 - B.top;
        const mx = (hx + px) / 2;
        out = `M${hx} ${hy} C${mx} ${hy} ${mx} ${py} ${px} ${py}`;
      } else {
        const px = P.left + P.width / 2 - B.left;
        const py = (p.parentElement ?? p).getBoundingClientRect().top - B.top - 6;
        const my = (hy + py) / 2;
        out = `M${hx} ${hy} C${hx} ${my} ${px} ${my} ${px} ${py}`;
      }
      setGeo({ w: B.width, h: B.height, ins, out });
    };

    measure();
    const ro = new ResizeObserver(measure);
    [b, h, p, ...nodes.current].forEach((el) => el && ro.observe(el));
    return () => ro.disconnect();
  }, [box, nodes, hub, phone]);

  if (!geo) return null;

  const flow = (period: number, duration: number) =>
    run ? { animate: { strokeDashoffset: [0, -period] }, transition: { duration, ease: "linear" as const, repeat: Infinity } } : {};

  return (
    <svg className="story__lines" viewBox={`0 0 ${geo.w} ${geo.h}`} aria-hidden="true">
      <defs>
        <marker id={arrow} viewBox="0 0 10 10" refX="7" refY="5" markerWidth="9" markerHeight="9" orient="auto">
          <path d="M0 0 L10 5 L0 10 Z" />
        </marker>
      </defs>
      {geo.ins.map((d, i) => (
        <m.path key={i} d={d} className="line-in" {...flow(10, 1.1)} />
      ))}
      <m.path d={geo.out} className="line-out" markerEnd={`url(#${arrow})`} {...flow(14, 0.8)} />
    </svg>
  );
}
