"use client";

import { useEffect, useRef, useState, Suspense } from "react";
import { useSearchParams } from "next/navigation";
import SiteNav from "@/components/SiteNav";
import SimHost from "@/components/SimHost";
import Link from "next/link";

function SimContent() {
  const searchParams = useSearchParams();
  const urlCode = searchParams.get("code") ?? "";

  const [inputCode, setInputCode] = useState(urlCode);
  const [activeCode, setActiveCode] = useState(urlCode);
  const [launched, setLaunched] = useState(!!urlCode);
  const inputRef = useRef<HTMLInputElement>(null);

  // If the URL already has a code, auto-launch.
  useEffect(() => {
    if (urlCode && /^\d{6,10}$/.test(urlCode)) {
      setActiveCode(urlCode);
      setLaunched(true);
    }
  }, [urlCode]);

  function launch(code: string) {
    const trimmed = code.trim();
    if (!/^\d{6,10}$/.test(trimmed)) return;
    setActiveCode(trimmed);
    setLaunched(true);
    // Push ?code= into the URL so the user can share / bookmark.
    const url = new URL(window.location.href);
    url.searchParams.set("code", trimmed);
    window.history.replaceState({}, "", url.toString());
  }

  if (launched && activeCode) {
    return (
      <SimHost
        key={activeCode}
        src={`/sim/index.html?code=${activeCode}`}
        title="True Carry Live Sim"
        backLabel="✕ Change Code"
        onBack={() => {
          setLaunched(false);
          setInputCode("");
          setActiveCode("");
          setTimeout(() => inputRef.current?.focus(), 100);
        }}
      />
    );
  }

  return (
    <>
      <SiteNav />
      <main className="sim-landing">
        <div className="sim-landing-card">
          <div className="sim-landing-eyebrow">True Carry Live Sim</div>
          <h1 className="sim-landing-title">Stream shots to your browser</h1>
          <p className="sim-landing-desc">
            Open <strong>Sim → Live Sim</strong> in the True Carry iOS app and enter
            the 6-digit code below to see your shots in real-time, no PC, no cables.
          </p>

          <form
            className="sim-code-form"
            onSubmit={(e) => {
              e.preventDefault();
              launch(inputCode);
            }}
          >
            <input
aria-label="Pairing code"               ref={inputRef}
              className="sim-code-input"
              type="text"
              inputMode="numeric"
              maxLength={10}
              placeholder="000000"
              value={inputCode}
              onChange={(e) => setInputCode(e.target.value.replace(/\D/g, "").slice(0, 10))}
              autoFocus
              autoComplete="off"
            />
            <button
              className="sim-code-btn"
              type="submit"
              disabled={inputCode.length < 6}
            >
              Open Simulator
            </button>
          </form>

          <p className="sim-landing-hint">
            Want to play without pairing? <Link href="/play" className="sim-link">Open Course Select →</Link>
          </p>
          <p className="sim-landing-hint secondary">
            Don&apos;t have the app? <Link href="/#pricing" className="sim-link">Download True Carry →</Link>
          </p>
        </div>
      </main>

      <style>{`
        .sim-landing {
          min-height: 100vh;
          display: flex;
          align-items: center;
          justify-content: center;
          padding: 80px 24px 40px;
          background: var(--bg);
        }
        .sim-landing-card {
          max-width: 480px;
          width: 100%;
          text-align: center;
        }
        .sim-landing-eyebrow {
          font-size: 12px;
          font-weight: 700;
          letter-spacing: 0.12em;
          text-transform: uppercase;
          color: var(--gold);
          margin-bottom: 16px;
        }
        .sim-landing-title {
          font-size: clamp(1.8rem, 5vw, 2.6rem);
          font-weight: 700;
          color: var(--cream);
          margin-bottom: 16px;
          line-height: 1.15;
        }
        .sim-landing-desc {
          font-size: 15px;
          color: var(--muted);
          line-height: 1.65;
          margin-bottom: 36px;
        }
        .sim-landing-desc strong { color: var(--cream); }
        .sim-code-form {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 14px;
          margin-bottom: 24px;
        }
        .sim-code-input {
          width: 220px;
          text-align: center;
          font-size: 2.4rem;
          font-weight: 800;
          letter-spacing: 0.18em;
          padding: 16px 20px;
          border-radius: 14px;
          border: 1.5px solid var(--border);
          background: var(--surface);
          color: var(--cream);
          outline: none;
          font-family: var(--font-mono, monospace);
          transition: border-color 0.15s;
        }
        .sim-code-input:focus { border-color: var(--gold); }
        .sim-code-input::placeholder { color: var(--faint); }
        .sim-code-btn {
          padding: 14px 32px;
          border-radius: 12px;
          border: none;
          background: linear-gradient(135deg, #8CA585 0%, #4d7a55 100%);
          color: #fff;
          font-size: 15px;
          font-weight: 700;
          letter-spacing: 0.04em;
          cursor: pointer;
          transition: opacity 0.15s;
          width: 220px;
        }
        .sim-code-btn:disabled { opacity: 0.35; cursor: default; }
        .sim-landing-hint { font-size: 13px; color: var(--faint); }
        .sim-landing-hint.secondary { margin-top: 8px; }
        .sim-link { color: var(--gold); text-decoration: none; }
        .sim-link:hover { text-decoration: underline; }

        /* Fullscreen iframe mode */
        .sim-fullscreen {
          position: fixed;
          inset: 0;
          background: #0a110c;
          z-index: 1000;
        }
        .sim-iframe {
          width: 100%;
          height: 100%;
          border: none;
          display: block;
        }
        .sim-change-code {
          position: fixed;
          bottom: 16px;
          left: 50%;
          transform: translateX(-50%);
          z-index: 1001;
          padding: 8px 18px;
          border-radius: 20px;
          border: 1px solid rgba(255,255,255,0.15);
          background: rgba(0,0,0,0.55);
          color: rgba(255,255,255,0.6);
          font-size: 12px;
          font-weight: 600;
          letter-spacing: 0.06em;
          cursor: pointer;
          backdrop-filter: blur(8px);
          transition: color 0.15s;
        }
        .sim-change-code:hover { color: #fff; }
      `}</style>
    </>
  );
}

export default function SimPage() {
  return (
    <Suspense>
      <SimContent />
    </Suspense>
  );
}
