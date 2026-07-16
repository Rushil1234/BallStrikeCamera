"use client";

import Link from "next/link";
import { useEffect, useState, Suspense } from "react";
import { supabase } from "@/lib/supabase";
import { GoogleIcon, AppleIcon } from "@/components/AuthIcons";
import { oauthCopy, signInWithProvider, type OAuthProvider } from "@/lib/oauth";
import { useRouter, useSearchParams } from "next/navigation";

function safeRedirectPath(value: string | null) {
  if (!value || !value.startsWith("/") || value.startsWith("//")) return "/account";
  return value;
}

type Mode = "signin" | "signup" | "reset";

function LoginForm() {
  const router = useRouter();
  const params = useSearchParams();
  const redirect = safeRedirectPath(params.get("redirect"));
  const initialMode = params.get("mode") === "reset" ? "reset" : params.get("mode") === "signup" ? "signup" : "signin";
  const [mode, setMode] = useState<Mode>(initialMode);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [oauthLoading, setOauthLoading] = useState<OAuthProvider | null>(null);
  const [resending, setResending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [confirmationEmail, setConfirmationEmail] = useState<string | null>(null);

  function clearMessages() {
    setError(null);
    setSuccess(null);
  }

  async function handleResendConfirmation() {
    if (!confirmationEmail) return;
    clearMessages();
    setResending(true);
    try {
      const { error } = await supabase.auth.resend({
        type: "signup",
        email: confirmationEmail,
        options: { emailRedirectTo: `${window.location.origin}/auth/callback?next=/account` },
      });
      if (error) throw error;
      setSuccess(`Confirmation email resent to ${confirmationEmail}.`);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Could not resend confirmation email.");
    } finally {
      setResending(false);
    }
  }

  async function handleOAuth(provider: OAuthProvider) {
    clearMessages();
    setOauthLoading(provider);
    try {
      await signInWithProvider(provider, redirect);
      // browser redirects to the provider on success
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : oauthCopy[provider].error);
      setOauthLoading(null);
    }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    clearMessages();
    setLoading(true);

    try {
      if (mode === "reset") {
        const { error } = await supabase.auth.resetPasswordForEmail(email, {
          redirectTo: `${window.location.origin}/reset-password`,
        });
        if (error) throw error;
        setSuccess("If an account exists for that email, a password reset link is on its way.");
      } else if (mode === "signin") {
        const { error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
        router.push(redirect);
      } else {
        const { error } = await supabase.auth.signUp({
          email,
          password,
          options: { emailRedirectTo: `${window.location.origin}/auth/callback?next=/account` },
        });
        if (error) throw error;
        setSuccess("Account created, check your email to confirm, then sign in.");
        setConfirmationEmail(email);
        setMode("signin");
      }
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Something went wrong");
    } finally {
      setLoading(false);
    }
  }

  const heading = mode === "signin" ? "Sign In" : mode === "signup" ? "Create Account" : "Reset password";
  const cardLabel = mode === "signin" ? "Account access" : mode === "signup" ? "New account" : "Forgot password";

  return (
    <main className="auth-main" aria-labelledby="auth-title">
      <section className="auth-panel">
        <div className="auth-copy">
          <span className="auth-kicker">
            {mode === "signin" ? "Welcome back" : mode === "signup" ? "Join True Carry" : "No problem"}
          </span>
          <h1 id="auth-title">
            {mode === "signin" ? "Sign in to your bag." : mode === "signup" ? "Create your True Carry account." : "Let's get you back in."}
          </h1>
          <p>
            {mode === "signin"
              ? "Open your dashboard, manage your plan, and keep every round synced."
              : mode === "signup"
              ? "Set up your account so premium data, devices, and shot history stay tied to you."
              : "Enter your email and we'll send a secure link to set a new password."}
          </p>
        </div>

        <div className="auth-card">
          <div className="auth-card-head">
            <span className="auth-card-label">{cardLabel}</span>
            <h2>{heading}</h2>
          </div>

          {success && <p className="success-msg auth-message">{success}</p>}
          {error && <p className="error-msg auth-message">{error}</p>}
          {confirmationEmail && (
            <button type="button" className="auth-resend" onClick={handleResendConfirmation} disabled={resending}>
              {resending ? "Sending…" : "Resend confirmation email"}
            </button>
          )}

          {mode !== "reset" && (
            <>
              <button type="button" className="auth-social" onClick={() => handleOAuth("google")} disabled={Boolean(oauthLoading)}>
                <GoogleIcon />
                {oauthLoading === "google" ? "Connecting…" : "Continue with Google"}
              </button>
              <button type="button" className="auth-social" onClick={() => handleOAuth("apple")} disabled={Boolean(oauthLoading)}>
                <AppleIcon />
                {oauthLoading === "apple" ? "Connecting…" : "Continue with Apple"}
              </button>
              <div className="auth-divider"><span>or</span></div>
            </>
          )}

          <form onSubmit={handleSubmit} className="auth-form">
            <div>
              <label htmlFor="email">Email</label>
              <input
                id="email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="you@example.com"
                autoComplete="email"
                required
              />
            </div>
            {mode !== "reset" && (
              <div>
                <div className="auth-label-row">
                  <label htmlFor="password">Password</label>
                  {mode === "signin" && (
                    <button type="button" className="auth-forgot" onClick={() => { clearMessages(); setMode("reset"); }}>
                      Forgot password?
                    </button>
                  )}
                </div>
                <input
                  id="password"
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="Enter your password"
                  autoComplete={mode === "signin" ? "current-password" : "new-password"}
                  required
                />
              </div>
            )}
            <button type="submit" className="auth-submit" disabled={loading}>
              {loading
                ? "Loading..."
                : mode === "signin"
                ? "Sign In"
                : mode === "signup"
                ? "Create Account"
                : "Send reset link"}
            </button>
          </form>

          <p className="auth-switch">
            {mode === "reset" ? (
              <>Remembered it?{" "}
                <button type="button" onClick={() => { clearMessages(); setMode("signin"); }}>Back to sign in</button>
              </>
            ) : mode === "signin" ? (
              <>No account yet?{" "}
                <button type="button" onClick={() => { clearMessages(); setMode("signup"); }}>Create one</button>
              </>
            ) : (
              <>Already have an account?{" "}
                <button type="button" onClick={() => { clearMessages(); setMode("signin"); }}>Sign in</button>
              </>
            )}
          </p>
        </div>
      </section>
    </main>
  );
}

export default function LoginPage() {
  const [navPhase, setNavPhase] = useState<"entering" | "transitioning" | "settled">("entering");

  useEffect(() => {
    const transitionTimer = window.setTimeout(() => setNavPhase("transitioning"), 40);
    const settledTimer = window.setTimeout(() => setNavPhase("settled"), 680);
    return () => {
      window.clearTimeout(transitionTimer);
      window.clearTimeout(settledTimer);
    };
  }, []);

  const authPageClassName = [
    "auth-page",
    navPhase === "entering" ? "auth-page-entering" : null,
    navPhase === "settled" ? "auth-page-settled" : null,
  ].filter(Boolean).join(" ");

  return (
    <div className={authPageClassName}>
      <header className="auth-nav">
        <Link href="/" className="auth-brand" aria-label="True Carry home">
          <img src="/truecarry-logo.png" alt="" aria-hidden />
          <span>True <em>Carry.</em></span>
        </Link>
        <nav className="auth-nav-links" aria-label="Login page navigation">
          <Link href="/#h07">Pricing</Link>
        </nav>
      </header>
      <Suspense>
        <LoginForm />
      </Suspense>
    </div>
  );
}
