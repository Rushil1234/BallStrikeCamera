import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";

export const metadata = { title: "Privacy Policy" };

const UPDATED = "July 3, 2026";

export default function PrivacyPage() {
  return (
    <>
      <SiteNav />
      <main className="narrow" style={{ paddingTop: 70, paddingBottom: 90 }}>
        <span className="eyebrow">Legal</span>
        <h1 style={{ fontSize: "clamp(32px,5vw,46px)", margin: "14px 0 10px" }}>Privacy Policy</h1>
        <p style={{ opacity: 0.6, marginBottom: 28 }}>Last updated {UPDATED}</p>
        <div className="prose">
          <h2>What we collect</h2>
          <p>
            <strong>Account data.</strong> Your email address and, if you use Google or Apple
            sign-in, the basic profile those providers share (name, email). Managed by our
            authentication provider, Supabase.
          </p>
          <p>
            <strong>Golf data you create.</strong> Shot metrics (ball speed, launch angles,
            spin, carry), practice sessions, simulator sessions, course rounds, your club bag,
            and profile details you enter. Free-tier shot data stays on your device; cloud sync
            applies to paid tiers or where you enable it.
          </p>
          <p>
            <strong>Camera frames.</strong> The camera captures used to measure your shots are
            processed on your iPhone. Replay frame bursts are stored on your device. A single
            composite image per shot may sync to your account so replays work across devices , 
            it is visible only to you and, if you share a shot, to the people you share it with.
          </p>
          <p>
            <strong>Billing.</strong> Payments are processed by Stripe. We never see or store
            your card number; we store your subscription tier and status.
          </p>
          <p>
            <strong>Location.</strong> Course mode uses your location on-device to map your
            round. Location is not tracked outside an active round.
          </p>
          <h2>What we do not do</h2>
          <p>
            We do not sell your data, run third-party advertising, or use your camera captures
            for anything other than measuring your shots and building your replays.
          </p>
          <h2>Where data lives</h2>
          <p>
            Cloud data is stored with Supabase (Postgres, row-level security scoped to your
            account). Media uploads live in Supabase Storage. Referral rewards are tracked by
            invite code. You can request deletion of your account and all associated data at
            any time via <a href="mailto:rushil@truecarrygolf.com">rushil@truecarrygolf.com</a>.
          </p>
          <h2>Sharing</h2>
          <p>
            Shots you explicitly share (feed posts, shot cards, live sim sessions) are visible
            to the audience you choose. Live sim pairing codes are short-lived and scoped to a
            single session.
          </p>
          <h2>Contact</h2>
          <p>
            Questions about this policy: <a href="mailto:rushil@truecarrygolf.com">rushil@truecarrygolf.com</a>.
          </p>
        </div>
      </main>
            <section className="legal-section" aria-labelledby="your-rights-h">
        <h2 id="your-rights-h">Your rights over your data</h2>
        <p>
          Wherever you live, we honor these rights for everyone:
        </p>
        <ul>
          <li><strong>Access &amp; portability</strong>, download a complete JSON export of your data, self-serve, from <a href="/account">your account</a>.</li>
          <li><strong>Deletion</strong>, delete your account and all associated data (sessions, shots, bag, billing profile) from <a href="/account">your account</a>, effective immediately. Backups age out within 30 days.</li>
          <li><strong>Correction</strong>, edit your profile and bag directly in the app or the locker.</li>
          <li><strong>No sale of personal data</strong>, we don&apos;t sell it or share it for cross-context advertising.</li>
        </ul>
        <p>
          Questions or requests we haven&apos;t automated yet: email{" "}
          <a href="mailto:rushil@truecarrygolf.com">rushil@truecarrygolf.com</a>, we respond within 30 days.
        </p>
      </section>
      <SiteFooter />
    </>
  );
}
