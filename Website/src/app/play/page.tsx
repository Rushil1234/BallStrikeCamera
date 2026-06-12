"use client";

import { useState } from "react";

function makeCode() {
  return String(Math.floor(Math.random() * 1_000_000)).padStart(6, "0");
}

export default function PlayPage() {
  const [code] = useState(makeCode);
  const src = `/sim/index.html?code=${code}`;

  return (
    <div className="sim-host">
      <div className="sim-bar">
        <a className="sim-back" href="/">
          ← True <span className="it">Carry.</span>
        </a>
        <div className="sim-code-display">
          <span className="sim-code-label">Enter in app</span>
          <span className="sim-code-value">{code}</span>
        </div>
        <a className="sim-full" href={src} target="_blank" rel="noreferrer">
          Full screen ↗
        </a>
      </div>
      <iframe
        className="sim-frame"
        src={src}
        title="True Carry Sim — Pine Hollow National"
        allow="autoplay; fullscreen"
      />
    </div>
  );
}
