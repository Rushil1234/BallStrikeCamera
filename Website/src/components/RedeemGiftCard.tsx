"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

type State = "idle" | "redeeming" | "done" | "error";

/** Redeem a gift-card code on /account. Prefills from ?redeem=CODE (the email's
 *  button links here). On success the amount becomes Stripe account credit that
 *  auto-applies to the next Pro/Atlas invoice. */
export default function RedeemGiftCard() {
  const [code, setCode] = useState("");
  const [state, setState] = useState<State>("idle");
  const [message, setMessage] = useState<string | null>(null);

  // Prefill from the deep link, then strip it from the URL.
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const pre = params.get("redeem");
    if (pre) {
      setCode(pre.toUpperCase());
      params.delete("redeem");
      const q = params.toString();
      window.history.replaceState(null, "", window.location.pathname + (q ? `?${q}` : ""));
    }
  }, []);

  async function redeem(e: React.FormEvent) {
    e.preventDefault();
    setState("redeeming");
    setMessage(null);
    const { data, error } = await supabase.functions.invoke("redeem-gift-card", {
      body: { code: code.trim().toUpperCase() },
    });
    if (error || !data?.ok) {
      setState("error");
      setMessage(data?.error ?? "Couldn't redeem that code. Try again.");
      return;
    }
    const dollars = (data.amountCents / 100).toFixed(0);
    setState("done");
    setMessage(`$${dollars} credit added — it comes off your next plan automatically.`);
    setCode("");
  }

  return (
    <section className="card redeem-card" aria-labelledby="redeem-h">
      <h2 id="redeem-h">Redeem a gift card</h2>
      <p className="redeem-copy">
        Enter a True Carry gift card code. The credit applies automatically to your next
        Pro or Atlas charge.
      </p>
      {state === "done" ? (
        <p className="redeem-done" role="status">{message}</p>
      ) : (
        <form className="redeem-form" onSubmit={redeem}>
          <input
            aria-label="Gift card code"
            placeholder="TC-XXXX-XXXX-XXXX"
            value={code}
            onChange={(e) => setCode(e.target.value.toUpperCase())}
            disabled={state === "redeeming"}
            spellCheck={false}
            autoComplete="off"
          />
          <button type="submit" className="btn btn-gold" disabled={state === "redeeming" || code.trim().length < 8}>
            {state === "redeeming" ? "Redeeming…" : "Redeem"}
          </button>
        </form>
      )}
      {state === "error" && message && <p className="redeem-error" role="alert">{message}</p>}
    </section>
  );
}
