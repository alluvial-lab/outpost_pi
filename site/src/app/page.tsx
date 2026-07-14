import { Hero } from "@/components/landing/hero";
import { Install } from "@/components/landing/install";
import { Pillars, GetApp, Strip, GithubCTA } from "@/components/landing/sections";
import { RevealController } from "@/components/landing/reveal-controller";

/** Compose the Outpost-Pi landing page sections. */
export default function Home() {
  return (
    <>
      <Hero />
      <Pillars />
      <Install />
      <GetApp />
      <Strip />
      <GithubCTA />
      <RevealController />
    </>
  );
}
