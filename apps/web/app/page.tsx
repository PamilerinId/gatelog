import { Header } from "@/components/Header";
import { Hero } from "@/components/Hero";
import { GateToday, Turn } from "@/components/Story";
import { Screens, Already } from "@/components/Screens";
import { Record } from "@/components/Record";
import { Demo, Footer } from "@/components/Demo";

export default function Home() {
  return (
    <>
      <Header />
      <main id="main">
        <Hero />
        <GateToday />
        <Turn />
        <Screens />
        <Record />
        <Already />
        <Demo />
      </main>
      <Footer />
    </>
  );
}
