"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { supabase, getUserEntitlement } from "@/lib/supabase";
import { useRouter } from "next/navigation";
import type { User } from "@supabase/supabase-js";

const PORTAL_URL = process.env.NEXT_PUBLIC_CUSTOMER_PORTAL_FUNCTION_URL!;

interface Entitlement {
  tier: string;
  payment_status: string;
  current_period_end: string | null;
  cancel_at_period_end: boolean;
  stripe_customer_id: string | null;
}

export default function AccountPage() {
  const [user, setUser] = useState<User | null>(null);
  const [entitlement, setEntitlement] = useState<Entitlement | null>(null);
  const [loading, setLoading] = useState(true);
  const [portalLoading, setPortalLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const router = useRouter();

  useEffect(() => {
    async function load() {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) { router.push("/login?redirect=/account"); return; }
      setUser(user);
      const ent = await getUserEntitlement(user.id);
      setEntitlement(ent);
      setLoading(false);
    }
    load();
  }, [router]);

  async function handleManageBilling() {
    setError(null);
    setPortalLoading(true);
    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) throw new Error("Not signed in");

      const res = await fetch(PORTAL_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${session.access_token}`,
        },
      });
      const json = await res.json();
      if (!res.ok) throw new Error(json.error ?? "Portal error");
      window.location.href = json.url;
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Something went wrong");
    } finally {
      setPortalLoading(false);
    }
  }

  async function handleSignOut() {
    await supabase.auth.signOut();
    router.push("/");
  }

  if (loading) return <div style={{ textAlign: "center", padding: 80, color: "var(--muted)" }}>Loading…</div>;

  const tier = entitlement?.tier ?? "free";
  const tierDisplay = tier.charAt(0).toUpperCase() + tier.slice(1);
  const periodEnd = entitlement?.current_period_end
    ? new Date(entitlement.current_period_end).toLocaleDateString()
    : null;

  return (
    <>
      <nav>
        <Link href="/" className="nav-logo">True Carry</Link>
        <div className="nav-links">
          <Link href="/pricing">Pricing</Link>
          <button onClick={handleSignOut} className="btn btn-muted" style={{ fontSize: 14, padding: "8px 18px" }}>Sign Out</button>
        </div>
      </nav>

      <main className="container" style={{ paddingTop: 60, paddingBottom: 80, maxWidth: 680, margin: "0 auto" }}>
        <h1 style={{ fontSize: 36, fontWeight: 800, marginBottom: 32 }}>Your Account</h1>

        {error && <p className="error-msg" style={{ marginBottom: 20 }}>{error}</p>}

        {/* Profile */}
        <div className="card" style={{ marginBottom: 20 }}>
          <h2 style={{ fontSize: 18, fontWeight: 700, marginBottom: 16, color: "var(--gold)" }}>Profile</h2>
          <p style={{ fontSize: 15, color: "var(--muted)", marginBottom: 4 }}>Email</p>
          <p style={{ fontSize: 16, fontWeight: 600 }}>{user?.email}</p>
        </div>

        {/* Subscription */}
        <div className="card" style={{ marginBottom: 20 }}>
          <h2 style={{ fontSize: 18, fontWeight: 700, marginBottom: 16, color: "var(--gold)" }}>Subscription</h2>
          <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 16 }}>
            <div className={`badge ${tier !== "free" ? "badge-sage" : ""}`}>{tierDisplay}</div>
            {entitlement?.payment_status && entitlement.payment_status !== "inactive" && (
              <span style={{ color: "var(--muted)", fontSize: 13 }}>{entitlement.payment_status}</span>
            )}
          </div>
          {periodEnd && (
            <p style={{ color: "var(--muted)", fontSize: 13, marginBottom: 16 }}>
              {entitlement?.cancel_at_period_end ? "Cancels" : "Renews"}: {periodEnd}
            </p>
          )}
          {tier === "free" ? (
            <Link href="/pricing" className="btn btn-gold" style={{ display: "inline-block" }}>Upgrade Plan</Link>
          ) : (
            <button className="btn btn-outline" onClick={handleManageBilling} disabled={portalLoading}>
              {portalLoading ? "Loading…" : "Manage Billing"}
            </button>
          )}
        </div>

        {/* Device (placeholder) */}
        <div className="card" style={{ marginBottom: 20 }}>
          <h2 style={{ fontSize: 18, fontWeight: 700, marginBottom: 16, color: "var(--gold)" }}>Active Device</h2>
          <p style={{ color: "var(--muted)", fontSize: 14 }}>
            Device management is coming soon. One active device is allowed per paid account.
            To transfer your account to a new device, contact support.
          </p>
        </div>

        {/* App */}
        <div className="card">
          <h2 style={{ fontSize: 18, fontWeight: 700, marginBottom: 12, color: "var(--gold)" }}>Using the App</h2>
          <p style={{ color: "var(--muted)", fontSize: 14, lineHeight: 1.6 }}>
            Open True Carry on iOS and sign in with this email address to unlock your subscription on the app.
          </p>
        </div>
      </main>

      <footer>
        <div style={{ display: "flex", gap: 24, justifyContent: "center", marginBottom: 16 }}>
          <Link href="/privacy">Privacy</Link>
          <Link href="/terms">Terms</Link>
        </div>
        © {new Date().getFullYear()} True Carry
      </footer>
    </>
  );
}
