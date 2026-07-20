"use client";

import { useState } from "react";
import { supabase } from "@/lib/supabase";

type State = "idle" | "open" | "saving" | "done" | "already" | "error";

export default function NotifyForm({
  productId,
  productName,
}: {
  productId: string;
  productName: string;
}) {
  const [state, setState] = useState<State>("idle");
  const [email, setEmail] = useState("");
  const [message, setMessage] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    const value = email.trim().toLowerCase();
    // Cheap client-side check; the database enforces the real constraint.
    if (!/^[^@\s]+@[^@\s.]+\.[^@\s]+$/.test(value)) {
      setMessage("That doesn't look like an email address.");
      setState("error");
      return;
    }

    setState("saving");
    setMessage(null);
    const { error } = await supabase
      .from("store_notify_requests")
      .insert({ email: value, product_id: productId, product_name: productName, source: "store" });

    if (!error) {
      setState("done");
      return;
    }
    // 23505 = unique_violation: they're already on this product's list.
    if (error.code === "23505") {
      setState("already");
      return;
    }
    setMessage("Couldn't save that just now — try again in a moment.");
    setState("error");
  }

  if (state === "done" || state === "already") {
    return (
      <p className="notify-done" role="status">
        {state === "done" ? "On the list — we'll email you." : "You're already on this list."}
      </p>
    );
  }

  if (state === "idle") {
    return (
      <button type="button" className="product-cta ghost" onClick={() => setState("open")}>
        Notify me
      </button>
    );
  }

  return (
    <form className="notify-form" onSubmit={submit}>
      <label className="sr-only" htmlFor={`notify-${productId}`}>
        Email address for {productName} availability
      </label>
      <input
        id={`notify-${productId}`}
        type="email"
        inputMode="email"
        autoComplete="email"
        required
        autoFocus
        placeholder="you@email.com"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        disabled={state === "saving"}
      />
      <button type="submit" className="notify-go" disabled={state === "saving"}>
        {state === "saving" ? "…" : "→"}
      </button>
      {message && <p className="notify-error" role="alert">{message}</p>}
    </form>
  );
}
