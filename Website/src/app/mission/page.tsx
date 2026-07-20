import type { Metadata } from "next";
import Image from "next/image";
import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";

export const metadata: Metadata = {
  title: "Our Mission: Every golfer deserves their numbers",
  description:
    "Real launch-monitor data has always been locked behind $500–$20,000 hardware. True Carry puts ball speed, launch, and carry in the iPhone you already own, so knowing your numbers isn't a luxury — even on your first bucket of balls.",
  alternates: { canonical: "/mission" },
  openGraph: {
    title: "Our Mission, True Carry",
    description:
      "Tour-grade ball data shouldn't cost thousands. We put the launch monitor in the phone you already own.",
    url: "/mission",
  },
};

// Headline numbers for the hero strip — a page about numbers should show some.
const STATS = [
  { v: "240fps", l: "the phone already shoots it" },
  { v: "$0", l: "to see your first numbers" },
  { v: "14", l: "clubs, one carry each" },
  { v: "3", l: "places: range, course, sim" },
];

// The price ladder — magnitude comparison, one gold hue for cost. The point is
// how little True Carry costs, so its bar is the empty one.
const LADDER = [
  { name: "Tour radar unit", note: "Trackman, on a tripod", price: "$20,000", pct: 100 },
  { name: "“Budget” monitor", note: "still hardware to buy", price: "$500–2,000", pct: 10 },
  { name: "True Carry", note: "the phone in your pocket", price: "Free to start", pct: 0, us: true },
];

const STEPS = [
  { n: "01", t: "Film", d: "Prop your iPhone down the line and hit. It captures the strike at 240 frames a second." },
  { n: "02", t: "Track", d: "True Carry follows the ball frame by frame and runs the same drag-and-lift flight model a radar uses." },
  { n: "03", t: "Know", d: "Ball speed, launch, and carry — in seconds, in plain numbers you can actually use." },
];

const BEGINNER = [
  { t: "No jargon to clear first", d: "You don't need to know what “spin axis” means to start. The readouts are plain: how fast, how high, how far." },
  { t: "Nothing to buy to find out", d: "Free to start on the phone you already own. The people who most need real numbers shouldn't have to gamble $500 to get them." },
  { t: "Learn your real gaps", d: "Stop guessing that you “hit 7-iron 150.” Find out what you actually carry each club, so you finally pick the right one." },
  { t: "Every swing says something", d: "At the range or the living room net, each shot gives you feedback — the same loop that makes good players good." },
];

const PILLARS = [
  {
    k: "Affordable",
    t: "No hardware to buy",
    d: "Trackman costs twenty grand. Even “budget” monitors run $500 to $2,000. True Carry runs on the iPhone already in your pocket — free to start, no sensors, no radar.",
  },
  {
    k: "Anywhere",
    t: "Range, course, or living room",
    d: "The same camera that reads your range session reads your shots on the course and feeds the browser simulator. One tool, every place you swing.",
  },
  {
    k: "For everyone",
    t: "Beginners most of all",
    d: "The players who most need to know their carry gaps are the ones who could never justify the gear — the weekend golfer, the range rat, the kid with a phone and a bucket of balls.",
  },
];

export default function MissionPage() {
  return (
    <div className="mission-page">
      <SiteNav />

      <header className="mission-hero" id="main-content">
        <p className="mission-kicker">Our mission</p>
        <h1>
          Every golfer deserves<br />
          <span className="it">to know their numbers.</span>
        </h1>
        <p className="mission-deck">
          Ball speed, launch angle, carry distance — the data that actually makes you
          better has spent decades locked behind hardware most golfers will never buy.
          We think that&apos;s backwards. So we put the launch monitor in the phone you
          already own.
        </p>
        <dl className="mission-stats" aria-label="True Carry by the numbers">
          {STATS.map((s) => (
            <div key={s.v}>
              <dt>{s.v}</dt>
              <dd>{s.l}</dd>
            </div>
          ))}
        </dl>
      </header>

      <main className="mission-main">
        {/* The problem — told as a price ladder */}
        <section className="mission-split" aria-labelledby="problem-h">
          <div className="mission-split-copy">
            <p className="mission-tag">The problem</p>
            <h2 id="problem-h">Golf&apos;s best data was gatekept by price.</h2>
            <p>
              For a generation, knowing your real numbers meant a radar unit on a tripod
              that cost more than most golfers spend on clubs in a decade. Tour pros had
              it. Fitters had it. Everyone else guessed — swinging harder, buying more
              clubs, never actually learning what their swing does.
            </p>
            <p>
              The information gap became a scoring gap. That advantage shouldn&apos;t
              belong to a price tag.
            </p>
          </div>
          <div className="price-ladder" role="img"
            aria-label="Cost of ball data: tour radar $20,000, budget monitors $500–2,000, True Carry free to start.">
            {LADDER.map((r) => (
              <div className={`ladder-row${r.us ? " us" : ""}`} key={r.name}>
                <div className="ladder-head">
                  <span className="ladder-name">{r.name}</span>
                  <span className="ladder-price">{r.price}</span>
                </div>
                <div className="ladder-track">
                  <span className="ladder-fill" style={{ width: `${Math.max(r.pct, r.us ? 0 : 3)}%` }} />
                </div>
                <span className="ladder-note">{r.note}</span>
              </div>
            ))}
          </div>
        </section>

        {/* The solution — three steps */}
        <section className="mission-block" aria-labelledby="solution-h">
          <p className="mission-tag">The solution</p>
          <h2 id="solution-h">Your iPhone is the launch monitor.</h2>
          <p>
            Modern phones shoot 240 frames a second. True Carry watches the ball leave
            the face, tracks it frame by frame, and runs the same aerodynamic flight
            model a radar unit uses — drag, lift, spin — for tour-grade ball speed,
            launch, and carry. No extra hardware, because the hardware is already in your
            hand.
          </p>
          <ol className="mission-steps">
            {STEPS.map((s) => (
              <li key={s.n}>
                <span className="step-n">{s.n}</span>
                <h3>{s.t}</h3>
                <p>{s.d}</p>
              </li>
            ))}
          </ol>
        </section>

        {/* NEW — beginners */}
        <section className="mission-beginner" aria-labelledby="beginner-h">
          <div className="beginner-media">
            <Image
              src="/mission/beginner-range.jpg"
              alt="A golfer practicing at a driving range at dusk, balls scattered across the turf"
              fill sizes="(max-width: 900px) 100vw, 520px"
              style={{ objectFit: "cover", objectPosition: "center 22%" }}
            />
          </div>
          <div className="beginner-copy">
            <p className="mission-tag">New to golf?</p>
            <h2 id="beginner-h">This was built for you first.</h2>
            <p className="beginner-lead">
              The player who gains the most from real numbers is the one just starting —
              and the least likely to ever buy a $20,000 radar to get them. True Carry
              hands a first-timer the same feedback loop a tour pro gets: hit a shot, see
              what actually happened, adjust. No coach, no launch bay, no jargon required.
            </p>
            <ul className="beginner-list">
              {BEGINNER.map((b) => (
                <li key={b.t}>
                  <h3>{b.t}</h3>
                  <p>{b.d}</p>
                </li>
              ))}
            </ul>
            <a className="beginner-cta" href="/#h07">Start free — no gear →</a>
          </div>
        </section>

        <section className="mission-pillars" aria-label="What accessibility means to us">
          {PILLARS.map((p) => (
            <div className="mission-pillar" key={p.k}>
              <span className="mission-pillar-k">{p.k}</span>
              <h3>{p.t}</h3>
              <p>{p.d}</p>
            </div>
          ))}
        </section>

        <section className="mission-vision" aria-labelledby="vision-h">
          <p className="mission-tag light">Where we&apos;re going</p>
          <h2 id="vision-h">A world where every golfer knows their game.</h2>
          <p>
            Imagine every player — not just the ones who could afford the gear — knowing
            their real carry with each club, watching a ball flight they can trust, and
            improving on their own terms. That&apos;s the game we&apos;re building toward:
            the data democratized, the guessing gone.
          </p>
          <div className="mission-ctas">
            <a className="solid" href="/#h07">Start free</a>
            <a className="ghost" href="/play">Play the sim</a>
          </div>
        </section>
      </main>

      <SiteFooter />
    </div>
  );
}
