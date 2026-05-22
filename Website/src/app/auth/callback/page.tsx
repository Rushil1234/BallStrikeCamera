"use client";

import { useEffect, useState, Suspense } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { supabase } from "@/lib/supabase";
import ThemeToggle from "@/components/ThemeToggle";

function safeRedirectPath(value: string | null) {
  if (!value || !value.startsWith("/") || value.startsWith("//")) return "/account";
  return value;
}

function AuthCallbackContent() {
  const router = useRouter();
  const params = useSearchParams();
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function finishSignIn() {
      const next = safeRedirectPath(params.get("next"));
      const code = params.get("code");

      try {
        if (code) {
          const { error } = await supabase.auth.exchangeCodeForSession(code);
          if (error) throw error;
        } else {
          const { data } = await supabase.auth.getSession();
          if (!data.session) throw new Error("No sign-in session was returned.");
        }

        if (!cancelled) router.replace(next);
      } catch (err) {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : "Could not finish sign-in.");
        }
      }
    }

    void finishSignIn();
    return () => {
      cancelled = true;
    };
  }, [params, router]);

  return (
    <main className="auth-main">
      <section className="auth-panel">
        <div className="auth-copy">
          <span className="auth-kicker">Secure sign-in</span>
          <h1>Finishing your sign in.</h1>
          <p>We&apos;re connecting your provider to your True Carry account, then sending you back where you started.</p>
        </div>

        <div className="auth-card">
          <div className="auth-card-head">
            <span className="auth-card-label">Account access</span>
            <h2>{error ? "Needs attention" : "One moment"}</h2>
          </div>
          {error ? (
            <>
              <p className="error-msg auth-message">{error}</p>
              <Link href="/login" className="auth-submit" style={{ textDecoration: "none" }}>
                Back to sign in
              </Link>
            </>
          ) : (
            <p className="auth-switch" style={{ marginTop: 0 }}>Completing secure sign-in…</p>
          )}
        </div>
      </section>
    </main>
  );
}

export default function AuthCallbackPage() {
  return (
    <div className="auth-page">
      <header className="auth-nav">
        <Link href="/" className="auth-brand" aria-label="True Carry home">
          <img src="/truecarry-logo.png" alt="" aria-hidden />
          <span>True <em>Carry.</em></span>
        </Link>
        <nav className="auth-nav-links" aria-label="Auth callback navigation">
          <Link href="/login">Sign in</Link>
          <ThemeToggle />
        </nav>
      </header>
      <Suspense>
        <AuthCallbackContent />
      </Suspense>
    </div>
  );
}
