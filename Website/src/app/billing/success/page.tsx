import Link from "next/link";
import SiteNav from "@/components/SiteNav";

export default function BillingSuccessPage() {
  return (
    <>
      <SiteNav actions={<Link href="/account">Account</Link>} />
      <main style={{ textAlign: "center", padding: "min(12vh, 110px) 24px 110px", maxWidth: 560, margin: "0 auto" }}>
        <div
          style={{
            width: 76, height: 76, borderRadius: "50%", margin: "0 auto 28px",
            display: "grid", placeItems: "center", fontSize: 34, color: "#1a1206",
            background: "linear-gradient(135deg, var(--gold-bright), var(--gold))",
            boxShadow: "var(--shadow-gold)",
          }}
        >
          ✓
        </div>
        <span className="eyebrow">Subscription active</span>
        <h1 style={{ fontSize: "clamp(32px,5vw,46px)", margin: "16px 0 16px" }}>
          You&apos;re all set
        </h1>
        <p className="lead" style={{ marginBottom: 34 }}>
          Your True Carry subscription is now active. Open the app on your iPhone and sign in with
          this account to unlock your plan.
        </p>
        <div style={{ display: "flex", gap: 14, justifyContent: "center", flexWrap: "wrap" }}>
          <Link href="/account" className="btn btn-gold btn-lg">Go to Account</Link>
          <Link href="/" className="btn btn-outline btn-lg">Home</Link>
        </div>
      </main>
    </>
  );
}
