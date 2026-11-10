import type { Metadata } from "next";
// Inter for the interface, JetBrains Mono for data. Bundled and served by the app, never fetched from Google.
import "@fontsource-variable/inter";
import "@fontsource-variable/jetbrains-mono";
import "./dashboard.css";
import "./map.css";
import "./simple.css";

// The estate dashboard sits inside the root layout (fonts, base tokens) but carries its own
// title and stylesheet, and is kept out of search engines.
export const metadata: Metadata = {
  title: { default: "Gatelog dashboard", template: "%s · Gatelog dashboard" },
  description: "Estate admin and committee dashboard.",
  robots: { index: false, follow: false },
  openGraph: null,
};

export default function DashboardGroupLayout({ children }: { children: React.ReactNode }) {
  return <div className="dash">{children}</div>;
}
