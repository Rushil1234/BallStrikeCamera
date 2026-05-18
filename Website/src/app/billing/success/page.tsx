import Link from "next/link";

export default function BillingSuccessPage() {
  return (
    <main style={{ textAlign: "center", padding: "100px 24px" }}>
      <div style={{ fontSize: 64, marginBottom: 24 }}>🎉</div>
      <h1 style={{ fontSize: 36, fontWeight: 800, marginBottom: 16 }}>Payment Successful!</h1>
      <p style={{ color: "var(--muted)", fontSize: 16, maxWidth: 480, margin: "0 auto 32px" }}>
        Your True Carry subscription is now active. Open the True Carry app on your iPhone
        and sign in with this account to unlock your plan.
      </p>
      <Link href="/account" className="btn btn-gold">Go to Account</Link>
    </main>
  );
}
