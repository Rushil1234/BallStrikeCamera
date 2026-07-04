"use client";

import { useState } from "react";

/**
 * Fullscreen sim iframe shared by the sim entry points: entrance transition,
 * loading veil until the bundle paints, and a back/exit control. `/play`
 * keeps its richer pairing-aware host; this covers direct launches.
 */
export default function SimHost({
  src,
  title,
  backLabel,
  onBack,
}: {
  src: string;
  title: string;
  backLabel: string;
  onBack: () => void;
}) {
  const [loaded, setLoaded] = useState(false);

  return (
    <div className="sim-hostframe">
      <iframe
        src={src}
        className="sim-hostframe-iframe"
        allow="autoplay; fullscreen"
        title={title}
        onLoad={() => setLoaded(true)}
      />
      {!loaded && (
        <div className="sim-hostframe-loading" aria-live="polite">
          <div className="sim-hostframe-spinner" aria-hidden />
          <span>Loading the sim…</span>
        </div>
      )}
      <button className="sim-hostframe-back" onClick={onBack}>{backLabel}</button>
    </div>
  );
}
