"use client";

import Link from "next/link";
import { useState } from "react";
import { supabase } from "@/lib/supabase";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense } from "react";

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
    <div style={{ maxWidth: 420, margin: "80px auto", padding: "0 24px" }}>
      <h1 style={{ fontSize: 32, fontWeight: 800, textAlign: "center", marginBottom: 8 }}>
        {mode === "signin" ? "Sign In" : "Create Account"}
      </h1>
      <p style={{ color: "var(--muted)", textAlign: "center", marginBottom: 32 }}>
        {mode === "signin" ? "Access your True Carry account." : "Get started with True Carry."}
      </p>

      <div className="card">
        {success && <p style={{ color: "var(--sage)", fontSize: 14, marginBottom: 16 }}>{success}</p>}
        {error && <p className="error-msg" style={{ marginBottom: 16 }}>{error}</p>}

        <form onSubmit={handleSubmit} style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <div>
            <label>Email</label>
            <input type="email" value={email} onChange={e => setEmail(e.target.value)} placeholder="you@example.com" required />
          </div>
          <div>
            <label>Password</label>
            <input type="password" value={password} onChange={e => setPassword(e.target.value)} placeholder="••••••••" required />
          </div>
          <button type="submit" className="btn btn-gold" style={{ width: "100%", marginTop: 8 }} disabled={loading}>
            {loading ? "Loading…" : mode === "signin" ? "Sign In" : "Create Account"}
          </button>
        </form>

        <p style={{ textAlign: "center", marginTop: 20, fontSize: 14, color: "var(--muted)" }}>
          {mode === "signin" ? (
            <>No account? <button onClick={() => setMode("signup")} style={{ background: "none", border: "none", color: "var(--gold)", cursor: "pointer", fontSize: 14 }}>Create one</button></>
          ) : (
            <>Have an account? <button onClick={() => setMode("signin")} style={{ background: "none", border: "none", color: "var(--gold)", cursor: "pointer", fontSize: 14 }}>Sign in</button></>
          )}
        </p>
      </div>

      <p style={{ textAlign: "center", marginTop: 24, fontSize: 13, color: "var(--muted)" }}>
        <Link href="/">← Back to home</Link>
      </p>
    </div>
  );
}

export default function LoginPage() {
  return (
    <>
      <Suspense>
        <LoginForm />
      </Suspense>
    </>
  );
}
