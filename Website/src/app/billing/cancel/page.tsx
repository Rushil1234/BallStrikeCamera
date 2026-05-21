import Link from "next/link";
import SiteNav from "@/components/SiteNav";

export default function BillingCancelPage() {
  return (
    <>
      <SiteNav actions={<Link href="/#pricing">Pricing</Link>} />
      <main style={{ textAlign: "center", padding: "min(12vh, 110px) 24px 110px", maxWidth: 560, margin: "0 auto" }}>
        <div
          style={{
            width: 76, height: 76, borderRadius: "50%", margin: "0 auto 28px",
            display: "grid", placeItems: "center", fontSize: 30, color: "var(--muted)",
            background: "var(--surface-2)", border: "1px solid var(--border-strong)",
          }}
        >
          ↩
        </div>
        <span className="eyebrow">No charge made</span>
        <h1 style={{ fontSize: "clamp(32px,5vw,46px)", margin: "16px 0 16px" }}>
          Checkout canceled
        </h1>
        <p className="lead" style={{ marginBottom: 34 }}>
          Nothing was charged. Head back to pricing to choose a plan whenever you&apos;re ready.
        </p>
        <div style={{ display: "flex", gap: 14, justifyContent: "center", flexWrap: "wrap" }}>
          <Link href="/#pricing" className="btn btn-gold btn-lg">View Plans</Link>
          <Link href="/" className="btn btn-outline btn-lg">Home</Link>
        </div>
      </main>
    </>
  );
}
