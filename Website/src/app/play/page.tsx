"use client";

import { useState, useEffect, useRef } from "react";

function makeCode() {
  return String(Math.floor(Math.random() * 1_000_000)).padStart(6, "0");
}

const COURSES = [
  { id: "range",        name: "Range",                 sub: "Free practice — no scoring",          icon: "🏌" },
  { id: "pine-hollow",  name: "Pine Hollow National",  sub: "18 holes · par 72 · 6,900 yd",        icon: "⛳" },
  { id: "pebble-private", name: "Cypress Coast Links", sub: "18 holes · coastal links · par 72",    icon: "⛳" },
  { id: "augusta",      name: "Augusta National",      sub: "Coming soon",                          icon: "⛳", disabled: true },
];

type Stage = "waiting" | "select" | "playing";

export default function PlayPage() {
  const [code]  = useState(makeCode);
  const [stage, setStage] = useState<Stage>("waiting");
  const iframeRef = useRef<HTMLIFrameElement>(null);

  // Listen for messages from the sim iframe.
  useEffect(() => {
    function onMessage(e: MessageEvent) {
      if (e.data?.type === "APP_CONNECTED" && stage === "waiting") {
        setStage("select");
      }
    }
    window.addEventListener("message", onMessage);
    return () => window.removeEventListener("message", onMessage);
  }, [stage]);

  function selectCourse(courseId: string) {
    setStage("playing");
    setTimeout(() => {
      const msgType = courseId === "range" ? "START_RANGE" : "START_SIM";
      iframeRef.current?.contentWindow?.postMessage({ type: msgType, courseId }, "*");
    }, 200);
  }

  const src = `/sim/index.html?code=${code}`;

  return (
    <div className="sim-host">
      {/* Slim top bar — always visible */}
      <div className="sim-bar">
        <a className="sim-back" href="/">← True <span className="it">Carry.</span></a>
        {stage === "playing" ? (
          <button className="sim-change-btn" onClick={() => setStage("select")}>
            ↩ Change
          </button>
        ) : (
          <a className="sim-full" href={src} target="_blank" rel="noreferrer">Full screen ↗</a>
        )}
      </div>

      {/* Sim iframe — always loaded so Supabase connection is live */}
      <div className="sim-iframe-wrap" style={{ opacity: stage === "playing" ? 1 : 0, pointerEvents: stage === "playing" ? "auto" : "none" }}>
        <iframe
          ref={iframeRef}
          className="sim-frame"
          src={src}
          title="True Carry Sim"
          allow="autoplay; fullscreen"
        />
      </div>

      {/* Stage 1 — code pairing screen */}
      {stage === "waiting" && (
        <div className="sim-stage sim-stage-waiting">
          <div className="sim-stage-inner">
            <div className="sim-pairing-icon">◉</div>
            <h2 className="sim-pairing-title">Live Sim</h2>
            <p className="sim-pairing-sub">Open the TrueCarry app → <b>Sim</b> → <b>Live Sim</b><br />and enter this code:</p>
            <div className="sim-pairing-code">{code}</div>
            <p className="sim-pairing-hint">Waiting for app to connect…</p>
          </div>
        </div>
      )}

      {/* Stage 2 — course selector */}
      {stage === "select" && (
        <div className="sim-stage sim-stage-select">
          <div className="sim-stage-inner">
            <p className="sim-select-kicker">Connected ✓</p>
            <h2 className="sim-select-title">Select Course</h2>
            <div className="sim-course-list">
              {COURSES.map(c => (
                <button
                  key={c.id}
                  className={`sim-course-card${c.disabled ? " disabled" : ""}`}
                  onClick={() => !c.disabled && selectCourse(c.id)}
                  disabled={c.disabled}
                >
                  <span className="sim-course-icon">{c.icon}</span>
                  <span className="sim-course-info">
                    <span className="sim-course-name">{c.name}</span>
                    <span className="sim-course-sub">{c.sub}</span>
                  </span>
                </button>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
