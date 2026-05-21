import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";

export const metadata = { title: "Terms of Service" };

export default function TermsPage() {
  return (
    <>
      <SiteNav />
      <main className="narrow" style={{ paddingTop: 70, paddingBottom: 90 }}>
        <span className="eyebrow">Legal</span>
        <h1 style={{ fontSize: "clamp(32px,5vw,46px)", margin: "14px 0 28px" }}>Terms of Service</h1>
        <div className="prose">
          <p>
            By using True Carry you agree to use the app for personal golf tracking only.
          </p>
          <p>
            Subscriptions are billed monthly or annually through Stripe. You may cancel at
            any time from your account page; access continues until the end of the billing period.
          </p>
          <p>
            True Carry is provided as-is. Distance and speed measurements are estimates and
            should not be relied upon for competitive purposes.
          </p>
          <p>
            For questions, email <a href="mailto:support@truecarry.app">support@truecarry.app</a>.
          </p>
        </div>
      </main>
      <SiteFooter />
    </>
  );
}
