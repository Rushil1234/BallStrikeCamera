"use client";

import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { supabase } from "@/lib/supabase";

const AMOUNTS = [
  { cents: 2500, label: "$25" },
  { cents: 5000, label: "$50" },
  { cents: 10000, label: "$100" },
];

/** The gift-card "Get it" button on /store. Opens a small modal to pick an
 *  amount and enter recipient + buyer email, then hands off to Stripe Checkout. */
export default function GiftCardBuy() {
  const [open, setOpen] = useState(false);
  const [amount, setAmount] = useState(2500);
  const [recipient, setRecipient] = useState("");
  const [buyer, setBuyer] = useState("");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [mounted, setMounted] = useState(false);

  useEffect(() => setMounted(true), []);
  // Lock body scroll while the modal is open.
  useEffect(() => {
    if (!open) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => { document.body.style.overflow = prev; };
  }, [open]);

  const emailOk = (v: string) => /^[^@\s]+@[^@\s.]+\.[^@\s]+$/.test(v.trim());

  async function checkout(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    if (!emailOk(recipient)) return setError("Enter a valid recipient email.");
    if (!emailOk(buyer)) return setError("Enter a valid email for your receipt.");

    setBusy(true);
    const { data, error: fnErr } = await supabase.functions.invoke("create-giftcard-session", {
      body: {
        amountCents: amount,
        recipientEmail: recipient.trim().toLowerCase(),
        purchaserEmail: buyer.trim().toLowerCase(),
        message: message.trim(),
      },
    });
    if (fnErr || !data?.url) {
      setBusy(false);
      setError(data?.error ?? "Couldn't start checkout. Try again in a moment.");
      return;
    }
    window.location.href = data.url; // Stripe Checkout
  }

  return (
    <>
      <button type="button" className="product-cta" onClick={() => setOpen(true)}>
        Get it
      </button>

      {open && mounted && createPortal(
        <div className="gc-overlay" role="dialog" aria-modal="true" aria-labelledby="gc-title" onClick={() => !busy && setOpen(false)}>
          <div className="gc-modal" onClick={(e) => e.stopPropagation()}>
            <button className="gc-close" aria-label="Close" onClick={() => setOpen(false)} disabled={busy}>×</button>
            <p className="gc-kicker">Gift card</p>
            <h2 id="gc-title">Give every yard.</h2>
            <p className="gc-sub">Store credit toward Pro or Atlas. Delivered by email as a code. Never expires.</p>

            <form onSubmit={checkout}>
              <div className="gc-amounts" role="radiogroup" aria-label="Amount">
                {AMOUNTS.map((a) => (
                  <button
                    type="button"
                    key={a.cents}
                    role="radio"
                    aria-checked={amount === a.cents}
                    className={`gc-amount${amount === a.cents ? " on" : ""}`}
                    onClick={() => setAmount(a.cents)}
                  >
                    {a.label}
                  </button>
                ))}
              </div>

              <label className="gc-field">
                <span>Recipient email</span>
                <input type="email" inputMode="email" autoComplete="off" required
                  placeholder="them@email.com" value={recipient} onChange={(e) => setRecipient(e.target.value)} disabled={busy} />
              </label>
              <label className="gc-field">
                <span>Your email (for the receipt)</span>
                <input type="email" inputMode="email" autoComplete="email" required
                  placeholder="you@email.com" value={buyer} onChange={(e) => setBuyer(e.target.value)} disabled={busy} />
              </label>
              <label className="gc-field">
                <span>Message <em>(optional)</em></span>
                <textarea rows={2} maxLength={500} placeholder="Happy birthday — go low."
                  value={message} onChange={(e) => setMessage(e.target.value)} disabled={busy} />
              </label>

              {error && <p className="gc-error" role="alert">{error}</p>}

              <button type="submit" className="gc-submit" disabled={busy}>
                {busy ? "Opening checkout…" : `Continue — ${AMOUNTS.find((a) => a.cents === amount)?.label}`}
              </button>
              <p className="gc-secure">Secure checkout by Stripe. You won't be charged until you confirm.</p>
            </form>
          </div>
        </div>,
        document.body
      )}
    </>
  );
}
