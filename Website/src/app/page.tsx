"use client";

import { useEffect, useRef, useState } from "react";
import EmbeddedCheckoutPanel from "@/components/EmbeddedCheckoutPanel";
import PhoneDemo from "@/components/PhoneDemo";
import ClubCards from "@/components/ClubCards";

type Hole = { n: number; name: string; par: number; yd: number; id: string };

const HOLES: Hole[] = [
  { n: 1, name: "Tee off", par: 4, yd: 372, id: "h01" },
  { n: 2, name: "What it does", par: 5, yd: 542, id: "h03" },
  { n: 3, name: "Play the sim", par: 5, yd: 527, id: "h05" },
  { n: 4, name: "Club cards", par: 3, yd: 188, id: "h06" },
  { n: 5, name: "One plan", par: 4, yd: 425, id: "h07" },
  { n: 6, name: "When you're ready", par: 3, yd: 158, id: "h08" },
  { n: 7, name: "Clubhouse", par: 5, yd: 580, id: "h09" },
];

type Plan = { id: string; name: string; price: string; per: string; tag: string; features: string[]; featured?: boolean; href?: string; cta?: string };

const PLANS: Plan[] = [
  { id: "free", name: "Free", price: "$0", per: "forever", tag: "Get a feel for it.", cta: "Get the app", href: "/login",
    features: ["Range mode", "10 shots a day", "Ball speed & carry", "On-device storage"] },
  { id: "basic", name: "Basic", price: "$5", per: "/ month", tag: "For the regular range-goer.",
    features: ["All modes — range, sim, course", "Unlimited shots", "100 cloud-saved shots", "Basic analytics", "Cloud sync"] },
  { id: "pro", name: "Pro", price: "$10", per: "/ month", tag: "For the player chasing gains.", featured: true,
    features: ["Everything in Basic", "1,000 cloud shots", "Advanced analytics", "In-round suggestions", "Video export"] },
  { id: "atlas", name: "Atlas", price: "$25", per: "/ month", tag: "The whole bag.",
    features: ["Everything in Pro", "Unlimited cloud shots", "Full media storage", "Apple Watch companion", "Priority support"] },
];

function HoleStrip({ hole }: { hole: Hole }) {
  return (
    <div className="hole-strip">
      <span className="n">N°&nbsp;{String(hole.n).padStart(2, "0")}<span className="gold">.</span></span>
      <span className="name">{hole.name}</span>
      <span className="par">Par <span className="v">{hole.par}</span></span>
      <span className="yd">Yd <span className="v">{hole.yd}</span></span>
    </div>
  );
}

export default function HomePage() {
  const [checkoutOpen, setCheckoutOpen] = useState(false);
  const [checkoutTier, setCheckoutTier] = useState("pro");
  const totalRef = useRef<HTMLSpanElement | null>(null);
  const ballRef = useRef<HTMLDivElement | null>(null);
  const trailRef = useRef<HTMLDivElement | null>(null);

  // Opening the panel never navigates — the overlay handles auth + Stripe inline.
  function openCheckout(tier: string = "pro") {
    setCheckoutTier(tier);
    setCheckoutOpen(true);
  }

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    if (params.get("checkout") === "premium") {
      document.getElementById("h07")?.scrollIntoView({ block: "start" });
      setCheckoutOpen(true);
      window.history.replaceState(null, "", "/#h07");
    }
  }, []);

  // Scroll: mark holes played, highlight current, tally carry, move the ball.
  useEffect(() => {
    const shouldReduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const isCompact = window.matchMedia("(max-width: 760px)").matches;
    if (shouldReduceMotion || isCompact) return;

    const sections = Array.from(document.querySelectorAll<HTMLElement>(".round .hole"));
    const rows = Array.from(document.querySelectorAll<HTMLElement>("#scHoles .row"));
    const played = new Set<string>();
    let total = 0;
    let raf = 0;

    function animateTotal(target: number) {
      cancelAnimationFrame(raf);
      const el = totalRef.current;
      if (!el) return;
      const start = parseInt((el.textContent || "0").replace(/[^\d]/g, ""), 10) || 0;
      const t0 = performance.now();
      const tick = (now: number) => {
        const t = Math.min(1, (now - t0) / 700);
        const e = 1 - Math.pow(1 - t, 3);
        el.textContent = Math.round(start + (target - start) * e).toLocaleString();
        if (t < 1) raf = requestAnimationFrame(tick);
      };
      raf = requestAnimationFrame(tick);
    }

    function update() {
      const trigger = window.innerHeight * 0.55;
      let currentId = sections[0]?.id ?? "";
      sections.forEach((sec) => {
        const hole = HOLES.find((item) => item.id === sec.id);
        if (!hole) return;
        if (sec.getBoundingClientRect().top < trigger) {
          if (!played.has(hole.id)) {
            played.add(hole.id);
            total += hole.yd;
            animateTotal(total);
          }
          currentId = hole.id;
        }
      });
      rows.forEach((r) => {
        const rowId = r.dataset.holeId ?? "";
        r.classList.toggle("played", played.has(rowId));
        r.classList.toggle("current", rowId === currentId);
      });
      const trail = trailRef.current, ball = ballRef.current;
      if (trail && ball) {
        const docH = document.documentElement.scrollHeight - window.innerHeight;
        const scrolled = Math.max(0, Math.min(1, window.scrollY / Math.max(1, docH)));
        ball.style.top = trail.offsetHeight * scrolled + "px";
      }
    }

    update();
    window.addEventListener("scroll", update, { passive: true });
    window.addEventListener("resize", update);
    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("scroll", update);
      window.removeEventListener("resize", update);
    };
  }, []);

  return (
    <div className="round">
      {/* Header */}
      <header className="head">
        <div className="row">
          <a className="brand" href="#h01">
            <img src="/truecarry-header-logo.png" alt="" />
            <span className="n">True <span className="it">Carry.</span></span>
          </a>
          <nav className="nav">
            <a className="l" href="#h03">What it does</a>
            <a className="l" href="/play">The Sim</a>
            <a className="l" href="/bridge">Connect sim</a>
            <a className="l" href="/store">Store</a>
            <a className="l" href="#h07">Pricing</a>
            <a className="l btn" href="/login">Sign in</a>
            <a className="l btn primary" href="#h07" onClick={(e) => { e.preventDefault(); openCheckout(); }}>
              Get the app
            </a>
          </nav>
        </div>
      </header>

      {/* Ball trail */}
      <div className="ball-trail" ref={trailRef}>
        <div className="line" />
        <span className="tee">Tee</span>
        <div className="ball" ref={ballRef} />
        <span className="pin">Pin</span>
      </div>

      <div className="shell">
        <main>
          {/* H01 — hero */}
          <section className="hole h01" id="h01">
            <video
              className="hero-video"
              autoPlay
              muted
              loop
              playsInline
              preload="auto"
              aria-hidden="true"
              onLoadedMetadata={(e) => { e.currentTarget.playbackRate = 0.82; }}
              onPlaying={(e) => e.currentTarget.classList.add("ready")}
            >
              <source src="/hero-golf-course.mp4" type="video/mp4" />
            </video>
            <div className="hero-shade" aria-hidden="true" />
            <div className="wrap">
              <HoleStrip hole={HOLES[0]} />
              <h1>Turn your<br />iPhone into a<br /><span className="yard">launch monitor.</span></h1>
              <p className="hero-copy">Measure ball speed, launch angle, and carry distance from the phone in your pocket.</p>
              <div className="tee-off">
                <div className="links">
                  <a className="solid" href="#h07" onClick={(e) => { e.preventDefault(); openCheckout(); }}>Get the app</a>
                  <a className="ghost" href="#h03">See what it does</a>
                </div>
              </div>
            </div>
          </section>

          <section className="mobile-round-card" aria-label="Mobile round summary">
            <div className="mobile-round-head">
              <span>Your round</span>
              <strong>{HOLES[0].yd} yd</strong>
            </div>
            <div className="mobile-round-list">
              {HOLES.map((hole) => (
                <a href={`#${hole.id}`} key={hole.id}>
                  <span>{String(hole.n).padStart(2, "0")}</span>
                  <b>{hole.name}</b>
                  <em>{hole.yd} yd</em>
                </a>
              ))}
            </div>
          </section>

          {/* H03 — what it does + live demo */}
          <section className="hole h03" id="h03">
            <div className="wrap">
              <HoleStrip hole={HOLES[1]} />
              <div className="app-demo">
                <div className="app-demo-copy">
                  <h2>See what it<br /><span className="it">does.</span></h2>
                  <p className="deck">Set your phone down, hit a shot, and True Carry reads the strike at 240 frames a second — ball speed, launch, and the carry the ball actually flies. No add-on hardware.</p>
                  <ul className="app-stats">
                    <li><span>Ball speed</span><b>±1.4 mph</b><em>vs. radar baseline</em></li>
                    <li><span>Launch</span><b>±0.4°</b><em>vs. radar baseline</em></li>
                    <li><span>True carry</span><b>±2.1 yd</b><em>vs. TrackMan · 14,210 shots</em></li>
                  </ul>
                  <p className="app-demo-hint">Pick a club and take a swing →</p>
                </div>
                <div className="app-demo-phone">
                  <PhoneDemo />
                </div>
              </div>
            </div>
          </section>

          {/* H05 — the sim */}
          <section className="hole h05" id="h05">
            <div className="wrap">
              <HoleStrip hole={HOLES[2]} />
              <div className="sim-feature">
                <div className="sim-copy">
                  <h2>Play a round.<br /><span className="it">Right here.</span></h2>
                  <p className="deck">Eighteen holes at Pine Hollow National, in your browser. The same flight model that reads your real shots drives every drive, chip, and putt.</p>
                  <ul className="sim-points">
                    <li><span>The course</span><b>18 holes · par 72 · 6,900 yd</b></li>
                    <li><span>The physics</span><b>True flight — drag, lift, spin</b></li>
                    <li><span>The numbers</span><b>Launch-monitor data, every swing</b></li>
                  </ul>
                  <div className="sim-ctas">
                    <a className="solid" href="/play">Tee off in the sim</a>
                    <a className="ghost" href="/sim/index.html?mode=course&course=pine-hollow" target="_blank" rel="noreferrer">Open full screen</a>
                  </div>
                </div>
                <a className="sim-shot" href="/play" aria-label="Play the True Carry Sim">
                  <img src="/sim-preview.jpg" alt="Pine Hollow National, hole 1 — the True Carry Sim" loading="lazy" />
                  <span className="sim-play">Tee off →</span>
                </a>
              </div>
            </div>
          </section>

          {/* H06 — NFC club cards */}
          <section className="hole h06" id="h06">
            <div className="wrap">
              <HoleStrip hole={HOLES[3]} />
              <div className="cards-feature">
                <div className="cards-copy">
                  <h2>Tap in.<br /><span className="it">Every club, tagged.</span></h2>
                  <p className="cards-deck">A slim NFC card lives on every club in your bag. Tap your phone on the way to address, and True Carry tags the shot — club, carry, and gapping build themselves, swing after swing.</p>
                  <ul className="cards-points">
                    <li><b>No batteries, no pairing</b><span>Passive NFC — tap and swing.</span></li>
                    <li><b>Gapping that fills itself</b><span>Real carries per club, not range guesses.</span></li>
                    <li><b>Fits any grip</b><span>Under-grip sticker or bag-tag card.</span></li>
                  </ul>
                  <div className="cards-ctas">
                    <a className="solid" href="/store">Visit the store</a>
                    <a className="ghost" href="#h03">See the app first</a>
                  </div>
                </div>
                <ClubCards />
              </div>
            </div>
          </section>

          {/* H07 — pricing (four tiers) */}
          <span id="pricing" aria-hidden style={{ position: "absolute", marginTop: "-80px" }} />
          <section className="hole h07" id="h07">
            <div className="wrap">
              <HoleStrip hole={HOLES[4]} />
              <div className="plans-head">
                <h2>One round.<br /><span className="it">Four ways to play.</span></h2>
                <p>Start free. Step up when you want more of the numbers. <span className="it">Cancel anytime, keep your data.</span></p>
              </div>
              <div className="plans">
                {PLANS.map((plan) => (
                  <div className={`plan${plan.featured ? " featured" : ""}`} key={plan.id}>
                    {plan.featured && <span className="plan-flag">Most played</span>}
                    <div className="plan-name">{plan.name}</div>
                    <div className="plan-price">{plan.price}<span className="per">{plan.per}</span></div>
                    <p className="plan-tag">{plan.tag}</p>
                    <ul>
                      {plan.features.map((f) => <li key={f}>{f}</li>)}
                    </ul>
                    {plan.href ? (
                      <a className="plan-cta" href={plan.href}>{plan.cta ?? `Choose ${plan.name}`}</a>
                    ) : (
                      <a className="plan-cta" href="#h07" onClick={(e) => { e.preventDefault(); openCheckout(plan.id); }}>Get {plan.name}</a>
                    )}
                  </div>
                ))}
              </div>
            </div>
          </section>

          {/* H08 — closing */}
          <section className="hole h08" id="h08">
            <div className="atlas-bg"><img src="/truecarry-logo.png" alt="" /></div>
            <div className="wrap">
              <HoleStrip hole={HOLES[5]} />
              <p className="copy">When you&apos;re ready,<br />we&apos;ll be in the <span className="gold">bag.</span></p>
              <a href="#h07" className="link" onClick={(e) => { e.preventDefault(); openCheckout(); }}>Get Premium &nbsp;→</a>
            </div>
          </section>

          {/* H09 — footer */}
          <footer className="hole h09" id="h09">
            <div className="wrap">
              <div className="grid">
                <div className="col">
                  <div className="wm">True <span className="it">Carry.</span></div>
                  <p>Tour-grade ball data from the iPhone in your pocket. Built for golfers who want to know every yard.</p>
                  <div className="meta">Pacifica · CA · Est. 2026</div>
                </div>
                <div className="col">
                  <h4>Product</h4>
                  <a href="#h03">What it does</a>
                  <a href="/play">Play the sim</a>
                  <a href="/bridge">Connect to GSPro / OGS</a>
                  <a href="/connect">Check connection</a>
                  <a href="/store">Store</a>
                  <a href="#h07">Pricing</a>
                  <a href="#h07" onClick={(e) => { e.preventDefault(); openCheckout(); }}>Get the app</a>
                </div>
                <div className="col">
                  <h4>Account</h4>
                  <a href="/login">Sign in</a>
                  <a href="/account">Your account</a>
                </div>
                <div className="col">
                  <h4>Legal</h4>
                  <a href="/privacy">Privacy</a>
                  <a href="/terms">Terms</a>
                </div>
              </div>
              <div className="bottom">
                <span>© 2026 True Carry</span>
                <span>Made in Pacifica · Bear every yard.</span>
              </div>
            </div>
          </footer>
        </main>

        {/* Scorecard rail */}
        <aside className="scorecard" id="scorecard" aria-label="Round scorecard">
          <div className="sc-head">
            <div className="t">Your <span className="it">round.</span></div>
            <div className="date">In progress<br />5.21.26 · Web</div>
          </div>
          <div className="holes" id="scHoles">
            <span className="col-h">H</span>
            <span className="col-h">Hole name</span>
            <span className="col-h r">Par</span>
            <span className="col-h r">Yd</span>
            {HOLES.map((h) => (
              <div className="row" key={h.id} data-hole-id={h.id} onClick={() => document.getElementById(h.id)?.scrollIntoView({ behavior: "smooth", block: "start" })} style={{ cursor: "pointer" }}>
                <span className="h">{String(h.n).padStart(2, "0")}</span>
                <span className="name">{h.name}</span>
                <span className="par">P{h.par}</span>
                <span className="yd">{h.yd}</span>
              </div>
            ))}
          </div>
          <div className="total">
            <div><div className="k">Carry · total</div></div>
            <div style={{ textAlign: "right" }}>
              <div className="v"><span ref={totalRef} id="scTotal">0</span><span className="it">.</span></div>
              <div className="u">yards</div>
            </div>
          </div>
          <div className="player">
            <span className="who">— You</span>
            <span className="stamp">live</span>
          </div>
        </aside>
      </div>

      {checkoutOpen && <EmbeddedCheckoutPanel tier={checkoutTier} onClose={() => setCheckoutOpen(false)} />}
    </div>
  );
}
