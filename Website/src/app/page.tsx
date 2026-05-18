import Link from "next/link";

export default function HomePage() {
  return (
    <>
      <nav>
        <span className="nav-logo">True Carry</span>
        <div className="nav-links">
          <Link href="/pricing">Pricing</Link>
          <Link href="/login" className="btn btn-gold" style={{ padding: "8px 20px", fontSize: "14px" }}>Sign In</Link>
        </div>
      </nav>

      <main className="container" style={{ paddingTop: 80, paddingBottom: 80 }}>
        {/* Hero */}
        <div style={{ textAlign: "center", maxWidth: 720, margin: "0 auto" }}>
          <div className="badge" style={{ marginBottom: 20 }}>Camera-based launch monitor</div>
          <h1 style={{ fontSize: "clamp(36px,6vw,64px)", fontWeight: 800, lineHeight: 1.1, marginBottom: 20 }}>
            Track every shot.<br />
            <span style={{ color: "var(--gold)" }}>Know every yard.</span>
          </h1>
          <p style={{ color: "var(--muted)", fontSize: 18, lineHeight: 1.7, marginBottom: 40 }}>
            True Carry turns your iPhone into a professional launch monitor. Measure ball speed,
            launch angle, and carry distance on the range or the course — no extra hardware needed.
          </p>
          <div style={{ display: "flex", gap: 16, justifyContent: "center", flexWrap: "wrap" }}>
            <Link href="/pricing" className="btn btn-gold">View Plans</Link>
            <Link href="/login" className="btn btn-outline">Sign In</Link>
          </div>
        </div>

        {/* Feature grid */}
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))", gap: 20, marginTop: 80 }}>
          {[
            { icon: "📐", title: "Ball Speed & Carry", body: "Measure carry distance and ball speed using your camera — no radar required." },
            { icon: "⛳", title: "Course Mode", body: "GPS hole view, live scoring, and shot tracking during your round." },
            { icon: "📊", title: "Shot Analytics", body: "Track trends, compare clubs, and identify patterns across every session." },
            { icon: "☁️", title: "Cloud Sync", body: "Your shots and rounds sync across all your devices automatically." },
          ].map(f => (
            <div key={f.title} className="card">
              <div style={{ fontSize: 32, marginBottom: 12 }}>{f.icon}</div>
              <h3 style={{ fontSize: 18, fontWeight: 700, marginBottom: 8 }}>{f.title}</h3>
              <p style={{ color: "var(--muted)", fontSize: 14, lineHeight: 1.6 }}>{f.body}</p>
            </div>
          ))}
        </div>

        {/* CTA */}
        <div className="card" style={{ textAlign: "center", marginTop: 60 }}>
          <h2 style={{ fontSize: 28, fontWeight: 700, marginBottom: 12 }}>Ready to play your best?</h2>
          <p style={{ color: "var(--muted)", marginBottom: 24 }}>Download True Carry and subscribe at truecarry.app/pricing.</p>
          <Link href="/pricing" className="btn btn-gold">Get Started</Link>
        </div>
      </main>

      <footer>
        <div style={{ display: "flex", gap: 24, justifyContent: "center", marginBottom: 16 }}>
          <Link href="/privacy">Privacy</Link>
          <Link href="/terms">Terms</Link>
          <Link href="/pricing">Pricing</Link>
        </div>
        © {new Date().getFullYear()} True Carry. All rights reserved.
      </footer>
    </>
  );
}
