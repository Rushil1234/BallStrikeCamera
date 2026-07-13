import type { Metadata } from "next";
import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";

export const metadata: Metadata = {
  title: "Our Mission: Every golfer deserves their numbers",
  description:
    "Real launch-monitor data has always been locked behind $500–$20,000 hardware. True Carry puts ball speed, launch, and carry in the iPhone you already own, so knowing your numbers isn't a luxury.",
  alternates: { canonical: "/mission" },
  openGraph: {
    title: "Our Mission, True Carry",
    description:
      "Tour-grade ball data shouldn't cost thousands. We put the launch monitor in the phone you already own.",
    url: "/mission",
  },
};

const PILLARS = [
  {
    k: "Affordable",
    t: "No hardware to buy",
    d: "Trackman costs twenty grand. Even 'budget' monitors run $500 to $2,000. True Carry runs on the iPhone already in your pocket, free to start, no sensors, no radar, no purchase to see your numbers.",
  },
  {
    k: "Anywhere",
    t: "Range, course, or living room",
    d: "The same camera that reads your range session reads your shots on the course and feeds the browser simulator. One tool, every place you swing, no launch bay required.",
  },
  {
    k: "For everyone",
    t: "Not just single-digit handicaps",
    d: "The players who most need to know their carry gaps are the ones who could never justify the gear. We built True Carry for them, the weekend golfer, the range rat, the kid with a phone and a bucket of balls.",
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
          Ball speed, launch angle, carry distance, the data that actually makes you
          better has spent decades locked behind hardware most golfers will never buy.
          We think that&apos;s backwards. So we put the launch monitor in the phone you
          already own.
        </p>
      </header>

      <main className="mission-main">
        <section className="mission-block" aria-labelledby="problem-h">
          <p className="mission-tag">The problem</p>
          <h2 id="problem-h">Golf&apos;s best data was gatekept by price.</h2>
          <p>
            For a generation, knowing your real numbers meant a radar unit on a tripod
            that cost more than most golfers spend on clubs in a decade. Tour pros had
            it. Fitters had it. Everyone else guessed, swinging harder, buying more
            clubs, and never actually learning what their swing does.
          </p>
          <p>
            The information gap became a scoring gap. Not because good golfers are
            special, but because they could see what was happening and adjust. That
            advantage shouldn&apos;t belong to a price tag.
          </p>
        </section>

        <section className="mission-block" aria-labelledby="solution-h">
          <p className="mission-tag">The solution</p>
          <h2 id="solution-h">Your iPhone is the launch monitor.</h2>
          <p>
            Modern phones shoot 240 frames a second. True Carry watches the ball leave
            the face, tracks it frame by frame, and runs the same aerodynamic flight
            model a radar unit uses, drag, lift, spin, to give you tour-grade ball
            speed, launch, and carry. No extra hardware, because the hardware is already
            in your hand.
          </p>
          <p>
            The physics don&apos;t care how much you paid. Real numbers, on the range,
            on the course, and in the simulator, for the price of an app.
          </p>
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
            Imagine every player, not just the ones who could afford the gear, knowing
            their real carry with each club, watching a ball flight they can trust, and
            improving on their own terms. That&apos;s the game we&apos;re building
            toward: the data democratized, the guessing gone.
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
