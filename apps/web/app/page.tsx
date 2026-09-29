import { Header } from "@/components/Header";
import { Hero } from "@/components/Hero";
import { Contrast } from "@/components/Contrast";
import { Turn } from "@/components/Turn";
import { Realities } from "@/components/Realities";
import { TryIt } from "@/components/TryIt";
import { Screens, Already } from "@/components/Screens";
import { Record } from "@/components/Record";
import { Demo, Footer } from "@/components/Demo";
import { StickyCta } from "@/components/StickyCta";
import { MotionProvider } from "@/components/motion/MotionProvider";

export default function Home() {
  return (
    <MotionProvider>
      <Header />
      <main id="main">
        <Hero />
        <Contrast />
        <Turn />
        <Realities />
        <TryIt />
        <Screens />
        <Record />
        <Already />
        <Demo />
      </main>
      <Footer />
      <StickyCta />
    </MotionProvider>
  );
}
