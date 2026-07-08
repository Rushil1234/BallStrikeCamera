"use client";

import { useState } from "react";

// Play-it-now demo: click loads the real sim (range mode, no phone pairing)
// right inside the marketing page. Lazy so the ~7MB sim never touches the
// initial page load.
export default function SimDemo() {
  const [live, setLive] = useState(false);
  const [ready, setReady] = useState(false);

  return (
    <div className={`sim-demo${live ? " live" : ""}`}>
      {live ? (
        <>
          {!ready && (
            <div className="sim-demo-loading" role="status" aria-live="polite">
              <span className="sim-demo-spinner" aria-hidden="true" />
              <span>Warming up the course…</span>
            </div>
          )}
          <iframe
            className="sim-demo-frame"
            src="/sim/index.html?mode=range"
            title="True Carry Sim — interactive demo"
            allow="autoplay; fullscreen"
            onLoad={() => setReady(true)}
          />
          {ready && (
            <div className="sim-demo-hint" aria-hidden="true">
              <span><b>Drag</b> to aim</span>
              <span><b>Space</b> to swing</span>
              <span><b>▲▼</b> club</span>
            </div>
          )}
        </>
      ) : (
        <button
          className="sim-demo-cover"
          onClick={() => setLive(true)}
          aria-label="Play the interactive sim demo in your browser"
        >
          <img src="/sim-preview.jpg" alt="" loading="lazy" />
          <span className="sim-demo-badge">Interactive demo · no app needed</span>
          <span className="sim-demo-play">
            <svg viewBox="0 0 24 24" width="26" height="26" aria-hidden="true">
              <path d="M8 5v14l11-7z" fill="currentColor" />
            </svg>
            Play in your browser
          </span>
        </button>
      )}
    </div>
  );
}
