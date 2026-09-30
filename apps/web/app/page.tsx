import { existsSync } from "node:fs";
import { join } from "node:path";
import { Header } from "@/components/Header";
import { Hero } from "@/components/Hero";
import { Contrast } from "@/components/Contrast";
import { Realities } from "@/components/Realities";
import { TryIt } from "@/components/TryIt";
import { Record } from "@/components/Record";
import { Demo, Footer } from "@/components/Demo";
import { StickyCta } from "@/components/StickyCta";
import { MotionProvider } from "@/components/motion/MotionProvider";

// Scene illustrations for the before and after, if they have been added.
// Drop arrival, call and book (.webp, .png or .jpg) into public/images/scenes/.
function sceneArt() {
  return ["arrival", "call", "book"].map((name) => {
    for (const ext of ["webp", "png", "jpg"]) {
      const src = `/images/scenes/${name}.${ext}`;
      if (existsSync(join(process.cwd(), "public", src))) return src;
    }
    return null;
  });
}

export default function Home() {
  return (
    <MotionProvider>
      <Header />
      <main id="main">
        <Hero />
        <Contrast art={sceneArt()} />
        <Realities />
        <TryIt />
        <Record />
        <Demo />
      </main>
      <Footer />
      <StickyCta />
    </MotionProvider>
  );
}
