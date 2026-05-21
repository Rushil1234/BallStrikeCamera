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

function LoginForm() {
  const [mode, setMode] = useState<"signin" | "signup">("signin");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const router = useRouter();
  const params = useSearchParams();
  const redirect = safeRedirectPath(params.get("redirect"));

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setSuccess(null);
    setLoading(true);

    try {
      if (mode === "signin") {
        const { error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
        router.push(redirect);
      } else {
        const { error } = await supabase.auth.signUp({ email, password });
        if (error) throw error;
        setSuccess("Account created! Check your email to confirm, then sign in.");
        setMode("signin");
      }
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Something went wrong");
    } finally {
      setLoading(false);
    }
  }

  return (
    <main className="auth-main" aria-labelledby="auth-title">
      <section className="auth-panel">
        <div className="auth-copy">
          <span className="auth-kicker">{mode === "signin" ? "Welcome back" : "Join True Carry"}</span>
          <h1 id="auth-title">{mode === "signin" ? "Sign in to your bag." : "Create your True Carry account."}</h1>
          <p>
            {mode === "signin"
              ? "Open your dashboard, manage your plan, and keep every round synced."
              : "Set up your account so premium data, devices, and shot history stay tied to you."}
          </p>
        </div>

        <div className="auth-card">
          <div className="auth-card-head">
            <span className="auth-card-label">{mode === "signin" ? "Account access" : "New account"}</span>
            <h2>{mode === "signin" ? "Sign In" : "Create Account"}</h2>
          </div>

          {success && <p className="success-msg auth-message">{success}</p>}
          {error && <p className="error-msg auth-message">{error}</p>}

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
            <div>
              <label htmlFor="password">Password</label>
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
            <button type="submit" className="auth-submit" disabled={loading}>
              {loading ? "Loading..." : mode === "signin" ? "Sign In" : "Create Account"}
            </button>
          </form>

          <p className="auth-switch">
            {mode === "signin" ? "No account yet?" : "Already have an account?"}{" "}
            <button
              type="button"
              onClick={() => {
                setError(null);
                setSuccess(null);
                setMode(mode === "signin" ? "signup" : "signin");
              }}
            >
              {mode === "signin" ? "Create one" : "Sign in"}
            </button>
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
