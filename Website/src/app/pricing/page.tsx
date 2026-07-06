"use client";

import { useState } from "react";
import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";
import EmbeddedCheckoutPanel from "@/components/EmbeddedCheckoutPanel";
import { PLANS } from "@/lib/plans";

export default function PricingPage() {
  const [checkoutTier, setCheckoutTier] = useState<string | null>(null);

  return (
    <>
      <SiteNav />
      <main className="narrow" style={{ paddingTop: 70, paddingBottom: 90 }}>
        <span className="eyebrow">Pricing</span>
        <h1 style={{ fontSize: "clamp(32px,5vw,46px)", margin: "14px 0 10px" }}>One bag, four ways to carry it.</h1>
        <p style={{ opacity: 0.7, marginBottom: 36, maxWidth: 560 }}>
          Every plan uses the same camera launch monitor. Paid tiers unlock cloud sync,
          the simulator, course mode, and deeper analytics. Cancel anytime.
        </p>

        <div className="plans">
          {PLANS.map((plan) => (
            <div className={`plan${plan.featured ? " featured" : ""}`} key={plan.id}>
              {plan.featured && <span className="plan-flag">Most played</span>}
              <div className="plan-name">{plan.name}</div>
              <div className="plan-price">{plan.price}<span className="per">{plan.per}</span></div>
              <p className="plan-tag">{plan.tag}</p>
              <ul>
                {plan.features.map((f) => <li key={f}>{f}</li>)}
              </ul>
              {plan.href ? (
                <a className="plan-cta" href={plan.href}>{plan.cta ?? `Choose ${plan.name}`}</a>
              ) : (
                <button className="plan-cta" onClick={() => setCheckoutTier(plan.id)}>Get {plan.name}</button>
              )}
            </div>
          ))}
        </div>

        <p style={{ opacity: 0.55, fontSize: 13, marginTop: 28 }}>
          Billing runs through Stripe on this site — Apple takes no cut, which is how the
          prices stay this low. Referral rewards stack as complimentary Pro time.
        </p>
      </main>
            <section className="pricing-disclosure" aria-label="Subscription terms">
        <h2>Auto-renewal &amp; cancellation</h2>
        <p>
          Paid plans <strong>renew automatically</strong> at the then-current price — monthly
          plans every month, annual plans every year — until you cancel. We&apos;ll charge the
          payment method on file at each renewal.
        </p>
        <p>
          <strong>Cancel anytime</strong> in <a href="/account">Account → Manage Billing</a> (two
          clicks, no phone call, no chat queue). Cancellation takes effect at the end of the
          current billing period and you keep full access until then. See the{" "}
          <a href="/terms">Terms</a> for details.
        </p>
      </section>
      <SiteFooter />

      {checkoutTier && (
        <EmbeddedCheckoutPanel tier={checkoutTier} onClose={() => setCheckoutTier(null)} />
      )}
    </>
  );
}
