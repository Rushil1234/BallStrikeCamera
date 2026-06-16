import type { Metadata } from "next";
import Link from "next/link";
import CopyCommand from "./CopyCommand";

export const metadata: Metadata = {
  title: "TrueCarry Bridge — Connect to GSPro or OpenGolfSim",
  description:
    "One command sets up the TrueCarry Bridge so your iPhone can send shots to GSPro or OpenGolfSim over Bluetooth. No install, no warnings.",
};

const MAC_CMD = "curl -fsSL https://truecarry.vercel.app/downloads/install.sh | bash";
const WIN_CMD = "irm https://truecarry.vercel.app/downloads/install.ps1 | iex";

const FAQ = [
  {
    q: "Why a command instead of an app I double-click?",
    a: "macOS and Windows block downloaded apps from unidentified developers — that's the \"could not verify\" warning. Running this command avoids that entirely: nothing is downloaded as a blocked file, so it just runs. It's the same approach used by tools like Homebrew.",
  },
  {
    q: "Is this safe? What does it do?",
    a: "It sets up a small, self-contained Python helper in a .truecarry folder in your home directory, installs one Bluetooth library, and runs the bridge. Nothing else on your system is touched, and you can read the exact script before running it (see the links at the bottom).",
  },
  {
    q: "Does this require Wi-Fi?",
    a: "No — the bridge talks to your iPhone over Bluetooth LE. Your computer just needs GSPro or OpenGolfSim running.",
  },
  {
    q: "Does it work with both GSPro and OpenGolfSim?",
    a: "Yes. The bridge auto-detects whichever simulator is running on port 921 (GSPro) or 3111 (OpenGolfSim).",
  },
  {
    q: "Do I need Python?",
    a: "Mac usually has it already. If it's missing, the command tells you exactly what to do. On Windows, install Python from python.org (check \"Add to PATH\") and run the command again.",
  },
  {
    q: "How do I run it next time?",
    a: "Paste the same command again. It reuses what's installed and always grabs the latest bridge, so you're never out of date.",
  },
];

export default function BridgePage() {
  return (
    <main
      style={{
        minHeight: "100vh",
        backgroundColor: "var(--bg)",
        color: "var(--text)",
        fontFamily: "var(--font-sans), sans-serif",
        padding: "0 0 80px",
      }}
    >
      {/* Nav */}
      <nav
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          padding: "20px 32px",
          borderBottom: "1px solid rgba(255,255,255,0.08)",
        }}
      >
        <Link href="/" style={{ textDecoration: "none" }}>
          <span
            style={{
              fontFamily: "var(--font-serif)",
              fontSize: 22,
              color: "var(--gold)",
              letterSpacing: "-0.3px",
            }}
          >
            True Carry
          </span>
        </Link>
        <Link href="/" style={{ fontSize: 13, color: "var(--muted)", textDecoration: "none" }}>
          ← Back to home
        </Link>
      </nav>

      <div style={{ maxWidth: 640, margin: "0 auto", padding: "0 24px" }}>
        {/* Hero */}
        <div style={{ textAlign: "center", padding: "56px 0 40px" }}>
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
            <span>🔵</span> Connect to your simulator
          </div>

          <h1
            style={{
              fontFamily: "var(--font-serif)",
              fontSize: "clamp(32px, 6vw, 50px)",
              fontWeight: 400,
              lineHeight: 1.1,
              marginBottom: 18,
              color: "var(--cream)",
            }}
          >
            One command.
            <br />
            Then just play.
          </h1>
          <p style={{ fontSize: 16, color: "var(--muted)", lineHeight: 1.65, maxWidth: 500, margin: "0 auto" }}>
            The TrueCarry Bridge relays shots from the app on your iPhone to{" "}
            <strong style={{ color: "var(--text)" }}>GSPro</strong> or{" "}
            <strong style={{ color: "var(--text)" }}>OpenGolfSim</strong> over Bluetooth — no Wi-Fi,
            no install, and no &ldquo;unverified developer&rdquo; warnings.
          </p>
        </div>

        {/* Mac — notarized download */}
        <div
          style={{
            backgroundColor: "var(--surface)",
            border: "1px solid rgba(255,255,255,0.08)",
            borderRadius: 16,
            padding: "24px 26px",
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 6 }}>
            <span style={{ fontSize: 24, lineHeight: 1 }}>🍎</span>
            <h2 style={{ fontSize: 18, fontWeight: 700, color: "var(--cream)" }}>On your Mac</h2>
          </div>
          <p style={{ fontSize: 13, color: "var(--muted)", lineHeight: 1.6, marginBottom: 16 }}>
            Signed &amp; notarized by Apple — no warnings, no Python needed. Download, open the disk
            image, and drag <strong style={{ color: "var(--text)" }}>TrueCarry Bridge</strong> into your
            Applications folder. A golf icon ⛳︎ then appears in your menu bar when you launch it.
          </p>
          <a
            href="/downloads/TrueCarryBridge.dmg"
            download
            style={{
              display: "block",
              textAlign: "center",
              padding: "13px 16px",
              borderRadius: 10,
              backgroundColor: "var(--cream)",
              color: "#1E2A22",
              fontSize: 15,
              fontWeight: 700,
              textDecoration: "none",
            }}
          >
            ⬇ Download for Mac (.dmg)
          </a>
          <details style={{ marginTop: 16 }}>
            <summary style={{ fontSize: 12, color: "var(--muted)", cursor: "pointer" }}>
              Prefer the command line?
            </summary>
            <p style={{ fontSize: 12, color: "var(--muted)", lineHeight: 1.6, margin: "10px 0" }}>
              Open Terminal (⌘ + Space → “Terminal”) and paste:
            </p>
            <CopyCommand command={MAC_CMD} />
          </details>
        </div>

        {/* Windows */}
        <div style={{ marginTop: 16 }}>
          <PlatformCard
            emoji="🪟"
            title="On Windows"
            openHint="Open PowerShell (Start menu → type “PowerShell”), then paste:"
            command={WIN_CMD}
          />
        </div>

        {/* Then in the app */}
        <div
          style={{
            marginTop: 28,
            backgroundColor: "var(--surface)",
            border: "1px solid rgba(255,255,255,0.08)",
            borderRadius: 16,
            padding: "24px 26px",
          }}
        >
          <h2 style={{ fontSize: 16, fontWeight: 700, color: "var(--cream)", marginBottom: 16 }}>
            Then, in the app
          </h2>
          <Step n="1" text="Make sure GSPro or OpenGolfSim is open on this computer." />
          <Step n="2" text="On your iPhone: open True Carry → Sim Mode → tap Bluetooth." />
          <Step n="3" text="It connects automatically — swing away." />

          <Link
            href="/connect"
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: 8,
              marginTop: 18,
              padding: "11px 20px",
              borderRadius: 100,
              border: "1px solid rgba(184,154,94,0.4)",
              backgroundColor: "rgba(184,154,94,0.10)",
              color: "var(--gold-bright)",
              fontSize: 14,
              fontWeight: 600,
              textDecoration: "none",
            }}
          >
            Check your connection live →
          </Link>
        </div>

        {/* FAQ */}
        <div style={{ marginTop: 56 }}>
          <h2
            style={{
              fontFamily: "var(--font-serif)",
              fontSize: 26,
              fontWeight: 400,
              marginBottom: 24,
              color: "var(--cream)",
            }}
          >
            Common questions
          </h2>
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            {FAQ.map(({ q, a }) => (
              <div
                key={q}
                style={{ backgroundColor: "var(--surface)", padding: "20px 24px", borderRadius: 12 }}
              >
                <p style={{ fontSize: 15, fontWeight: 700, color: "var(--cream)", marginBottom: 8 }}>{q}</p>
                <p style={{ fontSize: 14, color: "var(--muted)", lineHeight: 1.65 }}>{a}</p>
              </div>
            ))}
          </div>
        </div>

        {/* Manual fallback */}
        <p style={{ fontSize: 12, color: "var(--muted)", textAlign: "center", marginTop: 28, lineHeight: 1.7 }}>
          Prefer to inspect or run it yourself? View the{" "}
          <a href="/downloads/install.sh" style={{ color: "var(--gold-bright)" }}>
            Mac script
          </a>
          ,{" "}
          <a href="/downloads/install.ps1" style={{ color: "var(--gold-bright)" }}>
            Windows script
          </a>
          , or the{" "}
          <a href="/downloads/bridge.py" style={{ color: "var(--gold-bright)" }}>
            bridge itself
          </a>
          .
        </p>
      </div>
    </main>
  );
}

function PlatformCard({
  emoji,
  title,
  openHint,
  command,
}: {
  emoji: string;
  title: string;
  openHint: string;
  command: string;
}) {
  return (
    <div
      style={{
        backgroundColor: "var(--surface)",
        border: "1px solid rgba(255,255,255,0.08)",
        borderRadius: 16,
        padding: "24px 26px",
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 14 }}>
        <span style={{ fontSize: 24, lineHeight: 1 }}>{emoji}</span>
        <h2 style={{ fontSize: 18, fontWeight: 700, color: "var(--cream)" }}>{title}</h2>
      </div>
      <p style={{ fontSize: 13, color: "var(--muted)", lineHeight: 1.6, marginBottom: 14 }}>{openHint}</p>
      <CopyCommand command={command} />
    </div>
  );
}

function Step({ n, text }: { n: string; text: string }) {
  return (
    <div style={{ display: "flex", gap: 14, alignItems: "flex-start", marginBottom: 12 }}>
      <span
        style={{
          flexShrink: 0,
          width: 24,
          height: 24,
          borderRadius: "50%",
          backgroundColor: "rgba(184,154,94,0.15)",
          border: "1px solid rgba(184,154,94,0.35)",
          color: "var(--gold)",
          fontSize: 12,
          fontWeight: 700,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        {n}
      </span>
      <p style={{ fontSize: 14, color: "var(--muted)", lineHeight: 1.6, paddingTop: 2 }}>{text}</p>
    </div>
  );
}
