"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabase";
import EmbeddedCheckoutPanel from "@/components/EmbeddedCheckoutPanel";

const CHECKOUT_URL = process.env.NEXT_PUBLIC_CREATE_CHECKOUT_FUNCTION_URL!;
const CHECKOUT_RETURN_PATH = "/?checkout=premium#h07";

type Hole = { n: number; name: string; par: number; yd: number; id: string };

const HOLES: Hole[] = [
  { n: 1, name: "Tee off", par: 4, yd: 372, id: "h01" },
  { n: 3, name: "Three readings", par: 5, yd: 542, id: "h03" },
  { n: 4, name: "At last light", par: 4, yd: 411, id: "h04" },
  { n: 6, name: "Wednesday at the Presidio", par: 3, yd: 192, id: "h06" },
  { n: 7, name: "One plan", par: 4, yd: 425, id: "h07" },
  { n: 8, name: "When you're ready", par: 3, yd: 158, id: "h08" },
  { n: 9, name: "Clubhouse", par: 5, yd: 580, id: "h09" },
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
  const router = useRouter();
  const [checkoutToken, setCheckoutToken] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const totalRef = useRef<HTMLSpanElement | null>(null);
  const ballRef = useRef<HTMLDivElement | null>(null);
  const trailRef = useRef<HTMLDivElement | null>(null);

  async function startCheckout() {
    if (loading) return;
    setLoading(true);
    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) {
        router.push(`/login?redirect=${encodeURIComponent(CHECKOUT_RETURN_PATH)}`);
        return;
      }
      setCheckoutToken(session.access_token);
      if (window.location.search.includes("checkout=premium")) {
        window.history.replaceState(null, "", "/#h07");
      }
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    if (params.get("checkout") === "premium") {
      document.getElementById("h07")?.scrollIntoView({ block: "start" });
      void startCheckout();
    }
    // Run only once on entry so checkout intent opens after login.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Scroll: mark holes played, highlight current, tally carry, move the ball.
  useEffect(() => {
    const shouldReduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const isCompact = window.matchMedia("(max-width: 760px)").matches;
    if (shouldReduceMotion || isCompact) return;

    const sections = Array.from(document.querySelectorAll<HTMLElement>(".round .hole"));
    const rows = Array.from(document.querySelectorAll<HTMLElement>("#scHoles .row"));
    const played = new Set<number>();
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
      let currentIdx = 0;
      sections.forEach((sec, i) => {
        if (sec.getBoundingClientRect().top < trigger) {
          if (!played.has(i)) {
            played.add(i);
            total += HOLES[i]?.yd ?? 0;
            animateTotal(total);
          }
          currentIdx = i;
        }
      });
      rows.forEach((r, i) => {
        r.classList.toggle("played", played.has(i));
        r.classList.toggle("current", i === currentIdx);
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

  const tickerItems = (
    <>
      <span className="dot">◆</span> <span>Last shot · Maren · 7-iron · <span className="v">172.4 yd</span></span>
      <span className="dot">◆</span> <span>Wind · SW 8 mph</span>
      <span className="dot">◆</span> <span>Presidio · 62°F · Dry</span>
      <span className="dot">◆</span> <span>Now on the tee · <span className="v">You.</span></span>
      <span className="dot">◆</span> <span>Bear every yard.</span>
    </>
  );

  return (
    <div className="round">
      {/* Ticker */}
      <div className="ticker">
        <div className="track">{tickerItems}{tickerItems}</div>
      </div>

      {/* Header */}
      <header className="head">
        <div className="row">
          <a className="brand" href="#h01">
            <img src="/truecarry-logo.png" alt="" />
            <span className="n">True <span className="it">Carry.</span></span>
          </a>
          <nav className="nav">
            <a className="l" href="#h03">Readings</a>
            <a className="l" href="#h06">Rounds</a>
            <a className="l" href="#h07">Pricing</a>
            <a className="l btn" href="/login">Sign in</a>
            <a className="l btn primary" href="#h07" onClick={(e) => { e.preventDefault(); startCheckout(); }}>
              {loading ? "…" : "Get the app"}
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
            <img className="atlas" src="/truecarry-logo.png" alt="" />
            <div className="wrap">
              <HoleStrip hole={HOLES[0]} />
              <h1>Bear<br />every <span className="yard">yard.</span></h1>
              <div className="tee-off">
                <div className="links">
                  <a className="solid" href="#h07" onClick={(e) => { e.preventDefault(); startCheckout(); }}>Get the app</a>
                  <a className="ghost" href="#h03">See what it reads</a>
                </div>
                <div className="note">Now on the tee<br /><span className="v">You.</span></div>
              </div>
            </div>
          </section>

          <section className="mobile-round-card" aria-label="Mobile round summary">
            <div className="mobile-round-head">
              <span>Your round</span>
              <strong>{HOLES[0].yd} yd</strong>
            </div>
            <div className="mobile-round-list">
              {HOLES.slice(0, 5).map((hole) => (
                <a href={`#${hole.id}`} key={hole.id}>
                  <span>{String(hole.n).padStart(2, "0")}</span>
                  <b>{hole.name}</b>
                  <em>{hole.yd} yd</em>
                </a>
              ))}
            </div>
          </section>

          {/* H03 — readings */}
          <section className="hole h03" id="h03">
            <div className="wrap">
              <HoleStrip hole={HOLES[1]} />
              <p className="deck">At 240 frames a second, your phone sees enough to read the strike, the window, and the carry.</p>
              <div className="readings">
                <div className="reading">
                  <div className="label">Ball speed<span className="num">A · 01</span></div>
                  <div className="v">128<span className="u">mph</span></div>
                  <div className="gloss"><p>Read off the strike — not estimated from the club.</p><div className="src">±1.4 mph vs. radar baseline</div></div>
                </div>
                <div className="reading">
                  <div className="label">Launch<span className="num">A · 02</span></div>
                  <div className="v">17.6<span className="u">deg</span></div>
                  <div className="gloss"><p>The window the ball leaves on, degree by degree.</p><div className="src">±0.4° vs. radar baseline</div></div>
                </div>
                <div className="reading gold">
                  <div className="label">True carry<span className="num">A · 03 · headline</span></div>
                  <div className="v">172<span className="u">yd</span></div>
                  <div className="gloss"><p>The yards the ball actually flies through air. Before bounce, before roll, before the story.</p><div className="src">±2.1 yd vs. TrackMan baseline · 14,210 shots</div></div>
                </div>
              </div>
            </div>
          </section>

          {/* H04 — scene */}
          <section className="hole h04" id="h04">
            <div className="wrap strip-wrap"><HoleStrip hole={HOLES[2]} /></div>
            <div className="scene">
              <div className="ground" />
              <div className="horizon" />
              <div className="arc">
                <svg viewBox="0 0 1440 720" preserveAspectRatio="none"><path d="M 180 580 Q 720 60, 1080 520" /></svg>
              </div>
              <div className="ball-dot" />
              <div className="pin" />
              <div className="cap">
                Presidio · Hole 4 <span className="dot" /> Last light <span className="dot" /> 6:42 PM
                <div className="meta">Wind 8 mph SW · Temp 62°F · No add-on hardware</div>
              </div>
              <div className="stamp">Carry recorded<span className="v">287.4 yd</span></div>
            </div>
          </section>

          {/* H06 — round card (paper) */}
          <section className="hole h06" id="h06">
            <div className="wrap">
              <HoleStrip hole={HOLES[3]} />
              <div className="top">
                <h2>Wednesday<br />at the <span className="it">Presidio.</span></h2>
                <p>Every round becomes an object you can return to. Carry per hole, club per shot, where the misses cluster. This is Maren&apos;s back nine from last week — birdie on 15 with a 168-yard 8-iron.</p>
              </div>
              <div className="card">
                <div className="sc-head">
                  <div>
                    <div className="title">True <span className="it">Carry.</span></div>
                    <div className="sub">Round · Presidio · Back 9</div>
                  </div>
                  <div className="right">05·14·26<br />Maren · idx +2.4<br />Tee · Blue</div>
                </div>
                <table>
                  <thead><tr><th>Hole</th><th>10</th><th>11</th><th>12</th><th>13</th><th>14</th><th>15</th><th>16</th><th>17</th><th>18</th></tr></thead>
                  <tbody>
                    <tr><td className="lbl">Par</td><td>4</td><td>5</td><td>3</td><td>4</td><td>4</td><td>3</td><td>5</td><td>4</td><td>4</td></tr>
                    <tr><td className="lbl">Score</td><td>4</td><td>6</td><td>3</td><td>5</td><td>4</td><td className="gold">2</td><td>5</td><td>4</td><td>5</td></tr>
                    <tr><td className="lbl">Carry · yd</td><td>248</td><td>262</td><td>168</td><td>241</td><td>233</td><td>177</td><td>270</td><td>239</td><td>251</td></tr>
                    <tr><td className="lbl">Club</td><td>D</td><td>D</td><td>7i</td><td>D</td><td>3w</td><td>8i</td><td>D</td><td>D</td><td>D</td></tr>
                    <tr className="totals"><td className="lbl">Net</td><td colSpan={9}>38</td></tr>
                  </tbody>
                </table>
                <div className="sc-foot"><span>Wind 8 mph SW · 62°F</span><span className="net">+2<span className="it">.</span></span></div>
              </div>
            </div>
          </section>

          {/* H07 — pricing */}
          <section className="hole h07" id="h07">
            <div className="wrap">
              <HoleStrip hole={HOLES[4]} />
              <h2 className="price"><span className="dollar">$</span>10<span className="per">per<br />month</span></h2>
              <p className="summary">Everything True Carry does, in one plan. <span className="it">Cancel anytime, keep your data.</span></p>
              <ul className="features">
                <li><span className="what">Ball, launch &amp; carry on <span className="it">every</span> shot</span><span className="ok">Included</span></li>
                <li><span className="what">Range, simulator &amp; course modes</span><span className="ok">Included</span></li>
                <li><span className="what">A full season of <span className="it">shot history</span></span><span className="ok">Included</span></li>
                <li><span className="what">Cloud sync &amp; export</span><span className="ok">Included</span></li>
                <li><span className="what">Apple Watch companion</span><span className="ok">Included</span></li>
                <li><span className="what">Monthly model refresh</span><span className="ok">Included</span></li>
              </ul>
              <div className="cta">
                <a className="solid" href="#h07" onClick={(e) => { e.preventDefault(); startCheckout(); }}>{loading ? "Preparing…" : "Get Premium"}</a>
                <a className="ghost" href="#h03">See what it reads</a>
              </div>
            </div>
          </section>

          {/* H08 — closing */}
          <section className="hole h08" id="h08">
            <div className="atlas-bg"><img src="/truecarry-logo.png" alt="" /></div>
            <div className="wrap">
              <HoleStrip hole={HOLES[5]} />
              <p className="copy">When you&apos;re ready,<br />we&apos;ll be in the <span className="gold">bag.</span></p>
              <a href="#h07" className="link" onClick={(e) => { e.preventDefault(); startCheckout(); }}>Start the trial &nbsp;→</a>
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
                  <a href="#h03">What it reads</a>
                  <a href="#h06">Round view</a>
                  <a href="#h07">Pricing</a>
                </div>
                <div className="col">
                  <h4>Account</h4>
                  <a href="/login">Sign in</a>
                  <a href="/account">Your account</a>
                  <a href="#h07" onClick={(e) => { e.preventDefault(); startCheckout(); }}>Get the app</a>
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
                <span>Set in Instrument Serif &amp; Manrope</span>
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
              <div className="row" key={h.id} onClick={() => document.getElementById(h.id)?.scrollIntoView({ behavior: "smooth", block: "start" })} style={{ cursor: "pointer" }}>
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

      {checkoutToken && (
        <EmbeddedCheckoutPanel
          accessToken={checkoutToken}
          checkoutUrl={CHECKOUT_URL}
          onClose={() => setCheckoutToken(null)}
        />
      )}
    </div>
  );
}
