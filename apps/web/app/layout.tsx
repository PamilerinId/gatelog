import type { Metadata, Viewport } from "next";
import "@fontsource-variable/archivo/wdth.css";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000"),
  title: "Gatelog · Visitor access for Nigerian estates",
  description:
    "Residents clear guests on WhatsApp. Guards verify a six-digit code at the gate, even with the network down. The estate keeps a record of every entry.",
  openGraph: {
    title: "Gatelog",
    description: "Visitor access for Nigerian estates. Works when the network doesn’t.",
    images: ["/images/hero-gate-phone.jpg"],
    type: "website",
  },
};

export const viewport: Viewport = {
  themeColor: "#081a33",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en-NG">
      <body>
        <a className="skip-link" href="#main">
          Skip to content
        </a>
        {children}
      </body>
    </html>
  );
}
