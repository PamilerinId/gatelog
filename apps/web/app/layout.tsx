import type { Metadata, Viewport } from "next";
import Image from "next/image";
import "@fontsource-variable/manrope";
import "@fontsource/dm-mono/400.css";
import "@fontsource/dm-mono/500.css";
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
  themeColor: "#0d1512",
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
        <div className="backdrop" aria-hidden="true">
          <Image src="/images/backdrop-gate-dawn.jpg" alt="" fill sizes="100vw" quality={70} />
        </div>
        {children}
      </body>
    </html>
  );
}
