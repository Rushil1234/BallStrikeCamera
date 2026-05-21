"use client";

import { useRef, useState } from "react";

/* A small, self-contained interactive demo of the app: pick a club, "hit" a
   shot, and watch the tracer fly while the numbers are measured live. */

type ClubKey = "Driver" | "7 Iron" | "Wedge";

interface Club {
  key: ClubKey;
  /** [min, max] for each measured value */
  carry: [number, number];
  ball: [number, number];
  launch: [number, number];
  spin: [number, number];
  /** SVG flight path (viewBox 0 0 240 120) — apex + length vary by club */
  path: string;
}

const CLUBS: Club[] = [
  { key: "Driver", carry: [268, 292], ball: [161, 172], launch: [10.5, 14.5], spin: [2200, 2900], path: "M12,112 Q120,26 228,112" },
  { key: "7 Iron", carry: [150, 173], ball: [115, 125], launch: [16, 19.5], spin: [6300, 7300], path: "M12,112 Q96,12 182,112" },
  { key: "Wedge",  carry: [92, 118],  ball: [90, 105],  launch: [27, 34],   spin: [8600, 9900], path: "M12,112 Q62,6 120,112" },
];

interface Vals { carry: number; ball: number; launch: number; spin: number; }

const rand = ([a, b]: [number, number]) => a + Math.random() * (b - a);
const easeOut = (t: number) => 1 - Math.pow(1 - t, 3);

export default function PhoneDemo() {
  const [clubKey, setClubKey] = useState<ClubKey>("Driver");
  const [vals, setVals] = useState<Vals>({ carry: 287, ball: 168, launch: 12.4, spin: 2640 });
  const [animating, setAnimating] = useState(false);
  const [shot, setShot] = useState(0);
  const valsRef = useRef(vals);
  const rafRef = useRef<number | undefined>(undefined);

  const club = CLUBS.find((c) => c.key === clubKey)!;

  function hit() {
    if (animating) return;
    const target: Vals = {
      carry: rand(club.carry),
      ball: rand(club.ball),
      launch: rand(club.launch),
      spin: rand(club.spin),
    };
    const from = { ...valsRef.current };
    const dur = 1050;
    const start = performance.now();
    setAnimating(true);
    setShot((s) => s + 1);

    const tick = (now: number) => {
      const p = Math.min(1, (now - start) / dur);
      const e = easeOut(p);
      const cur: Vals = {
        carry: from.carry + (target.carry - from.carry) * e,
        ball: from.ball + (target.ball - from.ball) * e,
        launch: from.launch + (target.launch - from.launch) * e,
        spin: from.spin + (target.spin - from.spin) * e,
      };
      valsRef.current = cur;
      setVals(cur);
      if (p < 1) rafRef.current = requestAnimationFrame(tick);
      else setAnimating(false);
    };
    rafRef.current = requestAnimationFrame(tick);
  }

  return (
    <div className="phone">
      <div className="phone-notch" />
      <div className="phone-screen demo-screen">
        {/* Club selector */}
        <div className="demo-club-row">
          {CLUBS.map((c) => (
            <button
              key={c.key}
              className={`demo-club${c.key === clubKey ? " active" : ""}`}
              onClick={() => setClubKey(c.key)}
              disabled={animating}
            >
              {c.key}
            </button>
          ))}
        </div>

        {/* Carry headline */}
        <div>
          <div style={{ fontSize: 10, letterSpacing: "0.2em", textTransform: "uppercase", color: "var(--faint)", marginBottom: 6 }}>Carry</div>
          <div className="metric-big">{Math.round(vals.carry)}</div>
          <div style={{ fontSize: 12.5, color: "var(--muted)", marginTop: 6 }}>yards · {clubKey}</div>
        </div>

        {/* Ball flight tracer */}
        <svg
          key={shot}
          className={`demo-tracer ${animating ? "demo-fly" : "demo-static"}`}
          viewBox="0 0 240 120"
          preserveAspectRatio="xMidYMid meet"
          aria-hidden
        >
          <line className="demo-ground" x1="0" y1="113" x2="240" y2="113" />
          {/* flag at landing */}
          <line className="demo-flag" x1="228" y1="113" x2="228" y2="92" />
          <path className="demo-flag-cloth" d="M228,92 L240,96 L228,100 Z" />
          <path className="demo-arc-live" d={club.path} pathLength={1} />
          <circle className="demo-ball" r="3.4" style={{ offsetPath: `path("${club.path}")` }} />
        </svg>

        {/* Measured metrics */}
        <div className="metric-row">
          <div className="metric-chip"><div className="v">{Math.round(vals.ball)}</div><div className="l">Ball mph</div></div>
          <div className="metric-chip"><div className="v">{vals.launch.toFixed(1)}°</div><div className="l">Launch</div></div>
          <div className="metric-chip"><div className="v">{Math.round(vals.spin / 10) * 10}</div><div className="l">Spin</div></div>
        </div>

        {/* Hit + shot counter */}
        <button className="demo-hit" onClick={hit} disabled={animating}>
          {animating ? "Measuring…" : "Hit a shot"}
        </button>
        <div className="demo-shotno">{shot === 0 ? "Tap to track a shot" : `Shot ${shot} · ${clubKey}`}</div>
      </div>
    </div>
  );
}
