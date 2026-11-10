"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState, type ReactNode } from "react";

export type NavItem = { href: string; label: string };

/** The dashboard's pages, in the header strip. A menu button on phones. */
export function Nav({ items, footer }: { items: NavItem[]; footer?: ReactNode }) {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);

  useEffect(() => setOpen(false), [pathname]);

  const current = (href: string) => (href === "/dashboard" ? pathname === href : pathname === href || pathname.startsWith(`${href}/`));
  const here = items.find((i) => current(i.href));

  return (
    <nav className="dash-nav" aria-label="Dashboard" data-open={open}>
      <button type="button" className="dash-nav__toggle" aria-expanded={open} aria-controls="dash-nav-list" onClick={() => setOpen((o) => !o)}>
        {open ? "CLOSE" : here ? `MENU · ${here.label.toUpperCase()}` : "MENU"}
      </button>
      <div className="dash-nav__panel" id="dash-nav-list">
        <ul className="dash-nav__list">
          {items.map((i) => (
            <li key={i.href}>
              <Link href={i.href} className="dash-nav__link" aria-current={current(i.href) ? "page" : undefined}>
                {i.label}
              </Link>
            </li>
          ))}
        </ul>
        {footer}
      </div>
    </nav>
  );
}
