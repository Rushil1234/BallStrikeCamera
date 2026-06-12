import type { Metadata } from "next";
import SimHost from "@/components/SimHost";

export const metadata: Metadata = {
  title: "The Sim — Pine Hollow National",
  description:
    "Play a full 18-hole round in your browser. Real ball-flight physics, wind, bunkers, water, and launch-monitor data on every swing — the True Carry Sim.",
};

/**
 * Full-screen host for the True Carry Sim (a static three.js app served
 * from /sim/). A slim bar keeps a way back to the site; the game itself
 * owns every other pixel. Focus/loading handled client-side in SimHost.
 */
export default function PlayPage() {
  return <SimHost />;
}
