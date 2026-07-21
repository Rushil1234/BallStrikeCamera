"use client";

import { useEffect, useRef, useState } from "react";
import EmbeddedCheckoutPanel from "@/components/EmbeddedCheckoutPanel";
import PhoneDemo from "@/components/PhoneDemo";
import SimDemo from "@/components/SimDemo";
import ProductArt from "@/components/ProductArt";
import SiteNav from "@/components/SiteNav";
import { PLANS } from "@/lib/plans";
import { useSession } from "@/lib/useSession";
import { getUserEntitlement } from "@/lib/supabase";

type Hole = { n: number; name: string; par: number; yd: number; id: string };

const HOLES: Hole[] = [
  { n: 1, name: "Tee off", par: 4, yd: 372, id: "h01" },
  { n: 2, name: "What it does", par: 5, yd: 542, id: "h03" },
  { n: 3, name: "Play the sim", par: 5, yd: 527, id: "h05" },
  { n: 4, name: "One plan", par: 4, yd: 425, id: "h07" },
  { n: 5, name: "The pro shop", par: 3, yd: 188, id: "h06" },
  { n: 6, name: "When you're ready", par: 3, yd: 158, id: "h08" },
  { n: 7, name: "Clubhouse", par: 5, yd: 580, id: "h09" },
];

// Pro-shop teaser — the full hardware lineup, mirrored from /store. Imagery is
// the shared ProductArt (real photos for four, the render for foam balls).
type ShopItem = { id: string; name: string; price: string; tag: string; status: string };
const SHOP: ShopItem[] = [
  { id: "nfc-tag", name: "Club Tags", price: "$29", tag: "Tap a club, tag the shot", status: "Ships fall 2026" },
  { id: "foam-balls", name: "Foam Balls", price: "$19", tag: "Full swings, indoors", status: "Ships fall 2026" },
  { id: "tripod", name: "The Tripod", price: "$39", tag: "Holds the camera steady", status: "Ships fall 2026" },
  { id: "polo", name: "The Polo", price: "$65", tag: "Wear your numbers", status: "Ships fall 2026" },
  { id: "gift-card", name: "Gift Card", price: "$25+", tag: "Give every yard", status: "Available now" },
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
  // Billing toggle for the pricing section. Yearly (annual commitment) first.
  const [billing, setBilling] = useState<"yearly" | "monthly">("yearly");
  const totalRef = useRef<HTMLSpanElement | null>(null);
  const ballRef = useRef<HTMLDivElement | null>(null);
  const trailRef = useRef<HTMLDivElement | null>(null);

  // Track whether the signed-in visitor already has premium (paid or comped), so
  // we never send an existing subscriber into a checkout that the server would
  // refuse anyway.
  const { user } = useSession();
  const [alreadyPremium, setAlreadyPremium] = useState(false);
  useEffect(() => {
    let cancelled = false;
    if (!user) { setAlreadyPremium(false); return; }
    getUserEntitlement(user.id)
      .then((e: Record<string, unknown> | null) => {
        if (cancelled || !e) return;
        const comp = e.comp_pro_until ? new Date(e.comp_pro_until as string) > new Date() : false;
        const paid = e.tier !== "free" && ["active", "trialing"].includes(String(e.payment_status));
        setAlreadyPremium(Boolean(comp || paid));
      })
      .catch(() => { /* entitlement unknown -> fall through to normal checkout */ });
    return () => { cancelled = true; };
  }, [user]);

  // Opening the panel never navigates: the overlay handles auth + Stripe inline.
  function openCheckout(tier: string = "pro") {
    if (alreadyPremium) {
      // Already subscribed — take them to their account instead of charging again.
      window.location.href = "/account";
      return;
    }
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
      {/* Header, the shared site nav (session-aware), with the primary
          action opening the embedded checkout instead of a plain link. */}
      <SiteNav onGetApp={openCheckout} />

      {/* Ball trail */}
      <div className="ball-trail" ref={trailRef}>
        <div className="line" />
        <span className="tee">Tee</span>
        <div className="ball" ref={ballRef} />
        <span className="pin">Pin</span>
      </div>

      <div className="shell">
        <main>
          {/* H01, hero */}
          <section className="hole h01" id="h01">
            <video
              className="hero-video"
              autoPlay
              muted
              loop
              playsInline
              preload="auto"
              aria-hidden="true"
              poster="/hero-aerial-poster.jpg"
              onLoadedMetadata={(e) => { e.currentTarget.playbackRate = 0.72; }}
              onPlaying={(e) => e.currentTarget.classList.add("ready")}
            >
              <source src="/hero-aerial.mp4" type="video/mp4" />
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

          {/* H03, what it does + live demo */}
          <section className="hole h03" id="h03">
            <div className="wrap">
              <HoleStrip hole={HOLES[1]} />
              <div className="app-demo app-demo-solo">
                <div className="app-demo-phone">
                  <PhoneDemo />
                </div>
              </div>
            </div>
          </section>

          {/* H05, the sim */}
          <section className="hole h05" id="h05">
            <div className="wrap">
              <HoleStrip hole={HOLES[2]} />
              <div className="sim-feature sim-feature-solo">
                <SimDemo />
              </div>
            </div>
          </section>

          {/* H07, pricing — now the paper section, above the pro shop */}
          <span id="pricing" aria-hidden style={{ position: "absolute", marginTop: "-80px" }} />
          <section className="hole h07" id="h07">
            <div className="wrap">
              <HoleStrip hole={HOLES[3]} />
              <div className="plans-head">
                <h2>One round.<br /><span className="it">Three ways to play.</span></h2>
                <p>Start free. Step up when you want more of the numbers. <span className="it">Cancel anytime, keep your data.</span></p>
              </div>
              <div className="billing-toggle" role="tablist" aria-label="Billing interval">
                <button
                  role="tab"
                  aria-selected={billing === "yearly"}
                  className={`billing-opt${billing === "yearly" ? " on" : ""}`}
                  onClick={() => setBilling("yearly")}
                >
                  Yearly<span className="billing-save">4 months free</span>
                </button>
                <button
                  role="tab"
                  aria-selected={billing === "monthly"}
                  className={`billing-opt${billing === "monthly" ? " on" : ""}`}
                  onClick={() => setBilling("monthly")}
                >
                  Monthly
                </button>
                <span className={`billing-slide ${billing}`} aria-hidden />
              </div>
              <div className="plans">
                {PLANS.map((plan) => (
                  <div className={`plan${plan.featured ? " featured" : ""}`} key={plan.id}>
                    {plan.featured && <span className="plan-flag">Most played</span>}
                    <div className="plan-name">{plan.name}</div>
                    <div className="plan-price">
                      {plan.flat ? plan.monthly : plan[billing]}
                      <span className="per">{plan.per}</span>
                    </div>
                    <p className="plan-sub">
                      {plan.flat ? " " : billing === "yearly" ? "billed yearly" : "billed monthly"}
                    </p>
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

          {/* H06, the pro shop — the full hardware lineup, on the forest section */}
          <section className="hole h06" id="h06">
            <div className="wrap">
              <HoleStrip hole={HOLES[4]} />
              <div className="shop-feature">
                <div className="shop-head">
                  <div className="shop-head-copy">
                    <h2>Free on your phone.<br /><span className="it">A shop for the rest.</span></h2>
                    <p className="shop-deck">
                      The app is free and needs nothing but your iPhone. A few small things make it
                      sharper: tags that log every swing, balls you can hit indoors, and a tripod
                      that holds the shot.
                    </p>
                  </div>
                  <a className="shop-visit" href="/store">Visit the store <span aria-hidden>→</span></a>
                </div>

                {/* Bounce-card fan — overlapping product cards that spread on hover,
                    each showing its price as a gold chip instead of plain text. */}
                <div className="shop-fan">
                  {SHOP.map((p, i) => {
                    const live = p.status === "Available now";
                    return (
                      <a
                        className="fan-card"
                        key={p.id}
                        href="/store"
                        style={{ "--i": i, "--n": SHOP.length } as React.CSSProperties}
                        aria-label={`${p.name}. ${p.tag}. ${p.status}.`}
                      >
                        <span className="fan-art"><ProductArt kind={p.id} /></span>
                        <span className="fan-shade" aria-hidden />
                        <span className="fan-info">
                          <span className="fan-name">{p.name}</span>
                          <span className="fan-tag">{p.tag}</span>
                          <span className={`fan-status${live ? " live" : ""}`}>{p.status}</span>
                        </span>
                      </a>
                    );
                  })}
                </div>
              </div>
            </div>
          </section>

          {/* H08, closing */}
          <section className="hole h08" id="h08">
            <div className="atlas-bg"><img src="/truecarry-logo.png" alt="" /></div>
            <div className="wrap">
              <HoleStrip hole={HOLES[5]} />
              <p className="copy">When you&apos;re ready,<br />we&apos;ll be in the <span className="gold">bag.</span></p>
              <a href="#h07" className="link" onClick={(e) => { e.preventDefault(); openCheckout(); }}>Get Premium &nbsp;→</a>
            </div>
          </section>

          {/* H09, footer */}
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
                  <a href="/mission">Our mission</a>
                  <a href="/play">Play the sim</a>
                  <a href="/store">Store</a>
                  <a href="#h07">Pricing</a>
                </div>
                <div className="col">
                  <h4>Setup</h4>
                  <a href="/bridge">Connect to GSPro / OGS</a>
                  <a href="/connect">Check connection</a>
                  <a href="/support">Support</a>
                </div>
                <div className="col">
                  <h4>Account</h4>
                  <a href="/login">Sign in</a>
                  <a href="/account">Your account</a>
                  <a href="#h07">Manage plan</a>
                </div>
                <div className="col">
                  <h4>Legal</h4>
                  <a href="/privacy">Privacy</a>
                  <a href="/terms">Terms</a>
                </div>
              </div>
              <div className="bottom">
                <span>© {new Date().getFullYear()} True Carry</span>
                <span>Subscriptions securely managed by Stripe.</span>
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
            <span className="who">You</span>
            <span className="stamp">live</span>
          </div>
        </aside>
      </div>

      {checkoutOpen && <EmbeddedCheckoutPanel tier={checkoutTier} billingInterval={billing} onClose={() => setCheckoutOpen(false)} />}
    </div>
  );
}
