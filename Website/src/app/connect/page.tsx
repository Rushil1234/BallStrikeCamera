"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";

// The bridge serves its status here (see Bridge/bridge.py → STATUS_HTTP_PORT).
const STATUS_URL = "http://127.0.0.1:8421/status";

type BridgeStatus = {
  running: boolean;
  sim: string | null;
  simFound: boolean;
  bleConnected: boolean;
  ready: boolean;
  port: number | null;
  shots: number;
};

type Phase = "checking" | "no-bridge" | "no-sim" | "no-phone" | "ready";

export default function ConnectPage() {
  // null = still doing the first check
  const [reachable, setReachable] = useState<boolean | null>(null);
  const [status, setStatus] = useState<BridgeStatus | null>(null);
  const activeRef = useRef(true);

  useEffect(() => {
    activeRef.current = true;

    async function poll() {
      try {
        const ctrl = new AbortController();
        const t = setTimeout(() => ctrl.abort(), 1500);
        const res = await fetch(STATUS_URL, { signal: ctrl.signal, cache: "no-store" });
        clearTimeout(t);
        const json = (await res.json()) as BridgeStatus;
        if (!activeRef.current) return;
        setStatus(json);
        setReachable(true);
      } catch {
        if (!activeRef.current) return;
        setReachable(false);
        setStatus(null);
      }
    }

    poll();
    const id = setInterval(poll, 2000);
    return () => {
      activeRef.current = false;
      clearInterval(id);
    };
  }, []);

  const phase: Phase =
    reachable === null
      ? "checking"
      : reachable === false
      ? "no-bridge"
      : !status?.simFound
      ? "no-sim"
      : !status?.ready
      ? "no-phone"
      : "ready";

  const simName = status?.sim ?? "your simulator";

  return (
    <>
      <SiteNav />
      <main
        style={{
          minHeight: "100vh",
          backgroundColor: "var(--bg)",
          color: "var(--text)",
          fontFamily: "var(--font-sans), sans-serif",
          padding: "40px 0 80px",
        }}
      >
      <div style={{ maxWidth: 620, margin: "0 auto", padding: "0 24px" }}>
        {/* Hero */}
        <div style={{ textAlign: "center", padding: "56px 0 36px" }}>
          <div
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: 8,
              backgroundColor: "rgba(184,154,94,0.12)",
              border: "1px solid rgba(184,154,94,0.3)",
              borderRadius: 100,
              padding: "6px 16px",
              fontSize: 12,
              color: "var(--gold)",
              marginBottom: 24,
              letterSpacing: "0.4px",
            }}
          >
            <span>🔌</span> Connection Status
          </div>
          <h1
            style={{
              fontFamily: "var(--font-serif)",
              fontSize: "clamp(32px, 6vw, 46px)",
              fontWeight: 400,
              lineHeight: 1.1,
              marginBottom: 16,
              color: "var(--cream)",
            }}
          >
            Are you connected?
          </h1>
          <p style={{ fontSize: 15, color: "var(--muted)", lineHeight: 1.65, maxWidth: 460, margin: "0 auto" }}>
            Keep this page open on the <strong style={{ color: "var(--text)" }}>same computer</strong> that&rsquo;s
            running the TrueCarry Bridge. It updates automatically — no refresh needed.
          </p>
        </div>

        {/* Big status banner */}
        <BannerCard phase={phase} simName={simName} shots={status?.shots ?? 0} />

        {/* Step checklist */}
        <div
          style={{
            backgroundColor: "var(--surface)",
            border: "1px solid var(--border)",
            borderRadius: 16,
            padding: "8px 24px",
            marginTop: 16,
          }}
        >
          <StepRow
            done={reachable === true}
            pending={reachable === null}
            title="Bridge running on this computer"
            detail={
              reachable === true
                ? "TrueCarry Bridge is up."
                : reachable === false
                ? "Can't reach the bridge — start it, then keep its window open."
                : "Checking…"
            }
          />
          <Divider />
          <StepRow
            done={!!status?.simFound}
            pending={reachable !== true}
            title="Simulator detected"
            detail={
              status?.simFound
                ? `${status.sim} found${status.port ? ` (port ${status.port})` : ""}.`
                : reachable === true
                ? "Start GSPro or OpenGolfSim on this computer."
                : "—"
            }
          />
          <Divider />
          <StepRow
            done={!!status?.ready}
            pending={!status?.simFound}
            title="iPhone connected"
            detail={
              status?.ready
                ? "True Carry is paired over Bluetooth — shots will forward automatically."
                : status?.simFound
                ? "Open True Carry → Sim Mode → Bluetooth on your iPhone."
                : "—"
            }
          />
        </div>

        {/* Footer help */}
        <p style={{ fontSize: 12, color: "var(--muted)", textAlign: "center", marginTop: 24, lineHeight: 1.6 }}>
          Don&rsquo;t have the bridge yet?{" "}
          <Link href="/bridge" style={{ color: "var(--gold-bright)" }}>
            Download it here
          </Link>
          . If the status never updates, open this page in Chrome or Edge on the computer running the bridge.
        </p>
      </div>
      </main>
      <SiteFooter />
    </>
  );
}

// ── Banner ──────────────────────────────────────────────────────────────────

function BannerCard({ phase, simName, shots }: { phase: Phase; simName: string; shots: number }) {
  const config: Record<Phase, { color: string; bg: string; icon: string; title: string; sub: string }> = {
    checking: {
      color: "var(--muted)",
      bg: "rgba(174,176,162,0.10)",
      icon: "⏳",
      title: "Checking…",
      sub: "Looking for the bridge on this computer.",
    },
    "no-bridge": {
      color: "#D8A24A",
      bg: "rgba(216,162,74,0.10)",
      icon: "🟠",
      title: "Waiting for the bridge",
      sub: "Start TrueCarry Bridge on this computer and keep its window open.",
    },
    "no-sim": {
      color: "#D8A24A",
      bg: "rgba(216,162,74,0.10)",
      icon: "🟠",
      title: "Bridge running — no simulator yet",
      sub: "Open GSPro or OpenGolfSim, then it'll be detected automatically.",
    },
    "no-phone": {
      color: "#D8A24A",
      bg: "rgba(216,162,74,0.10)",
      icon: "🔵",
      title: `${simName} ready — waiting for your iPhone`,
      sub: "Open True Carry → Sim Mode → Bluetooth on your iPhone.",
    },
    ready: {
      color: "#3FB68B",
      bg: "rgba(63,182,139,0.12)",
      icon: "✅",
      title: "Connected — you're ready to play!",
      sub: `Shots from True Carry are forwarding to ${simName}. Go ahead and start your round.`,
    },
  };
  const c = config[phase];
  const pulsing = phase !== "ready" && phase !== "checking";

  return (
    <div
      style={{
        backgroundColor: c.bg,
        border: `1px solid ${c.color}`,
        borderRadius: 18,
        padding: "28px 26px",
        textAlign: "center",
      }}
    >
      <div
        style={{
          fontSize: 40,
          lineHeight: 1,
          marginBottom: 14,
          animation: pulsing ? "tcpulse 1.6s ease-in-out infinite" : undefined,
        }}
      >
        {c.icon}
      </div>
      <div style={{ fontSize: 21, fontWeight: 700, color: "var(--cream)", marginBottom: 8 }}>{c.title}</div>
      <p style={{ fontSize: 14, color: "var(--muted)", lineHeight: 1.6, maxWidth: 420, margin: "0 auto" }}>{c.sub}</p>
      {phase === "ready" && shots > 0 && (
        <div style={{ fontSize: 13, color: c.color, marginTop: 14, fontWeight: 600 }}>
          🏌️ {shots} shot{shots === 1 ? "" : "s"} relayed
        </div>
      )}
      <style>{`@keyframes tcpulse { 0%,100% { opacity: 1; } 50% { opacity: 0.45; } }`}</style>
    </div>
  );
}

// ── Step row ──────────────────────────────────────────────────────────────────

function StepRow({
  done,
  pending,
  title,
  detail,
}: {
  done: boolean;
  pending: boolean;
  title: string;
  detail: string;
}) {
  const color = done ? "#3FB68B" : pending ? "var(--muted)" : "#D8A24A";
  return (
    <div style={{ display: "flex", gap: 14, alignItems: "flex-start", padding: "18px 0" }}>
      <div
        style={{
          flexShrink: 0,
          width: 24,
          height: 24,
          borderRadius: "50%",
          backgroundColor: done ? "rgba(63,182,139,0.18)" : "var(--border)",
          border: `1px solid ${color}`,
          color,
          fontSize: 13,
          fontWeight: 700,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        {done ? "✓" : pending ? "·" : "!"}
      </div>
      <div>
        <p style={{ fontSize: 15, fontWeight: 600, color: "var(--cream)", marginBottom: 3 }}>{title}</p>
        <p style={{ fontSize: 13, color: "var(--muted)", lineHeight: 1.55 }}>{detail}</p>
      </div>
    </div>
  );
}

function Divider() {
  return <div style={{ height: 1, backgroundColor: "var(--border)" }} />;
}
