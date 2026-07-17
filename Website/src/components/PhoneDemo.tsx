"use client";

import { useEffect, useRef, useState } from "react";

/* An auto-playing, looping capture of the app: a ball sits at the tee, gets
   struck, flies along a live tracer to the flag while the numbers are measured,
   then cycles to the next club. Reads like a screen recording. */

type ClubKey = "Driver" | "7 Iron" | "Wedge";

interface Club {
  key: ClubKey;
  carry: [number, number];
  ball: [number, number];
  launch: [number, number];
  spin: [number, number];
  path: string; // flight arc in the 240x200 scene
}

const CLUBS: Club[] = [
  { key: "Driver", carry: [268, 292], ball: [161, 172], launch: [10.5, 14.5], spin: [2200, 2900], path: "M120,176 Q150,40 196,100" },
  { key: "7 Iron", carry: [150, 173], ball: [115, 125], launch: [16, 19.5], spin: [6300, 7300], path: "M120,176 Q140,38 178,116" },
  { key: "Wedge",  carry: [92, 118],  ball: [90, 105],  launch: [27, 34],   spin: [8600, 9900], path: "M120,176 Q128,34 158,126" },
];

interface Vals { carry: number; ball: number; launch: number; spin: number; }

const rand = ([a, b]: [number, number]) => Math.round((a + Math.random() * (b - a)) * 10) / 10;
const ease = (t: number) => 1 - Math.pow(1 - t, 2.2);
const clamp01 = (t: number) => Math.max(0, Math.min(1, t));

// Cycle timing, as fractions of one shot loop.
const CYCLE = 5200;
const IMPACT = 0.15;
const LAND = 0.6;

export default function PhoneDemo() {
  const [clubKey, setClubKey] = useState<ClubKey>("Driver");
  const [shot, setShot] = useState(1);

  const arcRef = useRef<SVGPathElement | null>(null);
  const guideRef = useRef<SVGPathElement | null>(null);
  const ballRef = useRef<SVGCircleElement | null>(null);
  const burstRef = useRef<SVGCircleElement | null>(null);
  const flashRef = useRef<HTMLDivElement | null>(null);
  const carryRef = useRef<HTMLDivElement | null>(null);
  const bsRef = useRef<HTMLDivElement | null>(null);
  const laRef = useRef<HTMLDivElement | null>(null);
  const spRef = useRef<HTMLDivElement | null>(null);

  // mutable engine state (kept out of React for smooth rAF)
  const eng = useRef({ idx: 0, target: pick(CLUBS[0]), start: 0, len: 1, jumpTo: -1, pinned: false });

  function jump(idx: number) {
    eng.current.jumpTo = idx;
    // A deliberate pick holds that club: the loop replays it with fresh numbers
    // instead of auto-advancing away ~5s later (which read as a broken selector).
    eng.current.pinned = true;
  }

  useEffect(() => {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    function loadClub(idx: number) {
      const club = CLUBS[idx];
      eng.current.idx = idx;
      eng.current.target = pick(club);
      const arc = arcRef.current, guide = guideRef.current;
      if (arc) { arc.setAttribute("d", club.path); eng.current.len = arc.getTotalLength(); arc.style.strokeDasharray = String(eng.current.len); }
      if (guide) guide.setAttribute("d", club.path);
      setClubKey(club.key);
    }

    function setNums(fp: number) {
      const t = eng.current.target;
      if (carryRef.current) carryRef.current.textContent = String(Math.round(t.carry * ease(fp)));
      if (bsRef.current) bsRef.current.textContent = String(Math.round(t.ball * clamp01(fp / 0.35)));
      if (laRef.current) laRef.current.textContent = (t.launch * clamp01(fp / 0.45)).toFixed(1) + "°";
      if (spRef.current) spRef.current.textContent = String(Math.round((t.spin * clamp01(fp / 0.6)) / 10) * 10);
    }

    function placeBall(fp: number) {
      const arc = arcRef.current, ball = ballRef.current;
      if (!arc || !ball) return;
      const pt = arc.getPointAtLength(ease(fp) * eng.current.len);
      const s = 1 - 0.5 * fp;
      ball.setAttribute("transform", `translate(${pt.x},${pt.y}) scale(${s})`);
      ball.style.opacity = fp >= 1 ? "0.92" : "1";
      arc.style.strokeDashoffset = String(eng.current.len * (1 - fp));
    }

    // initial paint
    loadClub(0);

    if (reduce) {
      placeBall(1);
      setNums(1);
      return;
    }

    let raf = 0;
    eng.current.start = performance.now();

    const frame = (now: number) => {
      let t = (now - eng.current.start) / CYCLE;

      if (eng.current.jumpTo >= 0) {
        loadClub(eng.current.jumpTo);
        eng.current.jumpTo = -1;
        eng.current.start = now;
        setShot((s) => s + 1);
        t = 0;
      } else if (t >= 1) {
        loadClub(eng.current.pinned ? eng.current.idx : (eng.current.idx + 1) % CLUBS.length);
        eng.current.start = now;
        setShot((s) => s + 1);
        t = 0;
      }

      // flight progress
      let fp = 0;
      if (t >= LAND) fp = 1;
      else if (t > IMPACT) fp = (t - IMPACT) / (LAND - IMPACT);
      placeBall(fp);
      setNums(fp);

      // impact flash + turf burst right after contact
      const flash = flashRef.current, burst = burstRef.current;
      const fl = t > IMPACT && t < IMPACT + 0.05 ? 1 - (t - IMPACT) / 0.05 : 0;
      if (flash) flash.style.opacity = String(fl * 0.7);
      if (burst) {
        const bt = clamp01((t - IMPACT) / 0.16);
        burst.style.opacity = t > IMPACT && bt < 1 ? String((1 - bt) * 0.8) : "0";
        burst.setAttribute("r", String(3 + bt * 16));
      }

      raf = requestAnimationFrame(frame);
    };
    raf = requestAnimationFrame(frame);
    return () => cancelAnimationFrame(raf);
  }, []);

  return (
    <div className="phone">
      <div className="phone-notch" />
      <div className="phone-screen live-screen">
        {/* Top: club selector + REC */}
        <div className="live-top">
          <div className="demo-club-row">
            {CLUBS.map((c, i) => (
              <button
                key={c.key}
                className={`demo-club${c.key === clubKey ? " active" : ""}`}
                onClick={() => jump(i)}
                type="button"
              >
                {c.key}
              </button>
            ))}
          </div>
        </div>

        {/* Carry headline */}
        <div className="live-carry">
          <div className="live-k">Carry<span className="live-rec"><span className="rec-dot" />REC</span></div>
          <div className="metric-big" ref={carryRef}>0</div>
          <div className="live-sub">yards · {clubKey}</div>
        </div>

        {/* Range scene with live ball flight */}
        <div className="live-scene">
          <div className="live-flash" ref={flashRef} />
          <svg viewBox="0 0 240 200" preserveAspectRatio="xMidYMid meet" aria-hidden>
            <line className="live-ground" x1="0" y1="178" x2="240" y2="178" />
            {/* flag in the distance */}
            <line className="live-pole" x1="196" y1="100" x2="196" y2="70" />
            <path className="live-flag" d="M196,70 L210,75 L196,80 Z" />
            <circle className="live-cup" cx="196" cy="100" r="2.5" />
            {/* faint predicted line + live tracer */}
            <path className="live-guide" ref={guideRef} fill="none" />
            <path className="live-arc" ref={arcRef} fill="none" pathLength={undefined} />
            {/* impact burst at the tee */}
            <circle className="live-burst" ref={burstRef} cx="120" cy="176" r="3" />
            {/* the ball */}
            <circle className="live-ball" ref={ballRef} r="5" />
          </svg>
        </div>

        {/* Measured metrics */}
        <div className="metric-row">
          <div className="metric-chip"><div className="v" ref={bsRef}>0</div><div className="l">Ball mph</div></div>
          <div className="metric-chip"><div className="v" ref={laRef}>0°</div><div className="l">Launch</div></div>
          <div className="metric-chip"><div className="v" ref={spRef}>0</div><div className="l">Spin</div></div>
        </div>

        <div className="live-foot"><span className="rec-dot" /> Live capture · shot {shot}</div>
      </div>
    </div>
  );
}

function pick(c: Club): Vals {
  return { carry: rand(c.carry), ball: rand(c.ball), launch: rand(c.launch), spin: rand(c.spin) };
}
