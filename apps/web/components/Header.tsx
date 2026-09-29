import { nav } from "@/content/copy";
import { GateMark } from "./ui/icons";

export function Header() {
  return (
    <header className="header">
      <div className="header__bar glass">
        <a className="brand" href="#top" aria-label="Gatelog, back to top">
          <GateMark />
          <span>Gatelog</span>
        </a>
        <nav className="header__nav" aria-label="Primary">
          {nav.map((item) => (
            <a key={item.href} href={item.href}>
              {item.label}
            </a>
          ))}
        </nav>
        <a className="btn btn--primary" href="#demo">
          Book a demo
        </a>
      </div>
    </header>
  );
}
