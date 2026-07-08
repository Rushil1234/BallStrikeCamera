"use client";

import { useState, useEffect, useRef } from "react";

function makeCode() {
  // Cryptographically-random pairing code — Math.random() is predictable and
  // must not be used for a value that gates access to a live session channel.
  // 9 digits (~30 bits): stage 2 of the pairing hardening; the iOS app has
  // accepted 6-10 digit codes since the 2026-07-01 build (stage 1).
  // Three digits per uint32 keeps every position uniform without BigInt.
  const buf = crypto.getRandomValues(new Uint32Array(3));
  return Array.from(buf, (v) => String(v % 1000).padStart(3, "0")).join("");
}

import QRCode from "qrcode";
import { SIM_COURSES, type SimCourse } from "@/lib/courses";

type CourseOption = SimCourse;
const COURSES: CourseOption[] = SIM_COURSES;

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
  const [players, setPlayers] = useState(1);
  const [names, setNames] = useState<string[]>(["", "", "", ""]);
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
      // Only trust messages from our own sim iframe (served same-origin).
      if (e.origin !== window.location.origin) return;
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
    iframeRef.current?.contentWindow?.postMessage({
      type: msgType,
      courseId: activeCourse.id,
      players,
      names: names.slice(0, players).map((n, i) => n.trim() || `PLAYER ${i + 1}`),
    }, window.location.origin);
  }, [activeCourse, simReady, stage, connected, players, names]);

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

  const [qrUrl, setQrUrl] = useState<string | null>(null);
  useEffect(() => {
    if (!code || code === "000000") return;
    // Scanning with the iPhone camera opens the app and pairs instantly.
    QRCode.toDataURL(`truecarry://livesim?code=${code}`, {
      width: 220, margin: 1,
      color: { dark: "#16201a", light: "#ece4d2" },
    }).then(setQrUrl).catch(() => setQrUrl(null));
  }, [code]);

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

  // Switch mode/course mid-session WITHOUT ending the phone pairing: the sim iframe
  // stays loaded and connected; the selector re-opens and picking a mode just posts a
  // fresh START_SIM / START_RANGE to the same runtime. Clearing activeCourse matters —
  // otherwise the auto-start effect would relaunch the old mode instantly.
  function switchMode() {
    setActiveCourse(null);
    setStage("select");
  }

  function endSession() {
    iframeRef.current?.contentWindow?.postMessage({ type: "END_SESSION" }, window.location.origin);
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
        {/* Home link only on the menu — during a session the way out is End session. */}
        {stage === "select" ? (
          <a className="sim-back" href="/">← True <span className="it">Carry.</span></a>
        ) : (
          <span aria-hidden="true" />
        )}
        <div className="sim-title">{activeCourse?.name ?? "Live Sim"}</div>
        {stage !== "select" ? (
          <div className="sim-bar-actions">
            <button className="sim-full" type="button" onClick={toggleFullscreen}>
              {isFullscreen ? "Exit full screen" : "Full screen"}
            </button>
            {connected && (
              <button className="sim-change-btn" onClick={switchMode}>
                {"⇄ Switch mode"}
              </button>
            )}
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
              <div className="sim-players-row" role="group" aria-label="Players">
                <span className="sim-players-label">Players</span>
                {[1, 2, 3, 4].map(n => (
                  <button
                    key={n}
                    className={`sim-players-btn${players === n ? " active" : ""}`}
                    onClick={() => setPlayers(n)}
                    aria-pressed={players === n}
                  >
                    {n}
                  </button>
                ))}
                {players > 1 && <span className="sim-players-hint">hot-seat match · everyone plays each hole</span>}
              </div>
              {players > 1 && (
                <div className="sim-players-names">
                  {Array.from({ length: players }, (_, i) => (
                    <input
                      key={i}
                      aria-label={`Player ${i + 1} name`}
                      placeholder={`Player ${i + 1}`}
                      maxLength={12}
                      value={names[i]}
                      onChange={e => setNames(ns => ns.map((v, j) => (j === i ? e.target.value : v)))}
                    />
                  ))}
                </div>
              )}
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
              {!connected && qrUrl && (
                <div className="sim-pairing-qr">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={qrUrl} alt="Scan with your iPhone camera to pair" />
                  <span>Scan with your iPhone camera</span>
                </div>
              )}
              <div className="sim-pairing-code-wrap">
                <div className="sim-pairing-code">{code}</div>
                <button type="button" className="sim-pairing-copy" onClick={copyCode}>
                  {copied ? "Copied ✓" : "Copy"}
                </button>
              </div>
              {!connected && (
                <p className="sim-pairing-or">or type the code in Sim → Live Sim</p>
              )}
              {connected ? (
                <>
                  <p className="sim-pairing-hint">Shots will feed the selected mode in real time.</p>
                  <a className="sim-pairing-watch" href={`/watch?code=${code}`} target="_blank" rel="noreferrer">
                    Share a spectate link →
                  </a>
                </>
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
