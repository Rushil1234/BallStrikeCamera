"use client";

import Link from "next/link";
import { useState, Suspense } from "react";
import { supabase } from "@/lib/supabase";
import { useRouter, useSearchParams } from "next/navigation";
import ThemeToggle from "@/components/ThemeToggle";

function safeRedirectPath(value: string | null) {
  if (!value || !value.startsWith("/") || value.startsWith("//")) return "/account";
  return value;
}

type Mode = "signin" | "signup" | "reset";

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
        options: { emailRedirectTo: `${window.location.origin}/login` },
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
      const { error } = await supabase.auth.signInWithOAuth({
        provider,
        options: {
          redirectTo: `${window.location.origin}/auth/callback?next=${encodeURIComponent(redirect)}`,
          queryParams: provider === "google" ? { prompt: "select_account" } : undefined,
        },
      });
      if (error) throw error;
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
        const { error } = await supabase.auth.signUp({ email, password });
        if (error) throw error;
        setSuccess("Account created — check your email to confirm, then sign in.");
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
  return (
    <div className="auth-page">
      <header className="auth-nav">
        <Link href="/" className="auth-brand" aria-label="True Carry home">
          <img src="/truecarry-logo.png" alt="" aria-hidden />
          <span>True <em>Carry.</em></span>
        </Link>
        <nav className="auth-nav-links" aria-label="Login page navigation">
          <Link href="/#h07">Pricing</Link>
          <ThemeToggle />
        </nav>
      </header>
      <Suspense>
        <LoginForm />
      </Suspense>
    </div>
  );
}
