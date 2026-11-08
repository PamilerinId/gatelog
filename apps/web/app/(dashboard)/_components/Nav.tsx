"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";

export type NavItem = { href: string; label: string };

/** Left navigation on wide screens; a menu button on phones. */
export function Nav({ items, estate }: { items: NavItem[]; estate: string }) {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);

  useEffect(() => setOpen(false), [pathname]);

  const current = (href: string) => (href === "/dashboard" ? pathname === href : pathname === href || pathname.startsWith(`${href}/`));
  const here = items.find((i) => current(i.href));

  return (
    <nav className="dash-nav" aria-label="Dashboard" data-open={open}>
      <div className="dash-nav__bar">
        <Link href="/dashboard" className="dash-brand">
          <span className="dash-brand__mark" aria-hidden="true" />
          <span>
            <span className="dash-brand__name">Gatelog</span>
            <span className="dash-brand__estate">{estate}</span>
          </span>
        </Link>
        <button type="button" className="dash-nav__toggle" aria-expanded={open} aria-controls="dash-nav-list" onClick={() => setOpen((o) => !o)}>
          {open ? "Close" : here ? `Menu: ${here.label}` : "Menu"}
        </button>
      </div>
      <ul id="dash-nav-list" className="dash-nav__list">
        {items.map((i) => (
          <li key={i.href}>
            <Link href={i.href} className="dash-nav__link" aria-current={current(i.href) ? "page" : undefined}>
              {i.label}
            </Link>
          </li>
        ))}
      </ul>
    </nav>
  );
}
