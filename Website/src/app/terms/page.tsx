import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";

export const metadata = { title: "Terms of Service" };

const UPDATED = "July 3, 2026";

export default function TermsPage() {
  return (
    <>
      <SiteNav />
      <main className="narrow" style={{ paddingTop: 70, paddingBottom: 90 }}>
        <span className="eyebrow">Legal</span>
        <h1 style={{ fontSize: "clamp(32px,5vw,46px)", margin: "14px 0 10px" }}>Terms of Service</h1>
        <p style={{ opacity: 0.6, marginBottom: 28 }}>Last updated {UPDATED}</p>
        <div className="prose">
          <h2>The service</h2>
          <p>
            True Carry is a camera-based golf launch monitor app, browser simulator, and
            companion website. Metrics are estimates produced from camera capture and physics
            models; they are for practice and entertainment, not professional club fitting or
            tournament measurement.
          </p>
          <h2>Your account</h2>
          <p>
            You are responsible for the activity on your account and for keeping your sign-in
            method secure. One account per person; you must be 13 or older.
          </p>
          <h2>Subscriptions</h2>
          <p>
            Paid tiers (Basic, Pro, Atlas) are billed through Stripe on the website, monthly,
            and renew automatically until canceled. You can cancel anytime from Account →
            Manage Billing; access continues to the end of the paid period. Referral rewards
            (complimentary Pro time) are promotional, non-transferable, and may be adjusted in
            cases of abuse.
          </p>
          <h2>Fair use</h2>
          <p>
            Do not attempt to break, reverse-bill, scrape, or resell the service; do not upload
            unlawful content to shared surfaces (feed, shot cards). We may suspend accounts
            that abuse referral codes, pairing codes, or other users.
          </p>
          <h2>Content</h2>
          <p>
            Your golf data is yours. By sharing a shot or post you grant us the limited license
            needed to display it to the audience you selected. Simulator courses are built from
            open geographic data (© OpenStreetMap contributors, ODbL; USGS elevation).
          </p>
          <h2>Warranty & liability</h2>
          <p>
            The service is provided “as is” without warranties. To the extent permitted by law,
            our liability is limited to the amount you paid in the last 12 months. Play safely —
            you are responsible for your swing space.
          </p>
          <h2>Changes</h2>
          <p>
            We may update these terms; material changes will be announced in the app or by
            email. Continued use after changes means acceptance. Questions:
            {" "}<a href="mailto:support@truecarry.app">support@truecarry.app</a>.
          </p>
        </div>
      </main>
      <SiteFooter />
    </>
  );
}
