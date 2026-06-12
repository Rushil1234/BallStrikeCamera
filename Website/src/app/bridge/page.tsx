import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "TrueCarry Bridge — Bluetooth PC Relay",
  description:
    "Download the TrueCarry Bridge to connect your iPhone to GSPro or OpenGolfSim via Bluetooth when Wi-Fi isn't available.",
};

const STEPS_WIN = [
  "Download both files below into the same folder on your PC.",
  'Double-click "TrueCarry-Bridge-Windows.bat" — it installs everything automatically.',
  "Open True Carry → Sim Mode → tap Bluetooth on your iPhone.",
  "The bridge connects and you're ready to play.",
];

const STEPS_MAC = [
  "Download both files below into the same folder on your Mac.",
  'Double-click "TrueCarry-Bridge-Mac.command" and allow it in System Settings if prompted.',
  "Open True Carry → Sim Mode → tap Bluetooth on your iPhone.",
  "The bridge connects and you're ready to play.",
];

const FAQ = [
  {
    q: "Does this require Wi-Fi?",
    a: "No — the bridge uses Bluetooth LE between your iPhone and your PC. Your PC still needs GSPro or OpenGolfSim running on localhost.",
  },
  {
    q: "Does it work with both GSPro and OpenGolfSim?",
    a: "Yes. The bridge auto-detects whichever simulator is running on port 921 (GSPro) or 3111 (OpenGolfSim) when it starts.",
  },
  {
    q: "Does it work on Mac with GSPro via Crossover?",
    a: "Yes. Crossover apps still listen on localhost, so the bridge connects to GSPro the same way it does on Windows.",
  },
  {
    q: "What if Bluetooth permission is denied?",
    a: 'On Mac: System Settings → Privacy & Security → Bluetooth → allow Terminal or TrueCarry-Bridge. On Windows: Settings → Bluetooth & devices → make sure Bluetooth is on.',
  },
  {
    q: "Can I set it to start automatically?",
    a: 'Yes — run the bridge from the command line with the "--setup-startup" flag and it will launch automatically every time you log in.',
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
        <Link
          href="/"
          style={{
            fontSize: 13,
            color: "var(--muted)",
            textDecoration: "none",
          }}
        >
          ← Back to home
        </Link>
      </nav>

      <div style={{ maxWidth: 720, margin: "0 auto", padding: "0 24px" }}>
        {/* Hero */}
        <div style={{ textAlign: "center", padding: "64px 0 48px" }}>
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
            <span>🔵</span> Bluetooth PC Relay
          </div>

          <h1
            style={{
              fontFamily: "var(--font-serif)",
              fontSize: "clamp(34px, 6vw, 52px)",
              fontWeight: 400,
              lineHeight: 1.1,
              marginBottom: 20,
              color: "var(--cream)",
            }}
          >
            TrueCarry Bridge
          </h1>
          <p
            style={{
              fontSize: 17,
              color: "var(--muted)",
              lineHeight: 1.65,
              maxWidth: 520,
              margin: "0 auto 12px",
            }}
          >
            No Wi-Fi at the sim bay? No problem. The TrueCarry Bridge runs on
            your PC and relays shots from the True Carry app on your iPhone
            directly to{" "}
            <strong style={{ color: "var(--text)" }}>GSPro</strong> or{" "}
            <strong style={{ color: "var(--text)" }}>OpenGolfSim</strong> over
            Bluetooth — no network required.
          </p>
        </div>

        {/* Download cards */}
        <div
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))",
            gap: 16,
            marginBottom: 56,
          }}
        >
          {/* Windows */}
          <div
            style={{
              backgroundColor: "var(--surface)",
              border: "1px solid rgba(255,255,255,0.08)",
              borderRadius: 16,
              padding: 28,
            }}
          >
            <div
              style={{
                fontSize: 36,
                marginBottom: 12,
                lineHeight: 1,
              }}
            >
              🪟
            </div>
            <h2
              style={{
                fontSize: 18,
                fontWeight: 700,
                marginBottom: 8,
                color: "var(--cream)",
              }}
            >
              Windows
            </h2>
            <p
              style={{
                fontSize: 13,
                color: "var(--muted)",
                lineHeight: 1.6,
                marginBottom: 20,
              }}
            >
              Works with GSPro (port 921) and OpenGolfSim (port 3111).
              Requires Python 3.9+ — the installer handles the rest.
            </p>
            <div
              style={{ display: "flex", flexDirection: "column", gap: 10 }}
            >
              <a
                href="/downloads/TrueCarry-Bridge-Windows.bat"
                download
                style={dlButtonStyle("#B89A5E", "#1E2A22")}
              >
                ⬇ Download for Windows
              </a>
              <a
                href="/downloads/bridge.py"
                download
                style={dlButtonStyle("rgba(255,255,255,0.07)", "var(--muted)")}
              >
                bridge.py (also needed)
              </a>
            </div>
          </div>

          {/* Mac */}
          <div
            style={{
              backgroundColor: "var(--surface)",
              border: "1px solid rgba(255,255,255,0.08)",
              borderRadius: 16,
              padding: 28,
            }}
          >
            <div
              style={{
                fontSize: 36,
                marginBottom: 12,
                lineHeight: 1,
              }}
            >
              🍎
            </div>
            <h2
              style={{
                fontSize: 18,
                fontWeight: 700,
                marginBottom: 8,
                color: "var(--cream)",
              }}
            >
              Mac
            </h2>
            <p
              style={{
                fontSize: 13,
                color: "var(--muted)",
                lineHeight: 1.6,
                marginBottom: 20,
              }}
            >
              Works with GSPro via Crossover and OpenGolfSim. Requires
              Python 3 (pre-installed on most Macs).
            </p>
            <div
              style={{ display: "flex", flexDirection: "column", gap: 10 }}
            >
              <a
                href="/downloads/TrueCarry-Bridge-Mac.command"
                download
                style={dlButtonStyle("#B89A5E", "#1E2A22")}
              >
                ⬇ Download for Mac
              </a>
              <a
                href="/downloads/bridge.py"
                download
                style={dlButtonStyle("rgba(255,255,255,0.07)", "var(--muted)")}
              >
                bridge.py (also needed)
              </a>
            </div>
          </div>
        </div>

        {/* Instructions */}
        <div style={{ marginBottom: 56 }}>
          <h2
            style={{
              fontFamily: "var(--font-serif)",
              fontSize: 28,
              fontWeight: 400,
              marginBottom: 32,
              color: "var(--cream)",
            }}
          >
            How to set it up
          </h2>
          <div
            style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 32 }}
          >
            <StepList title="Windows" steps={STEPS_WIN} />
            <StepList title="Mac" steps={STEPS_MAC} />
          </div>
        </div>

        {/* FAQ */}
        <div>
          <h2
            style={{
              fontFamily: "var(--font-serif)",
              fontSize: 28,
              fontWeight: 400,
              marginBottom: 28,
              color: "var(--cream)",
            }}
          >
            Common questions
          </h2>
          <div
            style={{ display: "flex", flexDirection: "column", gap: 1 }}
          >
            {FAQ.map(({ q, a }) => (
              <div
                key={q}
                style={{
                  backgroundColor: "var(--surface)",
                  padding: "20px 24px",
                  borderRadius: 12,
                  marginBottom: 8,
                }}
              >
                <p
                  style={{
                    fontSize: 15,
                    fontWeight: 700,
                    color: "var(--cream)",
                    marginBottom: 8,
                  }}
                >
                  {q}
                </p>
                <p
                  style={{
                    fontSize: 14,
                    color: "var(--muted)",
                    lineHeight: 1.65,
                  }}
                >
                  {a}
                </p>
              </div>
            ))}
          </div>
        </div>
      </div>
    </main>
  );
}

function StepList({ title, steps }: { title: string; steps: string[] }) {
  return (
    <div>
      <p
        style={{
          fontSize: 12,
          fontWeight: 700,
          letterSpacing: "0.6px",
          color: "var(--gold)",
          marginBottom: 16,
          textTransform: "uppercase",
        }}
      >
        {title}
      </p>
      <ol
        style={{
          listStyle: "none",
          display: "flex",
          flexDirection: "column",
          gap: 14,
        }}
      >
        {steps.map((step, i) => (
          <li key={i} style={{ display: "flex", gap: 14, alignItems: "flex-start" }}>
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
              {i + 1}
            </span>
            <p style={{ fontSize: 14, color: "var(--muted)", lineHeight: 1.65, paddingTop: 2 }}>
              {step}
            </p>
          </li>
        ))}
      </ol>
    </div>
  );
}

function dlButtonStyle(bg: string, color: string): React.CSSProperties {
  return {
    display: "block",
    textAlign: "center",
    padding: "12px 16px",
    borderRadius: 10,
    backgroundColor: bg,
    color,
    fontSize: 14,
    fontWeight: 600,
    textDecoration: "none",
    transition: "opacity 0.15s",
  };
}
