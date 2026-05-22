"use client";

import { EmbeddedCheckout, EmbeddedCheckoutProvider } from "@stripe/react-stripe-js";
import { loadStripe } from "@stripe/stripe-js";
import { useCallback, useEffect, useMemo, useState } from "react";
import { supabase } from "@/lib/supabase";

const publishableKey = process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY;
const stripePromise = publishableKey ? loadStripe(publishableKey) : null;
const DEFAULT_CHECKOUT_URL = process.env.NEXT_PUBLIC_CREATE_CHECKOUT_FUNCTION_URL;

function GoogleIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden>
      <path fill="#4285F4" d="M17.64 9.2c0-.64-.06-1.25-.16-1.84H9v3.48h4.84a4.14 4.14 0 0 1-1.8 2.72v2.26h2.92c1.7-1.57 2.68-3.88 2.68-6.62Z" />
      <path fill="#34A853" d="M9 18c2.43 0 4.47-.8 5.96-2.18l-2.92-2.26c-.8.54-1.84.86-3.04.86-2.34 0-4.32-1.58-5.03-3.7H.96v2.33A9 9 0 0 0 9 18Z" />
      <path fill="#FBBC05" d="M3.97 10.72a5.4 5.4 0 0 1 0-3.44V4.95H.96a9 9 0 0 0 0 8.1l3.01-2.33Z" />
      <path fill="#EA4335" d="M9 3.58c1.32 0 2.5.45 3.44 1.35l2.58-2.58C13.46.9 11.43 0 9 0A9 9 0 0 0 .96 4.95l3.01 2.33C4.68 5.16 6.66 3.58 9 3.58Z" />
    </svg>
  );
}

function AppleIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden>
      <path
        fill="currentColor"
        d="M14.4 9.54c-.02-2.04 1.68-3.02 1.76-3.07-.96-1.4-2.44-1.59-2.96-1.61-1.24-.13-2.45.74-3.08.74-.65 0-1.62-.72-2.67-.7-1.36.02-2.63.81-3.33 2.04-1.44 2.49-.37 6.15 1.01 8.16.69 1 1.5 2.11 2.55 2.07 1.03-.04 1.41-.66 2.65-.66 1.23 0 1.58.66 2.66.64 1.11-.02 1.8-1 2.46-2.01.8-1.14 1.12-2.27 1.13-2.33-.03-.01-2.16-.83-2.18-3.27ZM12.39 3.54c.56-.7.94-1.64.84-2.6-.81.04-1.82.56-2.4 1.24-.52.6-.98 1.58-.86 2.51.91.07 1.84-.46 2.42-1.15Z"
      />
    </svg>
  );
}

type OAuthProvider = "google" | "apple";

const oauthCopy: Record<OAuthProvider, { error: string }> = {
  google: { error: "Could not start Google sign-in." },
  apple: { error: "Could not start Apple sign-in." },
};

interface EmbeddedCheckoutPanelProps {
  onClose: () => void;
  /** Which plan to check out (basic | pro | atlas). Defaults to pro. */
  tier?: string;
  /** Optional pre-resolved token. If absent, the panel resolves/handles auth itself. */
  accessToken?: string | null;
  checkoutUrl?: string;
}

export default function EmbeddedCheckoutPanel({ onClose, tier = "pro", accessToken = null, checkoutUrl }: EmbeddedCheckoutPanelProps) {
  const url = checkoutUrl ?? DEFAULT_CHECKOUT_URL ?? "";
  const [token, setToken] = useState<string | null>(accessToken);
  const [checkingSession, setCheckingSession] = useState(!accessToken);
  const [clientSecret, setClientSecret] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [complete, setComplete] = useState(false);
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
        const { data, error } = await supabase.auth.signUp({ email, password });
        if (error) throw error;
        if (data.session) {
          setToken(data.session.access_token);
        } else {
          setAuthMsg("Account created — check your email to confirm, then sign in here to finish checkout.");
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
      const { error } = await supabase.auth.signInWithOAuth({
        provider,
        options: {
          redirectTo: `${window.location.origin}/auth/callback?next=${encodeURIComponent("/?checkout=premium#h07")}`,
          queryParams: provider === "google" ? { prompt: "select_account" } : undefined,
        },
      });
      if (error) throw error;
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
      body: JSON.stringify({ tier, billingInterval: "monthly", uiMode: "embedded" }),
    });

    const json = await res.json().catch(() => ({}));
    if (!res.ok) {
      throw new Error(res.status === 401 ? "Please sign in again before checkout." : (json.error ?? "Checkout failed."));
    }
    if (!json.clientSecret) throw new Error("Checkout did not return a client secret.");
    return json.clientSecret as string;
  }, [token, url, tier]);

  useEffect(() => {
    if (!token) return;
    let cancelled = false;
    setError(null);
    setClientSecret(null);
    setComplete(false);
    createCheckoutSession()
      .then((secret) => {
        if (!cancelled) setClientSecret(secret);
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
            <p>Stripe confirmed your subscription. Premium unlocks as soon as the webhook syncs — usually seconds.</p>
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
