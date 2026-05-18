import Link from "next/link";

export default function BillingCancelPage() {
  return (
    <main style={{ textAlign: "center", padding: "100px 24px" }}>
      <div style={{ fontSize: 64, marginBottom: 24 }}>↩️</div>
      <h1 style={{ fontSize: 36, fontWeight: 800, marginBottom: 16 }}>Checkout Canceled</h1>
      <p style={{ color: "var(--muted)", fontSize: 16, maxWidth: 480, margin: "0 auto 32px" }}>
        No charge was made. Head back to pricing to choose a plan whenever you're ready.
      </p>
      <div style={{ display: "flex", gap: 16, justifyContent: "center" }}>
        <Link href="/pricing" className="btn btn-gold">View Plans</Link>
        <Link href="/" className="btn btn-outline">Home</Link>
      </div>
    </main>
  );
}
