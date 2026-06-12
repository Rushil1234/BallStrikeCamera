"use client";

import { useEffect, useRef, useState } from "react";

/**
 * Client host for the True Carry Sim iframe. The game listens for keys on
 * its own window, so the host's job is to make sure the iframe actually
 * has focus — on load, on any pointer interaction, and whenever the tab
 * regains focus. Also shows a branded loading state while three.js boots.
 */
export default function SimHost() {
  const frameRef = useRef<HTMLIFrameElement>(null);
  const [loaded, setLoaded] = useState(false);

  const focusGame = () => {
    try {
      frameRef.current?.contentWindow?.focus();
    } catch {
      /* cross-origin guard — same-origin in practice */
    }
  };

  useEffect(() => {
    const onFocus = () => focusGame();
    window.addEventListener("focus", onFocus);
    return () => window.removeEventListener("focus", onFocus);
  }, []);

  return (
    <div className="sim-host" onPointerDown={focusGame}>
      <div className="sim-bar">
        <a className="sim-back" href="/">
          ← True <span className="it">Carry.</span>
        </a>
        <span className="sim-title">The Sim · Pine Hollow National</span>
        <span className="sim-bar-right">
          <a className="sim-live" href="/sim">Live Sim</a>
          <a className="sim-full" href="/sim/index.html" target="_blank" rel="noreferrer">
            Full screen ↗
          </a>
        </span>
      </div>
      <div className="sim-stage">
        {!loaded && (
          <div className="sim-loading" aria-label="Loading the sim">
            <span className="sim-loading-ball" />
            <span className="sim-loading-text">Walking to the first tee…</span>
          </div>
        )}
        <iframe
          ref={frameRef}
          className="sim-frame"
          src="/sim/index.html"
          title="True Carry Sim — Pine Hollow National"
          allow="autoplay; fullscreen"
          onLoad={() => {
            setLoaded(true);
            focusGame();
          }}
        />
      </div>
    </div>
  );
}
