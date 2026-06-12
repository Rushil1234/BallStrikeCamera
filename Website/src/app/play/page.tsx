import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "The Sim — Pine Hollow National",
  description:
    "Play a full 18-hole round in your browser. Real ball-flight physics, wind, bunkers, water, and launch-monitor data on every swing — the True Carry Sim.",
};

/**
 * Full-screen host for the True Carry Sim (a static three.js app served
 * from /sim/). A slim bar keeps a way back to the site; the game itself
 * owns every other pixel.
 */
export default function PlayPage() {
  return (
    <div className="sim-host">
      <div className="sim-bar">
        <a className="sim-back" href="/">
          ← True <span className="it">Carry.</span>
        </a>
        <span className="sim-title">The Sim · Pine Hollow National</span>
        <a className="sim-full" href="/sim/index.html" target="_blank" rel="noreferrer">
          Full screen ↗
        </a>
      </div>
      <iframe
        className="sim-frame"
        src="/sim/index.html"
        title="True Carry Sim — Pine Hollow National"
        allow="autoplay; fullscreen"
      />
    </div>
  );
}
