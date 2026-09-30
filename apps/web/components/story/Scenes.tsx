// The evening without Gatelog, drawn as three line scenes. Each tile is a little darker
// than the last: 18:41, 18:43, 18:46. Stroke colour comes from CSS (currentColor).

type SceneProps = { label: string };

function Rain({ from = 0 }: { from?: number }) {
  const drops = [
    [14, 6], [38, 16], [62, 4], [86, 20], [112, 8], [136, 18], [184, 6], [26, 30], [74, 34], [124, 38], [48, 48], [98, 50],
  ];
  return (
    <g className="scene__rain">
      {drops.slice(from).map(([x, y], i) => (
        <path key={i} d={`M${x} ${y} l-3 8`} />
      ))}
    </g>
  );
}

function Car({ x }: { x: number }) {
  return (
    <g transform={`translate(${x} 0)`}>
      <path d="M0 96 V88 Q0 83 6 82 L14 75 H30 L38 82 Q46 83 46 88 V96 Z" />
      <path d="M16 76 V82" />
      <circle cx="10" cy="97" r="5" className="scene__fill" />
      <circle cx="36" cy="97" r="5" className="scene__fill" />
    </g>
  );
}

/** 18:41. A queue at the barrier, rain, and the guard asking who you are here to see. */
export function SceneArrival({ label }: SceneProps) {
  return (
    <svg viewBox="0 0 200 120" preserveAspectRatio="xMidYMid slice" role="img" aria-label={label} className="scene__art scene__art--1">
      <Rain />
      <path d="M0 102 H200" />
      {/* keke */}
      <g>
        <path d="M6 96 V82 Q6 73 15 73 H34 Q40 73 40 80 V96" />
        <path d="M4 73 H42" />
        <path d="M22 73 V96" />
        <circle cx="12" cy="97" r="4" className="scene__fill" />
        <circle cx="34" cy="97" r="4" className="scene__fill" />
      </g>
      <Car x={48} />
      <Car x={100} />
      {/* barrier, down */}
      <rect x="152" y="66" width="6" height="36" className="scene__fill" />
      <rect x="64" y="67" width="91" height="5" className="scene__paper" />
      <path d="M66 69.5 H153" className="scene__stripes" />
      {/* guardhouse */}
      <path d="M166 102 V58 H200" />
      <path d="M162 58 H200" />
      <rect x="174" y="68" width="14" height="12" />
      {/* who are you here to see? */}
      <rect x="156" y="16" width="34" height="24" rx="2" className="scene__paper" />
      <path d="M166 40 L163 48 L173 40" className="scene__paper" />
      <text x="173" y="34" textAnchor="middle" className="scene__glyph">
        ?
      </text>
    </svg>
  );
}

/** 18:43. The guard calls the house on one bar of signal. It rings out. */
export function SceneCall({ label }: SceneProps) {
  return (
    <svg viewBox="0 0 200 120" preserveAspectRatio="xMidYMid slice" role="img" aria-label={label} className="scene__art scene__art--2">
      <Rain from={4} />
      {/* clock: the queue is still waiting */}
      <circle cx="44" cy="60" r="20" />
      <path d="M44 60 V46" />
      <path d="M44 60 L54 66" />
      <path d="M44 38 V41 M44 79 V82 M22 60 H25 M63 60 H66" />
      {/* phone */}
      <rect x="86" y="22" width="36" height="70" rx="5" className="scene__paper" />
      <path d="M98 27 H110" />
      {/* one bar of signal */}
      <rect x="92" y="38" width="3" height="4" className="scene__fill" />
      <rect x="97" y="35" width="3" height="7" />
      <rect x="102" y="32" width="3" height="10" />
      <rect x="107" y="29" width="3" height="13" />
      {/* handset */}
      <path d="M97 62 q2 -6 6 -4 l3 3 q1 2 -1 3 q-2 1 -1 3 q2 4 6 6 q2 1 3 -1 q1 -2 3 -1 l3 3 q2 4 -4 6 q-10 2 -18 -18 Z" className="scene__fill" />
      {/* rings, going nowhere */}
      <path d="M130 44 Q136 57 130 70" className="scene__ring" />
      <path d="M138 36 Q148 57 138 78" className="scene__ring scene__ring--2" />
      <path d="M146 28 Q160 57 146 86" className="scene__ring scene__ring--3" />
      <path d="M166 50 l12 12 M178 50 l-12 12" className="scene__cross" />
      <path d="M0 106 H200" />
    </svg>
  );
}

/** 18:46. A name goes into the book, by hand, in the dark. */
export function SceneBook({ label }: SceneProps) {
  return (
    <svg viewBox="0 0 200 120" preserveAspectRatio="xMidYMid slice" role="img" aria-label={label} className="scene__art scene__art--3">
      {/* torch beam */}
      <path d="M18 10 L34 4 L162 100 L58 112 Z" className="scene__beam" />
      <rect x="8" y="4" width="22" height="9" rx="1" transform="rotate(-20 19 8)" />
      {/* open book */}
      <path d="M48 96 L50 52 Q75 45 100 54 L100 100 Q75 91 48 96 Z" className="scene__paper" />
      <path d="M152 96 L150 52 Q125 45 100 54 L100 100 Q125 91 152 96 Z" className="scene__paper" />
      {/* ruled lines, left page */}
      <path d="M56 64 Q76 59 94 65 M56 73 Q76 68 94 74 M56 82 Q76 77 94 83" className="scene__rule" />
      {/* ruled lines, right page */}
      <path d="M106 65 Q124 59 144 64 M106 74 Q124 68 144 73 M106 83 Q124 77 144 82" className="scene__rule" />
      {/* handwriting */}
      <path d="M58 62 q3 -4 5 0 t5 0 t5 -1 t5 1 t5 -1" className="scene__ink" />
      <path d="M58 71 q3 -4 5 0 t5 -1 t5 1 t5 0" className="scene__ink" />
      <path d="M108 63 q3 -4 5 0 t5 -1 t5 1 t5 -1 t5 0" className="scene__ink" />
      <path d="M108 72 q3 -3 5 0 t4 -1 t5 1" className="scene__ink" />
      {/* pen */}
      <path d="M160 36 L130 74 L128 80 L133 76 L163 39 Z" className="scene__fill" />
    </svg>
  );
}
