"use client";

// The real, playable browser sim embedded live. We show a lightweight preview
// (the recorded loop as a poster) until the visitor clicks, then swap in an
// iframe running the actual sim, so the heavy WebGL only loads on demand and
// the homepage stays fast for people who are just scrolling.
import { useState } from "react";

const SIM_SRC = "/sim/index.html?mode=course&course=pine-hollow";

export default function SimDemo() {
  const [live, setLive] = useState(false);

  return (
    <div className="sim-demo">
      {live ? (
        <iframe
          className="sim-demo-frame"
          src={SIM_SRC}
          title="True Carry live browser sim"
          allow="autoplay; fullscreen; gamepad"
        />
      ) : (
        <button type="button" className="sim-demo-load" onClick={() => setLive(true)} aria-label="Play the True Carry sim, live in your browser">
          <video
            className="sim-demo-video"
            autoPlay
            muted
            loop
            playsInline
            preload="metadata"
            poster="/sim-demo-poster.jpg"
            aria-hidden="true"
          >
            <source src="/sim-demo.webm" type="video/webm" />
          </video>
          <span className="sim-demo-badge">Live browser sim</span>
          <span className="sim-demo-play">
            <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">
              <path d="M8 5v14l11-7z" fill="currentColor" />
            </svg>
            Play here, live
          </span>
        </button>
      )}
      <a className="sim-demo-fs" href={SIM_SRC} target="_blank" rel="noreferrer">Open full screen &#8599;</a>
    </div>
  );
}
