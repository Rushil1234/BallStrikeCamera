"use client";

import { EmbeddedCheckout, EmbeddedCheckoutProvider } from "@stripe/react-stripe-js";
import { loadStripe } from "@stripe/stripe-js";
import { useCallback, useEffect, useMemo, useState } from "react";
import { supabase } from "@/lib/supabase";
import { GoogleIcon, AppleIcon } from "@/components/AuthIcons";
import { oauthCopy, signInWithProvider, type OAuthProvider } from "@/lib/oauth";
import { isUndeliverableEmail } from "@/lib/email";

const publishableKey = process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY;
const stripePromise = publishableKey ? loadStripe(publishableKey) : null;
const DEFAULT_CHECKOUT_URL = process.env.NEXT_PUBLIC_CREATE_CHECKOUT_FUNCTION_URL;

interface EmbeddedCheckoutPanelProps {
  onClose: () => void;
  /** Which plan to check out (pro | atlas). Defaults to pro. */
  tier?: string;
  /** Annual commitment (yearly) or month to month. Defaults to yearly. */
  billingInterval?: "yearly" | "monthly";
  /** Optional pre-resolved token. If absent, the panel resolves/handles auth itself. */
  accessToken?: string | null;
  checkoutUrl?: string;
}

export default function EmbeddedCheckoutPanel({ onClose, tier = "pro", billingInterval = "yearly", accessToken = null, checkoutUrl }: EmbeddedCheckoutPanelProps) {
  const url = checkoutUrl ?? DEFAULT_CHECKOUT_URL ?? "";
  const [token, setToken] = useState<string | null>(accessToken);
  const [checkingSession, setCheckingSession] = useState(!accessToken);
  const [clientSecret, setClientSecret] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [complete, setComplete] = useState(false);
  const [alreadySubscribed, setAlreadySubscribed] = useState(false);
  const [requestId, setRequestId] = useState(0);

  // Inline auth (so the button never navigates away)
  const [mode, setMode] = useState<"signin" | "signup">("signin");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [authBusy, setAuthBusy] = useState(false);
  const [oauthBusy, setOauthBusy] = useState<OAuthProvider | null>(null);
  const [authMsg, setAuthMsg] = useState<string | null>(null);

  // Resolve an existing session when no token was handed in.
  useEffect(() => {
    if (token) {
      setCheckingSession(false);
      return;
    }
    let cancelled = false;
    supabase.auth.getSession().then(({ data }) => {
      if (cancelled) return;
      if (data.session) setToken(data.session.access_token);
      setCheckingSession(false);
    });
    return () => {
      cancelled = true;
    };
  }, [token]);

  async function handleAuth(e: React.FormEvent) {
    e.preventDefault();
    setAuthMsg(null);
    setAuthBusy(true);
    try {
      if (mode === "signin") {
        const { data, error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
        if (data.session) setToken(data.session.access_token);
      } else {
        if (isUndeliverableEmail(email)) {
          throw new Error("Please use a real, deliverable email address.");
        }
        const { data, error } = await supabase.auth.signUp({
          email,
          password,
          options: { emailRedirectTo: `${window.location.origin}/auth/callback?next=${encodeURIComponent("/?checkout=premium#h07")}` },
        });
        if (error) throw error;
        if (data.session) {
          setToken(data.session.access_token);
        } else {
          setAuthMsg("Account created, check your email to confirm, then sign in here to finish checkout.");
          setMode("signin");
        }
      }
    } catch (err) {
      setAuthMsg(err instanceof Error ? err.message : "Could not sign in.");
    } finally {
      setAuthBusy(false);
    }
  }

  async function handleOAuth(provider: OAuthProvider) {
    setAuthMsg(null);
    setOauthBusy(provider);
    try {
      await signInWithProvider(provider, "/?checkout=premium#h07");
    } catch (err) {
      setAuthMsg(err instanceof Error ? err.message : oauthCopy[provider].error);
      setOauthBusy(null);
    }
  }

  const createCheckoutSession = useCallback(async () => {
    if (!publishableKey) throw new Error("Stripe publishable key is not configured.");
    if (!url) throw new Error("Checkout function URL is not configured.");
    if (!token) throw new Error("Not signed in.");

    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({ tier, billingInterval, uiMode: "embedded" }),
    });

    const json = await res.json().catch(() => ({}));
    if (!res.ok) {
      throw new Error(res.status === 401 ? "Please sign in again before checkout." : (json.error ?? "Checkout failed."));
    }
    // Server refused checkout because this account already has premium — signal
    // the caller (null) instead of trying to render a Stripe session.
    if (json.alreadySubscribed) return null;
    if (!json.clientSecret) throw new Error("Checkout did not return a client secret.");
    return json.clientSecret as string;
  }, [token, url, tier, billingInterval]);

  useEffect(() => {
    if (!token) return;
    let cancelled = false;
    setError(null);
    setClientSecret(null);
    setComplete(false);
    setAlreadySubscribed(false);
    createCheckoutSession()
      .then((secret) => {
        if (cancelled) return;
        if (secret === null) { setAlreadySubscribed(true); return; }
        setClientSecret(secret);
      })
      .catch((err) => {
        if (!cancelled) setError(err instanceof Error ? err.message : "Checkout failed.");
      });
    return () => {
      cancelled = true;
    };
  }, [createCheckoutSession, token, requestId]);

  const options = useMemo(() => ({ clientSecret, onComplete: () => setComplete(true) }), [clientSecret]);

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

        {!stripePromise ? (
          <div className="checkout-config">
            <h3>Stripe needs one public setting.</h3>
            <p>
              Add <code>NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY</code> to enable embedded checkout. Card details are
              handled by Stripe, never by True Carry servers.
            </p>
          </div>
        ) : complete ? (
          <div className="checkout-config">
            <h3>You&apos;re all set.</h3>
            <p>Stripe confirmed your subscription. Premium unlocks as soon as the webhook syncs, usually seconds.</p>
            <button className="checkout-retry" type="button" onClick={onClose}>
              Done
            </button>
          </div>
        ) : error ? (
          <div className="checkout-config checkout-error">
            <h3>Checkout needs attention.</h3>
            <p>{error}</p>
            <button className="checkout-retry" type="button" onClick={() => setRequestId((n) => n + 1)}>
              Try again
            </button>
          </div>
        ) : checkingSession ? (
          <div className="checkout-config">
            <h3>Loading…</h3>
          </div>
        ) : !token ? (
          <div className="checkout-auth">
            <h3>{mode === "signin" ? "Sign in to continue" : "Create your account"}</h3>
            <p>Your subscription ties to your True Carry account, so it unlocks in the app too.</p>
            {authMsg && <p className="error-msg" style={{ marginBottom: 6 }}>{authMsg}</p>}
            <button type="button" className="auth-social" onClick={() => handleOAuth("google")} disabled={Boolean(oauthBusy)}>
              <GoogleIcon />
              {oauthBusy === "google" ? "Connecting…" : "Continue with Google"}
            </button>
            <button type="button" className="auth-social auth-apple" onClick={() => handleOAuth("apple")} disabled={Boolean(oauthBusy)}>
              <AppleIcon />
              {oauthBusy === "apple" ? "Connecting…" : "Continue with Apple"}
            </button>
            <div className="auth-divider"><span>or</span></div>
            <form onSubmit={handleAuth}>
              <label htmlFor="co-email">Email</label>
              <input id="co-email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="you@example.com" autoComplete="email" required />
              <div className="auth-label-row">
                <label htmlFor="co-pass">Password</label>
                {mode === "signin" && (
                  <button type="button" className="auth-forgot" onClick={() => { window.location.href = "/login?mode=reset"; }}>
                    Forgot password?
                  </button>
                )}
              </div>
              <input id="co-pass" type="password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="Your password" autoComplete={mode === "signin" ? "current-password" : "new-password"} required />
              <button type="submit" className="btn btn-gold btn-block" disabled={authBusy}>
                {authBusy ? "Working…" : mode === "signin" ? "Sign in & continue" : "Create account & continue"}
              </button>
            </form>
            <p className="checkout-auth-switch">
              {mode === "signin" ? "No account yet?" : "Already have an account?"}{" "}
              <button type="button" onClick={() => { setMode(mode === "signin" ? "signup" : "signin"); setAuthMsg(null); }}>
                {mode === "signin" ? "Create one" : "Sign in"}
              </button>
            </p>
          </div>
        ) : alreadySubscribed ? (
          <div className="checkout-config">
            <h3>You&apos;re already subscribed 🎉</h3>
            <p>This account already has True Carry premium — no need to pay again. Sign in on the app to start playing.</p>
            <a className="btn btn-gold btn-block" href="/account" style={{ textDecoration: "none", marginTop: 12 }}>Go to your account</a>
          </div>
        ) : clientSecret ? (
          <EmbeddedCheckoutProvider stripe={stripePromise} options={options}>
            <EmbeddedCheckout />
          </EmbeddedCheckoutProvider>
        ) : (
          <div className="checkout-config">
            <h3>Preparing secure checkout…</h3>
            <p>Creating your Stripe session inside True Carry.</p>
          </div>
        )}
      </div>
    </div>
  );
}
