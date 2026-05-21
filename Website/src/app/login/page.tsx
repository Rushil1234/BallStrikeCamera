"use client";

import Link from "next/link";
import { useState, Suspense } from "react";
import { supabase } from "@/lib/supabase";
import { useRouter, useSearchParams } from "next/navigation";
import SiteNav from "@/components/SiteNav";

function LoginForm() {
  const [mode, setMode] = useState<"signin" | "signup">("signin");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const router = useRouter();
  const params = useSearchParams();
  const redirect = params.get("redirect") ?? "/account";

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
    <main style={{ maxWidth: 440, margin: "0 auto", padding: "min(11vh, 90px) 24px 90px" }}>
      <div style={{ textAlign: "center", marginBottom: 30 }}>
        <span className="eyebrow">{mode === "signin" ? "Welcome back" : "Join True Carry"}</span>
        <h1 style={{ fontSize: 38, margin: "14px 0 10px" }}>
          {mode === "signin" ? "Sign In" : "Create Account"}
        </h1>
        <p style={{ color: "var(--muted)", fontSize: 15 }}>
          {mode === "signin" ? "Access your subscription and account." : "Set up your account to manage your plan."}
        </p>
      </div>

      <div className="card">
        {success && <p className="success-msg" style={{ marginBottom: 16 }}>{success}</p>}
        {error && <p className="error-msg" style={{ marginBottom: 16 }}>{error}</p>}

        <form onSubmit={handleSubmit} style={{ display: "flex", flexDirection: "column", gap: 18 }}>
          <div>
            <label>Email</label>
            <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="you@example.com" required />
          </div>
          <div>
            <label>Password</label>
            <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="••••••••" required />
          </div>
          <button type="submit" className="btn btn-gold btn-block" style={{ marginTop: 6 }} disabled={loading}>
            {loading ? "Loading…" : mode === "signin" ? "Sign In" : "Create Account"}
          </button>
        </form>

        <p style={{ textAlign: "center", marginTop: 22, fontSize: 14, color: "var(--muted)" }}>
          {mode === "signin" ? (
            <>No account?{" "}
              <button onClick={() => setMode("signup")} style={{ background: "none", border: "none", color: "var(--gold)", cursor: "pointer", fontSize: 14, fontWeight: 600 }}>Create one</button>
            </>
          ) : (
            <>Have an account?{" "}
              <button onClick={() => setMode("signin")} style={{ background: "none", border: "none", color: "var(--gold)", cursor: "pointer", fontSize: 14, fontWeight: 600 }}>Sign in</button>
            </>
          )}
        </p>
      </div>

      <p style={{ textAlign: "center", marginTop: 24, fontSize: 13.5, color: "var(--muted)" }}>
        <Link href="/">← Back to home</Link>
      </p>
    </main>
  );
}

export default function LoginPage() {
  return (
    <>
      <SiteNav actions={<Link href="/#pricing">Pricing</Link>} />
      <Suspense>
        <LoginForm />
      </Suspense>
    </>
  );
}
