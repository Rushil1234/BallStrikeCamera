import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Play the Sim, 18 holes in your browser",
  description:
    "Tee off in the True Carry browser simulator, real courses, true ball flight, and launch-monitor data on every swing. Pair your iPhone to feed real shots into the sim.",
  alternates: { canonical: "/play" },
  openGraph: {
    title: "Play the True Carry Sim, 18 holes in your browser",
    description: "Real courses, true flight physics, launch-monitor data every swing. Pair your phone and play.",
    url: "/play",
  },
};

export default function PlayLayout({ children }: { children: React.ReactNode }) {
  return children;
}
