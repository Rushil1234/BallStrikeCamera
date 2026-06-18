"use client";

import { useState, useEffect, useRef } from "react";

function makeCode() {
  return String(Math.floor(Math.random() * 1_000_000)).padStart(6, "0");
}

type CourseOption = {
  id: string;
  name: string;
  sub: string;
  detail: string;
  meta: string;
  mark: string;
  hrefMode: "range" | "course";
  disabled?: boolean;
};

const COURSES: CourseOption[] = [
  {
    id: "range",
    name: "Range",
    sub: "Free practice · no scoring",
    detail: "Target greens, dispersion feedback, carry windows, and club gapping without starting a round.",
    meta: "Practice",
    mark: "R",
    hrefMode: "range",
  },
  {
    id: "pine-hollow",
    name: "Pine Hollow National",
    sub: "18 holes · par 72 · 6,900 yd",
    detail: "The built-in parkland course with the current scoring, map, hole picker, and full round flow.",
    meta: "Classic",
    mark: "18",
    hrefMode: "course",
  },
  {
    id: "pebble-private",
    name: "Cypress Coast Links",
    sub: "18 holes · coastal links · par 72",
    detail: "A rugged Pacific-style routing with ocean edges, cliffside holes, cypress belts, and coastal wind visuals.",
    meta: "New course",
    mark: "CC",
    hrefMode: "course",
  },
  {
    id: "augusta",
    name: "Augusta National",
    sub: "Coming soon",
    detail: "Reserved for a future private course build.",
    meta: "Preview",
    mark: "A",
    hrefMode: "course",
    disabled: true,
  },
];

type Stage = "select" | "launching" | "playing";

export default function PlayPage() {
  const [code, setCode] = useState("000000");
  const [stage, setStage] = useState<Stage>("select");
  const [connected, setConnected] = useState(false);
  const [simReady, setSimReady] = useState(false);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [activeCourse, setActiveCourse] = useState<CourseOption | null>(null);
  const hostRef = useRef<HTMLDivElement>(null);
  const iframeRef = useRef<HTMLIFrameElement>(null);

  useEffect(() => {
    setCode(makeCode());
  }, []);

  useEffect(() => {
    function onFullscreenChange() {
      setIsFullscreen(document.fullscreenElement === hostRef.current);
    }
    document.addEventListener("fullscreenchange", onFullscreenChange);
    return () => document.removeEventListener("fullscreenchange", onFullscreenChange);
  }, []);

  // Listen for messages from the sim iframe.
  useEffect(() => {
    function onMessage(e: MessageEvent) {
      if (e.data?.type === "SIM_READY") {
        setSimReady(true);
      }
      if (e.data?.type === "SIM_LAUNCHED") {
        setStage("playing");
      }
      if (e.data?.type === "APP_CONNECTED") {
        setConnected(true);
      }
    }
    window.addEventListener("message", onMessage);
    return () => window.removeEventListener("message", onMessage);
  }, []);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const mode = params.get("mode");
    const courseId = params.get("course") ?? "pine-hollow";
    const requestedCourse = mode === "range"
      ? COURSES.find((course) => course.id === "range")
      : mode === "course"
        ? COURSES.find((course) => course.id === courseId)
        : null;
    if (requestedCourse && !requestedCourse.disabled) {
      // Remember the requested mode, but don't launch until the phone is paired.
      setActiveCourse(requestedCourse);
    }
  }, []);

  // Auto-start the session the moment both the laptop and phone are connected
  // (with a mode chosen here or via the launch URL).
  useEffect(() => {
    if (connected && activeCourse && stage === "select") {
      setStage("launching");
    }
  }, [connected, activeCourse, stage]);

  useEffect(() => {
    if (stage !== "launching" || !activeCourse || !simReady || !connected) return;
    const msgType = activeCourse.id === "range" ? "START_RANGE" : "START_SIM";
    iframeRef.current?.contentWindow?.postMessage({ type: msgType, courseId: activeCourse.id }, "*");
  }, [activeCourse, simReady, stage, connected]);

  function writeLaunchUrl(course: CourseOption) {
    const url = new URL(window.location.href);
    url.searchParams.set("mode", course.hrefMode);
    if (course.hrefMode === "course") {
      url.searchParams.set("course", course.id);
    } else {
      url.searchParams.delete("course");
    }
    window.history.replaceState({}, "", url.toString());
  }

  function selectCourse(course: CourseOption) {
    if (course.disabled) return;
    // Phone pairing is optional — you can play in the browser standalone.
    setActiveCourse(course);
    setStage("launching");
    writeLaunchUrl(course);
  }

  function returnToSelect() {
    setStage("select");
    const url = new URL(window.location.href);
    url.searchParams.delete("mode");
    url.searchParams.delete("course");
    window.history.replaceState({}, "", url.toString());
  }

  async function toggleFullscreen() {
    try {
      if (document.fullscreenElement) {
        await document.exitFullscreen();
      } else {
        await hostRef.current?.requestFullscreen();
      }
    } catch {
      // Some embedded browsers disallow the Fullscreen API; stay in-page either way.
    }
  }

  const src = code === "000000" ? null : `/sim/index.html?code=${code}`;

  return (
    <div className="sim-host" ref={hostRef}>
      {/* Slim top bar — always visible */}
      <div className="sim-bar">
        <a className="sim-back" href="/">← True <span className="it">Carry.</span></a>
        <div className="sim-title">{activeCourse?.name ?? "Live Sim"}</div>
        {stage !== "select" ? (
          <div className="sim-bar-actions">
            <button className="sim-full" type="button" onClick={toggleFullscreen}>
              {isFullscreen ? "Exit full screen" : "Full screen"}
            </button>
            <button className="sim-change-btn" onClick={returnToSelect}>
              ↩ Change
            </button>
          </div>
        ) : (
          <span className="sim-full-hint">Choose mode</span>
        )}
      </div>

      {/* Sim iframe — always loaded so Supabase connection is live */}
      <div className="sim-iframe-wrap" style={{ opacity: stage === "playing" ? 1 : 0, pointerEvents: stage === "playing" ? "auto" : "none" }}>
        {src && (
          <iframe
            ref={iframeRef}
            className="sim-frame"
            src={src}
            title="True Carry Sim"
            allow="autoplay; fullscreen"
          />
        )}
      </div>

      {stage === "launching" && (
        <div className="sim-stage sim-stage-loading" role="status" aria-live="polite">
          <div className="sim-loading-card">
            <div className="sim-loading-mark">{activeCourse?.mark ?? "TC"}</div>
            <p>{simReady ? "Launching" : "Warming up"}</p>
            <h1>{activeCourse?.name ?? "True Carry Sim"}</h1>
            <span>{simReady ? "Handing off to the course runtime" : "Loading course assets and live shot connection"}</span>
          </div>
        </div>
      )}

      {/* Course selector */}
      {stage === "select" && (
        <div className="sim-stage sim-stage-select">
          <div className="sim-launch-shell">
            <section className="sim-launch-copy" aria-label="Play True Carry">
              <p className="sim-select-kicker">{connected ? "Phone connected" : "Browser sim ready"}</p>
              <h1 className="sim-select-title">Choose how you want to play.</h1>
              <p className="sim-select-body">
                {connected
                  ? "Your phone is paired — pick a mode and it'll feed real shots straight in."
                  : "Pick the range or an 18-hole course and play right here. Pair your iPhone (code on the right) anytime to add real shots."}
              </p>
              <div className="sim-status-row">
                <span><b>{COURSES.filter(c => !c.disabled).length}</b> playable modes</span>
                <span><b>{connected ? "Live" : "Optional"}</b> phone link</span>
              </div>
            </section>

            <section className="sim-course-panel" aria-label="Courses">
              <div className="sim-course-panel-head">
                <p>Course Select</p>
                <span>{connected ? "Ready for live shots" : "Ready in browser"}</span>
              </div>
              <div className="sim-course-list">
                {COURSES.map(c => (
                  <button
                    key={c.id}
                    className={`sim-course-card${c.disabled ? " disabled" : ""}`}
                    onClick={() => selectCourse(c)}
                    disabled={c.disabled}
                  >
                    <span className="sim-course-icon" aria-hidden="true">{c.mark}</span>
                    <span className="sim-course-info">
                      <span className="sim-course-meta">{c.meta}</span>
                      <span className="sim-course-name">{c.name}</span>
                      <span className="sim-course-sub">{c.sub}</span>
                      <span className="sim-course-detail">{c.detail}</span>
                    </span>
                    <span className="sim-course-action">{c.disabled ? "Soon" : "Play"}</span>
                  </button>
                ))}
              </div>
            </section>

            <aside className="sim-pairing-panel" aria-label="Phone pairing">
              <div className="sim-pairing-top">
                <span className={`sim-connection-dot${connected ? " connected" : ""}`} aria-hidden="true" />
                <span>{connected ? "Connected" : "Pair iPhone"}</span>
              </div>
              <h2 className="sim-pairing-title">Live shot input</h2>
              <p className="sim-pairing-sub">
                Open the TrueCarry app, enter this code in Live Sim, then select any course here.
              </p>
              <div className="sim-pairing-code">{code}</div>
              <p className="sim-pairing-hint">
                {connected ? "Shots will feed the selected mode." : "The website sim works now; pairing adds real shots."}
              </p>
            </aside>
          </div>
        </div>
      )}
    </div>
  );
}
