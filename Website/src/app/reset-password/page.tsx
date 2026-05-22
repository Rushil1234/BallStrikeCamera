"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabase";
import ThemeToggle from "@/components/ThemeToggle";

export default function ResetPasswordPage() {
  const router = useRouter();
  const [ready, setReady] = useState(false);
  const [checking, setChecking] = useState(true);
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  useEffect(() => {
    let mounted = true;

    async function verifyResetLink() {
      const code = new URLSearchParams(window.location.search).get("code");
      if (code) {
        const { error } = await supabase.auth.exchangeCodeForSession(code);
        if (error) {
          if (mounted) {
            setError(error.message);
            setChecking(false);
          }
          return;
        }
      }

      // Supabase can also auto-detect recovery tokens in the URL hash.
      const { data } = await supabase.auth.getSession();
      if (mounted) {
        setReady(Boolean(data.session));
        setChecking(false);
      }
    }

    void verifyResetLink();

    const { data: sub } = supabase.auth.onAuthStateChange((event, session) => {
      if (!mounted) return;
      if (event === "PASSWORD_RECOVERY" || session) {
        setReady(true);
        setChecking(false);
      }
    });

    // Fallback: if no recovery session appears, stop the spinner so we can explain.
    const timer = setTimeout(() => mounted && setChecking(false), 2500);

    return () => {
      mounted = false;
      sub.subscription.unsubscribe();
      clearTimeout(timer);
    };
  }, []);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    if (password.length < 6) { setError("Use at least 6 characters."); return; }
    if (password !== confirm) { setError("Passwords don't match."); return; }
    setSaving(true);
    try {
      const { error } = await supabase.auth.updateUser({ password });
      if (error) throw error;
      setDone(true);
      setTimeout(() => router.push("/account"), 1600);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Could not update password.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="auth-page">
      <header className="auth-nav">
        <Link href="/" className="auth-brand" aria-label="True Carry home">
          <img src="/truecarry-logo.png" alt="" aria-hidden />
          <span>True <em>Carry.</em></span>
        </Link>
        <nav className="auth-nav-links" aria-label="Reset password navigation">
          <Link href="/login">Sign in</Link>
          <ThemeToggle />
        </nav>
      </header>

      <main className="auth-main">
        <section className="auth-panel">
          <div className="auth-copy">
            <span className="auth-kicker">Account security</span>
            <h1>Set a new password.</h1>
            <p>Choose a new password for your True Carry account. You&apos;ll be signed in right after.</p>
          </div>

          <div className="auth-card">
            <div className="auth-card-head">
              <span className="auth-card-label">Reset password</span>
              <h2>New password</h2>
            </div>

            {error && <p className="error-msg auth-message">{error}</p>}

            {done ? (
              <p className="success-msg auth-message">Password updated. Taking you to your account…</p>
            ) : checking ? (
              <p className="auth-switch" style={{ marginTop: 0 }}>Verifying your reset link…</p>
            ) : ready ? (
              <form onSubmit={handleSubmit} className="auth-form">
                <div>
                  <label htmlFor="pw">New password</label>
                  <input id="pw" type="password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="At least 6 characters" autoComplete="new-password" required />
                </div>
                <div>
                  <label htmlFor="pw2">Confirm password</label>
                  <input id="pw2" type="password" value={confirm} onChange={(e) => setConfirm(e.target.value)} placeholder="Re-enter password" autoComplete="new-password" required />
                </div>
                <button type="submit" className="auth-submit" disabled={saving}>
                  {saving ? "Saving…" : "Update password"}
                </button>
              </form>
            ) : (
              <div>
                <p style={{ color: "var(--muted)", lineHeight: 1.6, marginBottom: 16 }}>
                  This reset link is invalid or has expired. Request a fresh one from the sign-in page.
                </p>
                <Link href="/login" className="auth-submit" style={{ textDecoration: "none" }}>Back to sign in</Link>
              </div>
            )}
          </div>
        </section>
      </main>
    </div>
  );
}
