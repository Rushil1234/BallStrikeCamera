"use client";

import { EmbeddedCheckout, EmbeddedCheckoutProvider } from "@stripe/react-stripe-js";
import { loadStripe } from "@stripe/stripe-js";
import { useCallback, useMemo } from "react";

const publishableKey = process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY;
const stripePromise = publishableKey ? loadStripe(publishableKey) : null;

interface EmbeddedCheckoutPanelProps {
  accessToken: string;
  checkoutUrl: string;
  onClose: () => void;
}

export default function EmbeddedCheckoutPanel({ accessToken, checkoutUrl, onClose }: EmbeddedCheckoutPanelProps) {
  const fetchClientSecret = useCallback(async () => {
    if (!publishableKey) {
      throw new Error("Stripe publishable key is not configured.");
    }

    const res = await fetch(checkoutUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        tier: "premium",
        billingInterval: "monthly",
        uiMode: "embedded",
      }),
    });

    const json = await res.json();
    if (!res.ok) throw new Error(json.error ?? "Checkout failed");
    if (!json.clientSecret) throw new Error("Checkout did not return a client secret.");
    return json.clientSecret as string;
  }, [accessToken, checkoutUrl]);

  const options = useMemo(() => ({ fetchClientSecret }), [fetchClientSecret]);

  return (
    <div className="checkout-overlay" role="dialog" aria-modal="true" aria-label="True Carry checkout">
      <button className="checkout-scrim" type="button" onClick={onClose} aria-label="Close checkout" />
      <div className="checkout-shell">
        <div className="checkout-head">
          <div>
            <span className="badge">Secure checkout</span>
            <h2>Upgrade without leaving True Carry.</h2>
          </div>
          <button className="checkout-close" type="button" onClick={onClose} aria-label="Close checkout">
            Close
          </button>
        </div>

        {stripePromise ? (
          <EmbeddedCheckoutProvider stripe={stripePromise} options={options}>
            <EmbeddedCheckout />
          </EmbeddedCheckoutProvider>
        ) : (
          <div className="checkout-config">
            <h3>Stripe needs one public setting.</h3>
            <p>
              Add <code>NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY</code> in Vercel and locally to enable embedded checkout.
              Card details will still be handled by Stripe, not by True Carry servers.
            </p>
          </div>
        )}
      </div>
    </div>
  );
}
