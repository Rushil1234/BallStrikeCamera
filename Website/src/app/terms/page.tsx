import Link from "next/link";

export default function TermsPage() {
  return (
    <>
      <nav>
        <Link href="/" className="nav-logo">True Carry</Link>
      </nav>
      <main className="container" style={{ paddingTop: 60, paddingBottom: 80, maxWidth: 720, margin: "0 auto" }}>
        <h1 style={{ fontSize: 36, fontWeight: 800, marginBottom: 32 }}>Terms of Service</h1>
        <div style={{ color: "var(--muted)", lineHeight: 1.8, fontSize: 15 }}>
          <p style={{ marginBottom: 20 }}>
            By using True Carry you agree to use the app for personal golf tracking only.
          </p>
          <p style={{ marginBottom: 20 }}>
            Subscriptions are billed monthly or annually through Stripe. You may cancel at
            any time from your account page; access continues until the end of the billing period.
          </p>
          <p style={{ marginBottom: 20 }}>
            True Carry is provided as-is. Distance and speed measurements are estimates and
            should not be relied upon for competitive purposes.
          </p>
          <p>
            For questions, email <a href="mailto:support@truecarry.app">support@truecarry.app</a>.
          </p>
        </div>
      </main>
    </>
  );
}
