"use client";

import Link from "next/link";
import { useMemo, useState } from "react";

export type HomeCardData = {
  id: string;
  label: string;
  street: string;
  zone: string;
  resident: string | null;
  numbers: number;
  pending: number;
  inside: number;
};

/** Every home as a card, grouped by street, with one search box. */
export function HomeCards({ homes, onlyNoNumber }: { homes: HomeCardData[]; onlyNoNumber: boolean }) {
  const [q, setQ] = useState("");
  const [noNumber, setNoNumber] = useState(onlyNoNumber);

  const groups = useMemo(() => {
    const needle = q.trim().toLowerCase();
    const shown = homes.filter(
      (h) =>
        (!noNumber || h.numbers === 0) &&
        (!needle || `${h.label} ${h.street} ${h.zone} ${h.resident ?? ""}`.toLowerCase().includes(needle)),
    );
    const by = new Map<string, HomeCardData[]>();
    for (const h of shown) {
      const key = `${h.street}, ${h.zone}`;
      by.set(key, [...(by.get(key) ?? []), h]);
    }
    return [...by.entries()];
  }, [homes, q, noNumber]);
  const count = groups.reduce((n, [, hs]) => n + hs.length, 0);

  return (
    <>
      <div className="dash-search">
        <label htmlFor="home-search" className="sr-only">
          Find a home
        </label>
        <input
          id="home-search"
          type="search"
          className="dash-input dash-search__input"
          placeholder="Find a home, street or resident"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          autoComplete="off"
        />
        {noNumber && (
          <button type="button" className="dash-chip-btn" onClick={() => setNoNumber(false)}>
            SHOWING HOMES WITH NO NUMBER · SHOW ALL
          </button>
        )}
      </div>
      <p className="dash-muted dash-small" aria-live="polite">
        {count === homes.length ? `${homes.length} homes.` : `${count} of ${homes.length} homes.`}
      </p>
      {groups.length === 0 && <p className="dash-done">No home matches that.</p>}
      {groups.map(([street, hs]) => (
        <section key={street} className="dash-street-group" aria-label={street}>
          <h2 className="dash-street-group__title">{street}</h2>
          <ul className="dash-homecards">
            {hs.map((h) => (
              <li key={h.id}>
                <Link href={`/dashboard/register/homes/${h.id}`} className="dash-homecard">
                  <span className="dash-homecard__no tnum">{h.label}</span>
                  <span className="dash-homecard__street">{h.street}</span>
                  <span className="dash-homecard__who">{h.resident ?? "Nobody registered"}</span>
                  <span className="dash-homecard__facts">
                    {h.numbers === 0 ? (
                      <span className="dash-warn-text">No number</span>
                    ) : (
                      <span>
                        {h.numbers} {h.numbers === 1 ? "number" : "numbers"} ✓
                      </span>
                    )}
                    {h.pending > 0 && <span className="dash-warn-text">{h.pending} waiting</span>}
                    {h.inside > 0 && <span>{h.inside} inside</span>}
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        </section>
      ))}
    </>
  );
}
