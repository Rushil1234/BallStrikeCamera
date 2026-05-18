import Link from "next/link";

export default function PrivacyPage() {
  return (
    <>
      <nav>
        <Link href="/" className="nav-logo">True Carry</Link>
      </nav>
      <main className="container" style={{ paddingTop: 60, paddingBottom: 80, maxWidth: 720, margin: "0 auto" }}>
        <h1 style={{ fontSize: 36, fontWeight: 800, marginBottom: 32 }}>Privacy Policy</h1>
        <div style={{ color: "var(--muted)", lineHeight: 1.8, fontSize: 15 }}>
          <p style={{ marginBottom: 20 }}>
            True Carry collects only the data necessary to operate the app and website:
            your email address, shot data you create, and subscription status. We do not
            sell your data to third parties.
          </p>
          <p style={{ marginBottom: 20 }}>
            Shot data (ball speed, carry distance, launch angle, video frames) is stored
            securely in Supabase and is only accessible to your account.
          </p>
          <p style={{ marginBottom: 20 }}>
            Payment processing is handled by Stripe. We do not store credit card information.
          </p>
          <p>
            For questions, email <a href="mailto:support@truecarry.app">support@truecarry.app</a>.
          </p>
        </div>
      </main>
    </>
  );
}
