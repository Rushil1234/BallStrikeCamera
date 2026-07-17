"use client";

import { useEffect, useRef, useState } from "react";

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
  autoStartOnReady = false,
}: {
  src: string;
  title: string;
  backLabel: string;
  onBack: () => void;
  /** Send START_SIM as soon as the sim runtime reports SIM_READY. Needed for
   *  live-code launches (`?code=`), which have no `?mode=` auto-start and no
   *  pairing-aware host — without it the sim never leaves its boot overlay. */
  autoStartOnReady?: boolean;
}) {
  const [loaded, setLoaded] = useState(false);
  const iframeRef = useRef<HTMLIFrameElement>(null);

  useEffect(() => {
    if (!autoStartOnReady) return;
    function onMessage(e: MessageEvent) {
      // Only trust messages from our own same-origin sim bundle.
      if (e.origin !== window.location.origin) return;
      if (e.data?.type === "SIM_READY") {
        iframeRef.current?.contentWindow?.postMessage(
          { type: "START_SIM" },
          window.location.origin
        );
      }
    }
    window.addEventListener("message", onMessage);
    return () => window.removeEventListener("message", onMessage);
  }, [autoStartOnReady]);

  return (
    <div className="sim-hostframe">
      <iframe
        ref={iframeRef}
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
