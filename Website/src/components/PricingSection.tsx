"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabase";
import Reveal from "@/components/Reveal";
import EmbeddedCheckoutPanel from "@/components/EmbeddedCheckoutPanel";

const CHECKOUT_URL = process.env.NEXT_PUBLIC_CREATE_CHECKOUT_FUNCTION_URL!;

const FEATURES = [
  "All play modes: range, simulator, course",
  "Unlimited shots, every day",
  "Ball speed, launch, and carry on every strike",
  "Cloud sync across your devices",
  "Shot history and analytics",
  "Cancel anytime",
];

export default function PricingSection() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [checkoutToken, setCheckoutToken] = useState<string | null>(null);
  const router = useRouter();

  async function handleUpgrade() {
    setError(null);
    setLoading(true);

    try {
      const {
        data: { session },
      } = await supabase.auth.getSession();

      if (!session) {
        router.push("/login?redirect=%2F%23pricing");
        return;
      }

      setCheckoutToken(session.access_token);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Something went wrong");
    } finally {
      setLoading(false);
    }
  }

  return (
    <section className="section pricing-home" id="pricing">
      <div className="container pricing-layout">
        <Reveal className="section-head pricing-copy">
          <span className="eyebrow">Pricing</span>
          <h2 style={{ fontSize: "clamp(34px,6vw,68px)", margin: "22px 0 20px" }}>
            One plan. <span className="gold-text">Everything in.</span>
          </h2>
          <p className="lead">
            Full access to True Carry for a flat monthly price. No launch monitor, no add-on sensors,
            no tier maze hiding the numbers you actually came for.
          </p>
        </Reveal>

        <Reveal delay={120} className="pricing-card-wrap">
          {error && <p className="error-msg" style={{ marginBottom: 18 }}>{error}</p>}

          <div className="card pricing-card">
            <div className="pricing-card-top">
              <div>
                <span className="badge">Full access</span>
                <h3 style={{ fontSize: 30, marginTop: 12 }}>Premium</h3>
              </div>
              <div className="pricing-price">
                <span className="price-amt">$10</span>
                <span className="price-unit">/ month</span>
              </div>
            </div>

            <p className="price-per">Billed monthly. Cancel anytime.</p>

            <ul className="feat-list" style={{ marginTop: 30 }}>
              {FEATURES.map((feature) => (
                <li key={feature}>
                  <span className="ck">✓</span>
                  {feature}
                </li>
              ))}
            </ul>

            <button className="btn btn-gold btn-block btn-lg" onClick={handleUpgrade} disabled={loading}>
              {loading ? "Preparing checkout..." : "Get Premium"}
            </button>
          </div>

          <p className="pricing-note">
            A free tier is available inside the app. Subscriptions are securely managed by Stripe.
          </p>
        </Reveal>
      </div>

      {checkoutToken && (
        <EmbeddedCheckoutPanel
          accessToken={checkoutToken}
          checkoutUrl={CHECKOUT_URL}
          onClose={() => setCheckoutToken(null)}
        />
      )}
    </section>
  );
}
