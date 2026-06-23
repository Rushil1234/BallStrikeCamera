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
  const [copied, setCopied] = useState(false);
  const [showEndConfirm, setShowEndConfirm] = useState(false);
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
      if (e.data?.type === "APP_DISCONNECTED") {
        // The phone left the live session — drop the link and return to the
        // (now re-locked) selector so the user can pair again.
        setConnected(false);
        setStage("select");
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

  // Safety net: never sit on the launch screen without a paired phone — the
  // round can't start, so fall back to the (gated) selector instead of hanging.
  useEffect(() => {
    if (stage === "launching" && !connected) setStage("select");
  }, [stage, connected]);

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
    // Require a paired phone before a round can start — pick is locked until then.
    if (!connected) return;
    setActiveCourse(course);
    setStage("launching");
    writeLaunchUrl(course);
  }

  async function copyCode() {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      // clipboard may be blocked in some embedded browsers — ignore
    }
  }

  function returnToSelect() {
    setStage("select");
    const url = new URL(window.location.href);
    url.searchParams.delete("mode");
    url.searchParams.delete("course");
    window.history.replaceState({}, "", url.toString());
  }

  // Exiting a live round ends the session for the paired phone too — so confirm
  // it clearly when connected, and signal the sim/phone on the way out.
  function requestExit() {
    if (connected) setShowEndConfirm(true);
    else returnToSelect();
  }

  function endSession() {
    iframeRef.current?.contentWindow?.postMessage({ type: "END_SESSION" }, "*");
    setConnected(false);
    setShowEndConfirm(false);
    returnToSelect();
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
            <button className="sim-change-btn" onClick={requestExit}>
              {connected ? "↩ End session" : "↩ Change"}
            </button>
          </div>
        ) : (
          <span className="sim-full-hint">{connected ? "Choose mode" : "Pair phone"}</span>
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
          <div className={`sim-launch-shell${connected ? " is-connected" : " is-locked"}`}>
            <section className="sim-launch-copy" aria-label="Play True Carry">
              <p className={`sim-select-kicker${connected ? "" : " waiting"}`}>
                {connected ? "● Phone connected" : "Step 1 — pair your iPhone"}
              </p>
              <h1 className="sim-select-title">Choose how you want to play.</h1>
              <p className="sim-select-body">
                {connected
                  ? "Your phone is paired — pick a mode and every shot you hit feeds straight into the sim."
                  : "Connect your iPhone with the code on the right to unlock the range and courses. The picks below stay locked until you're paired."}
              </p>
              <div className="sim-status-row">
                <span><b>{COURSES.filter(c => !c.disabled).length}</b> playable modes</span>
                <span><b>{connected ? "Live" : "Required"}</b> phone link</span>
              </div>
            </section>

            <section className="sim-course-panel" aria-label="Courses">
              <div className="sim-course-panel-head">
                <p>Course Select</p>
                <span>{connected ? "Ready for live shots" : "🔒 Pair phone to unlock"}</span>
              </div>
              <div className="sim-course-list">
                {COURSES.map(c => {
                  const locked = !c.disabled && !connected;
                  return (
                    <button
                      key={c.id}
                      className={`sim-course-card${c.disabled ? " disabled" : ""}${locked ? " locked" : ""}`}
                      onClick={() => selectCourse(c)}
                      disabled={c.disabled || !connected}
                      aria-disabled={c.disabled || !connected}
                    >
                      <span className="sim-course-icon" aria-hidden="true">{c.mark}</span>
                      <span className="sim-course-info">
                        <span className="sim-course-meta">{c.meta}</span>
                        <span className="sim-course-name">{c.name}</span>
                        <span className="sim-course-sub">{c.sub}</span>
                        <span className="sim-course-detail">{c.detail}</span>
                      </span>
                      <span className="sim-course-action">
                        {c.disabled ? "Soon" : locked ? "🔒" : "Play"}
                      </span>
                    </button>
                  );
                })}
              </div>
            </section>

            <aside className={`sim-pairing-panel${connected ? " is-connected" : " is-waiting"}`} aria-label="Phone pairing">
              <div className="sim-pairing-top">
                <span className={`sim-connection-dot${connected ? " connected" : ""}`} aria-hidden="true" />
                <span>{connected ? "iPhone connected" : "Pair to play"}</span>
              </div>
              <h2 className="sim-pairing-title">{connected ? "You're connected" : "Connect your iPhone"}</h2>
              <p className="sim-pairing-sub">
                {connected
                  ? "Pick a mode on the left and start hitting — your shots show up here live."
                  : "Open the TrueCarry app → Sim → Live Sim, then enter this code to unlock play."}
              </p>
              <div className="sim-pairing-code-wrap">
                <div className="sim-pairing-code">{code}</div>
                <button type="button" className="sim-pairing-copy" onClick={copyCode}>
                  {copied ? "Copied ✓" : "Copy"}
                </button>
              </div>
              {connected ? (
                <p className="sim-pairing-hint">Shots will feed the selected mode in real time.</p>
              ) : (
                <div className="sim-pairing-waiting" role="status" aria-live="polite">
                  <span className="sim-pairing-spinner" aria-hidden="true" />
                  Waiting for your phone…
                </div>
              )}
            </aside>
          </div>
        </div>
      )}

      {showEndConfirm && (
        <div className="sim-modal-scrim" role="dialog" aria-modal="true" onClick={() => setShowEndConfirm(false)}>
          <div className="sim-modal" onClick={(e) => e.stopPropagation()}>
            <h2 className="sim-modal-title">End this session?</h2>
            <p className="sim-modal-body">
              This disconnects your paired iPhone and ends the live round. You'll
              need to pair again with a new code to keep playing.
            </p>
            <div className="sim-modal-actions">
              <button className="sim-modal-cancel" onClick={() => setShowEndConfirm(false)}>
                Keep playing
              </button>
              <button className="sim-modal-end" onClick={endSession}>
                End session
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
