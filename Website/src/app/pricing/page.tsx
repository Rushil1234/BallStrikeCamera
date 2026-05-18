"use client";

import Link from "next/link";
import { useState } from "react";
import { supabase } from "@/lib/supabase";
import { useRouter } from "next/navigation";

const CHECKOUT_URL = process.env.NEXT_PUBLIC_CREATE_CHECKOUT_FUNCTION_URL!;

const TIERS = [
  {
    id: "free",
    name: "Free",
    monthlyPrice: "$0",
    yearlyPrice: "$0",
    badge: null,
    features: [
      "Range mode only",
      "10 shots per day",
      "Basic ball speed & carry",
      "Local device storage",
    ],
    cta: null,
  },
  {
    id: "basic",
    name: "Basic",
    monthlyPrice: "$9.99",
    yearlyPrice: "$79.99",
    badge: null,
    features: [
      "All modes (range, sim, course)",
      "Unlimited daily shots",
      "100 cloud-saved shots",
      "Basic analytics",
      "Cloud sync",
    ],
    cta: "Get Basic",
  },
  {
    id: "pro",
    name: "Pro",
    monthlyPrice: "$19.99",
    yearlyPrice: "$159.99",
    badge: "Most Popular",
    features: [
      "Everything in Basic",
      "1,000 cloud-saved shots",
      "Advanced analytics",
      "In-round suggestions",
      "Video export",
    ],
    cta: "Get Pro",
  },
  {
    id: "unlimited",
    name: "Unlimited",
    monthlyPrice: "$39.99",
    yearlyPrice: "$319.99",
    badge: "All-Access",
    features: [
      "Everything in Pro",
      "Unlimited cloud-saved shots",
      "Full media & frame storage",
      "All analytics features",
      "Priority support",
    ],
    cta: "Get Unlimited",
  },
];

export default function PricingPage() {
  const [interval, setInterval] = useState<"monthly" | "yearly">("monthly");
  const [loading, setLoading] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const router = useRouter();

  async function handleUpgrade(tierId: string) {
    setError(null);
    setLoading(tierId);
    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) {
        router.push("/login?redirect=/pricing");
        return;
      }

      const res = await fetch(CHECKOUT_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${session.access_token}`,
        },
        body: JSON.stringify({ tier: tierId, billingInterval: interval }),
      });

      const json = await res.json();
      if (!res.ok) throw new Error(json.error ?? "Checkout failed");
      window.location.href = json.url;
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Something went wrong");
    } finally {
      setLoading(null);
    }
  }

  return (
    <>
      <nav>
        <Link href="/" className="nav-logo">True Carry</Link>
        <div className="nav-links">
          <Link href="/account">Account</Link>
          <Link href="/login" className="btn btn-outline" style={{ padding: "8px 18px", fontSize: "14px" }}>Sign In</Link>
        </div>
      </nav>

      <main className="container" style={{ paddingTop: 60, paddingBottom: 80 }}>
        <div style={{ textAlign: "center", marginBottom: 48 }}>
          <h1 style={{ fontSize: 40, fontWeight: 800, marginBottom: 12 }}>Simple Pricing</h1>
          <p style={{ color: "var(--muted)", fontSize: 16, marginBottom: 28 }}>
            Choose a plan. Upgrade or cancel anytime.
          </p>

          {/* Interval toggle */}
          <div style={{ display: "inline-flex", background: "var(--card)", borderRadius: 12, padding: 4, border: "1px solid var(--border)" }}>
            {(["monthly", "yearly"] as const).map(i => (
              <button
                key={i}
                onClick={() => setInterval(i)}
                style={{
                  padding: "8px 24px",
                  borderRadius: 9,
                  border: "none",
                  fontWeight: 600,
                  fontSize: 14,
                  cursor: "pointer",
                  background: interval === i ? "var(--gold)" : "transparent",
                  color: interval === i ? "#000" : "var(--muted)",
                  transition: "all 0.15s",
                }}
              >
                {i === "monthly" ? "Monthly" : "Yearly (save 33%)"}
              </button>
            ))}
          </div>
        </div>

        {error && <p className="error-msg" style={{ textAlign: "center", marginBottom: 24 }}>{error}</p>}

        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(240px, 1fr))", gap: 20 }}>
          {TIERS.map(tier => (
            <div
              key={tier.id}
              className="card"
              style={{
                position: "relative",
                outline: tier.id === "pro" ? "2px solid var(--gold)" : "none",
              }}
            >
              {tier.badge && (
                <div className="badge" style={{ marginBottom: 12 }}>{tier.badge}</div>
              )}
              <h2 style={{ fontSize: 24, fontWeight: 800, marginBottom: 4 }}>{tier.name}</h2>
              <div style={{ fontSize: 36, fontWeight: 800, color: "var(--gold)", marginBottom: 4 }}>
                {interval === "monthly" ? tier.monthlyPrice : tier.yearlyPrice}
              </div>
              <div style={{ color: "var(--muted)", fontSize: 13, marginBottom: 20 }}>
                {interval === "yearly" && tier.id !== "free" ? "per year" : "per month"}
              </div>

              <ul style={{ listStyle: "none", marginBottom: 24 }}>
                {tier.features.map(f => (
                  <li key={f} style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 10, fontSize: 14, color: "var(--muted)" }}>
                    <span style={{ color: "var(--sage)", fontWeight: 700 }}>✓</span> {f}
                  </li>
                ))}
              </ul>

              {tier.cta ? (
                <button
                  className={`btn ${tier.id === "pro" ? "btn-gold" : "btn-outline"}`}
                  style={{ width: "100%" }}
                  onClick={() => handleUpgrade(tier.id)}
                  disabled={loading === tier.id}
                >
                  {loading === tier.id ? "Redirecting…" : tier.cta}
                </button>
              ) : (
                <div className="btn btn-muted" style={{ width: "100%", textAlign: "center" }}>Free in app</div>
              )}
            </div>
          ))}
        </div>

        <p style={{ textAlign: "center", color: "var(--muted)", fontSize: 13, marginTop: 32 }}>
          Subscriptions managed by Stripe. Cancel anytime from your account page.
        </p>
      </main>

      <footer>
        <div style={{ display: "flex", gap: 24, justifyContent: "center", marginBottom: 16 }}>
          <Link href="/privacy">Privacy</Link>
          <Link href="/terms">Terms</Link>
        </div>
        © {new Date().getFullYear()} True Carry
      </footer>
    </>
  );
}
