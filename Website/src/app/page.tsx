import Link from "next/link";
import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";
import Reveal from "@/components/Reveal";
import PhoneDemo from "@/components/PhoneDemo";
import PricingSection from "@/components/PricingSection";

// What True Carry measures — carry is the headline, the only gold number.
const MEASURES = [
  { k: "Ball speed", v: "128", u: "mph", note: "Read off the strike, not estimated from the club." },
  { k: "Launch angle", v: "17.6", u: "°", note: "The window the ball leaves on — degree by degree." },
  { k: "Carry", v: "172", u: "yd", carry: true, note: "The only number that doesn't lie. Air, not roll." },
];

// Three-feature breakdown
const FEATURES = [
  {
    title: "The numbers that matter",
    body: "Ball speed, launch, and true carry — read off a single iPhone camera at 240 frames a second. The same data a radar box gives you, without the box.",
  },
  {
    title: "A round, recorded",
    body: "GPS hole maps, live scoring, and shot tracking from the tee to the cup. A round you can go back and read, not a feed you scroll.",
  },
  {
    title: "Where your yards go",
    body: "Dispersion, club gapping, trends over the season. See the gap between your 7-iron and your 8, and watch it close.",
  },
];

export default function HomePage() {
  return (
    <>
      <SiteNav />

      {/* ───────── Hero ───────── */}
      <header className="hero">
        <div className="container hero-grid">
          <Reveal>
            <span className="eyebrow">The camera launch monitor</span>
            <h1 className="display" style={{ margin: "28px 0 26px" }}>
              Bear<br />every <span className="serif-i gold-text">yard.</span>
            </h1>
            <p className="lead" style={{ maxWidth: 460 }}>
              A launch monitor light enough for the bag, honest enough for the
              scorecard. True Carry reads ball speed, launch, and carry off the
              iPhone already in your bag — measured, modeled, played.
            </p>
            <div className="hero-cta">
              <Link href="#pricing" className="btn btn-gold btn-lg">See plans</Link>
              <Link href="/login" className="btn btn-outline btn-lg">Sign in</Link>
              <span className="hero-note">iPhone · no extra hardware</span>
            </div>
          </Reveal>

          <Reveal delay={120}>
            <div className="logo-field" aria-label="True Carry mark on forest field">
              <div className="dimples" aria-hidden />
              <img src="/truecarry-logo.png" alt="True Carry — Atlas mark" />
              <span className="tag">Primary · Forest</span>
            </div>
          </Reveal>
        </div>
      </header>

      {/* ───────── What we measure ───────── */}
      <section className="section container" id="measures" style={{ paddingTop: "clamp(40px,6vw,80px)" }}>
        <Reveal className="section-head" style={{ marginBottom: 34 }}>
          <span className="eyebrow">What True Carry measures</span>
          <h2 style={{ fontSize: "clamp(32px,5vw,56px)", margin: "22px 0 0", maxWidth: 640 }}>
            Three readings off one camera.
          </h2>
        </Reveal>
        <Reveal>
          <div className="measures">
            {MEASURES.map((m) => (
              <div className={`measure${m.carry ? " is-carry" : ""}`} key={m.k}>
                <div className="k">{m.k}</div>
                <div className="v">{m.v}<span className="u">{m.u}</span></div>
                <div className="note">{m.note}</div>
              </div>
            ))}
          </div>
        </Reveal>
        <Reveal>
          <p className="lead" style={{ marginTop: 26, maxWidth: 620 }}>
            Carry is the headline — never total distance, never the club, never the story
            you tell at the clubhouse. We round honestly and footnote everything.
          </p>
        </Reveal>
      </section>

      {/* ───────── Feature breakdown ───────── */}
      <section className="section container" id="features" style={{ paddingTop: 0 }}>
        <Reveal className="section-head" style={{ marginBottom: 8 }}>
          <span className="eyebrow">What it does</span>
          <h2 style={{ fontSize: "clamp(32px,5vw,56px)", margin: "22px 0 0", maxWidth: 620 }}>
            A launch monitor, minus the launch monitor.
          </h2>
        </Reveal>
        <div className="feature-list">
          {FEATURES.map((f, i) => (
            <Reveal key={f.title} as="div">
              <div className="feature-item">
                <span className="idx">{String(i + 1).padStart(2, "0")}</span>
                <h3>{f.title}</h3>
                <p>{f.body}</p>
              </div>
            </Reveal>
          ))}
        </div>
      </section>

      {/* ───────── In-app preview ───────── */}
      <section className="section container" id="app" style={{ paddingTop: 0 }}>
        <div className="hero-grid" style={{ alignItems: "center" }}>
          <Reveal>
            <span className="eyebrow">In the app</span>
            <h2 style={{ fontSize: "clamp(30px,4.4vw,52px)", margin: "22px 0 22px", maxWidth: 520 }}>
              The brand, at <span className="serif-i gold-text">arm&apos;s length.</span>
            </h2>
            <p className="lead" style={{ maxWidth: 460 }}>
              Forest holds the screen. Bone carries the type. Gold is reserved for the one
              number that matters most in any view. No streaks, no badges — the interface
              doesn&apos;t reward you for showing up, it just shows up too.
            </p>
            <div className="hero-cta">
              <Link href="#pricing" className="btn btn-gold btn-lg">See plans</Link>
            </div>
          </Reveal>
          <Reveal delay={120}>
            <PhoneDemo />
          </Reveal>
        </div>
      </section>

      {/* ───────── Social proof (placeholder) ───────── */}
      <section className="section proof">
        <div className="container proof-grid">
          <Reveal>
            <span className="eyebrow">From the range</span>
            <p className="proof-quote" style={{ marginTop: 24 }}>
              &ldquo;It told me my 7-iron carries <span className="it">172</span>, not the
              185 I&apos;d been bragging about.&rdquo;
            </p>
            <div className="proof-attrib">Placeholder · early tester · 11.4 index</div>
          </Reveal>
          <Reveal delay={120}>
            <p className="lead" style={{ maxWidth: 360 }}>
              Real quotes go here once testing wraps. Until then, the numbers speak — and
              they round honestly.
            </p>
            <div className="proof-logos" aria-label="Press and partners placeholder">
              <span className="pl">As seen in ▢</span>
              <span className="pl">Partner ▢</span>
              <span className="pl">Club ▢</span>
            </div>
          </Reveal>
        </div>
      </section>

      {/* ───────── Pricing ───────── */}
      <PricingSection />

      {/* ───────── CTA ───────── */}
      <section className="cta-band">
        <div className="container">
          <Reveal>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 40, justifyContent: "space-between", alignItems: "flex-end" }}>
              <div style={{ maxWidth: 560 }}>
                <span className="eyebrow">Get started</span>
                <h2 style={{ fontSize: "clamp(34px,6vw,68px)", margin: "22px 0 0" }}>
                  Bear every yard.
                </h2>
              </div>
              <div style={{ display: "flex", gap: 14, flexWrap: "wrap" }}>
                <Link href="#pricing" className="btn btn-gold btn-lg">See plans</Link>
                <Link href="/login" className="btn btn-outline btn-lg">Create account</Link>
              </div>
            </div>
          </Reveal>
        </div>
      </section>

      <SiteFooter />
    </>
  );
}
