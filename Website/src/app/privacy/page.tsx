import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";

export const metadata = { title: "Privacy Policy" };

export default function PrivacyPage() {
  return (
    <>
      <SiteNav />
      <main className="narrow" style={{ paddingTop: 70, paddingBottom: 90 }}>
        <span className="eyebrow">Legal</span>
        <h1 style={{ fontSize: "clamp(32px,5vw,46px)", margin: "14px 0 28px" }}>Privacy Policy</h1>
        <div className="prose">
          <p>
            True Carry collects only the data necessary to operate the app and website:
            your email address, shot data you create, and subscription status. We do not
            sell your data to third parties.
          </p>
          <p>
            Shot data (ball speed, carry distance, launch angle, video frames) is stored
            securely in Supabase and is only accessible to your account.
          </p>
          <p>
            Payment processing is handled by Stripe. We do not store credit card information.
          </p>
          <p>
            For questions, visit our <a href="/support">support page</a> or email{" "}
            <a href="mailto:Rushil@truecarrygolf.com">Rushil@truecarrygolf.com</a>.
          </p>
        </div>
      </main>
      <SiteFooter />
    </>
  );
}
