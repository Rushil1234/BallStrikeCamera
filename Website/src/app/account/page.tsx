"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { User } from "@supabase/supabase-js";
import {
  deactivateAccountClub,
  getAccountDashboard,
  getUserEntitlement,
  saveAccountClub,
  supabase,
  updateAccountProfile,
  type AccountClub,
  type AccountDashboard,
  type AccountProfile,
} from "@/lib/supabase";
import EmbeddedCheckoutPanel from "@/components/EmbeddedCheckoutPanel";
import SiteFooter from "@/components/SiteFooter";
import SiteNav from "@/components/SiteNav";

const PORTAL_URL = process.env.NEXT_PUBLIC_CUSTOMER_PORTAL_FUNCTION_URL!;
const CHECKOUT_URL = process.env.NEXT_PUBLIC_CREATE_CHECKOUT_FUNCTION_URL!;

interface Entitlement {
  tier: string;
  payment_status: string;
  current_period_end: string | null;
  cancel_at_period_end: boolean;
  stripe_customer_id: string | null;
  comp_pro_until: string | null;
}

export default function AccountPage() {
  const [user, setUser] = useState<User | null>(null);
  const [entitlement, setEntitlement] = useState<Entitlement | null>(null);
  const [dashboard, setDashboard] = useState<AccountDashboard | null>(null);
  const [loading, setLoading] = useState(true);
  const [checkoutLoading, setCheckoutLoading] = useState(false);
  const [checkoutToken, setCheckoutToken] = useState<string | null>(null);
  const [portalLoading, setPortalLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const router = useRouter();

  const loadAccount = useCallback(async () => {
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user) {
      router.push("/login?redirect=/account");
      return;
    }

    const ent = (await getUserEntitlement(user.id)) as Entitlement | null;
    // The locker (profile, bag, devices) is available on every tier;
    // only the analytics sections are premium-gated at render time.
    const accountData = await getAccountDashboard(user.id);

    setUser(user);
    setEntitlement(ent);
    setDashboard(accountData);
    setLoading(false);
  }, [router]);

  useEffect(() => {
    loadAccount().catch((err: unknown) => {
      setError(err instanceof Error ? err.message : "Unable to load account data");
      setLoading(false);
    });
  }, [loadAccount]);

  const [exporting, setExporting] = useState(false);
  const [deleting, setDeleting] = useState(false);

  async function handleExportData() {
    setError(null);
    setExporting(true);
    try {
      const { data, error: rpcErr } = await supabase.rpc("export_my_data");
      if (rpcErr) throw rpcErr;
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = "truecarry-data-export.json";
      a.click();
      URL.revokeObjectURL(a.href);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Export failed");
    } finally {
      setExporting(false);
    }
  }

  async function handleDeleteAccount() {
    if (!window.confirm(
      "Delete your TrueCarry account and ALL data (sessions, shots, bag, billing profile)? This cannot be undone."
    )) return;
    setError(null);
    setDeleting(true);
    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) throw new Error("Not signed in");
      const base = process.env.NEXT_PUBLIC_SUPABASE_URL;
      const res = await fetch(`${base}/functions/v1/delete-account`, {
        method: "POST",
        headers: { Authorization: `Bearer ${session.access_token}` },
      });
      if (!res.ok) throw new Error(`Deletion failed (${res.status})`);
      await supabase.auth.signOut();
      window.location.href = "/";
    } catch (e) {
      setError(e instanceof Error ? e.message : "Deletion failed");
      setDeleting(false);
    }
  }

  async function handleManageBilling() {
    setError(null);
    setPortalLoading(true);
    try {
      const {
        data: { session },
      } = await supabase.auth.getSession();
      if (!session) throw new Error("Not signed in");

      const res = await fetch(PORTAL_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${session.access_token}`,
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

  async function handleUpgrade() {
    setError(null);
    setCheckoutLoading(true);
    try {
      const {
        data: { session },
      } = await supabase.auth.getSession();
      if (!session) {
        router.push("/login?redirect=/account");
        return;
      }

      setCheckoutToken(session.access_token);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Could not start checkout.");
    } finally {
      setCheckoutLoading(false);
    }
  }

  async function handleSignOut() {
    await supabase.auth.signOut();
    router.push("/");
  }

  function handleCloseCheckout() {
    setCheckoutToken(null);
    loadAccount().catch((err: unknown) => {
      setError(err instanceof Error ? err.message : "Unable to refresh account data");
    });
  }

  if (loading) {
    return (
      <>
        <SiteNav actions={<Link href="/#pricing">Pricing</Link>} />
        <main className="account-shell">
          <div className="account-loading">Loading your True Carry profile...</div>
        </main>
      </>
    );
  }

  const tier = entitlement?.tier ?? "free";
  const tierDisplay = tier.charAt(0).toUpperCase() + tier.slice(1);
  const premium = hasPremiumAccess(entitlement);
  const profile = dashboard?.profile;
  const displayName = profile?.display_name || user?.email?.split("@")[0] || "Golfer";
  const periodEnd = entitlement?.current_period_end
    ? new Date(entitlement.current_period_end).toLocaleDateString(undefined, {
        year: "numeric",
        month: "long",
        day: "numeric",
      })
    : null;
  const compUntil = entitlement?.comp_pro_until && new Date(entitlement.comp_pro_until) > new Date()
    ? new Date(entitlement.comp_pro_until).toLocaleDateString(undefined, { year: "numeric", month: "long", day: "numeric" })
    : null;

  return (
    <>
      <SiteNav
        actions={
          <>
            <Link href="/#pricing">Pricing</Link>
            <button onClick={handleSignOut} className="btn btn-muted" style={{ fontSize: 14, padding: "9px 20px" }}>
              Sign Out
            </button>
          </>
        }
      />

      <main className="account-shell">
        <section className="account-hero">
          <div>
            <span className="eyebrow">Player account</span>
            <h1>{displayName}</h1>
            <p>
              Your subscription, player profile, bag, practice history, device status, and round activity in one
              professional-grade command center.
            </p>
          </div>

          <div className="account-status-card">
            <span className={`badge ${premium ? "badge-sage" : ""}`}>{tierDisplay} plan</span>
            <strong>{premium ? "Premium access active" : "Free access"}</strong>
            <span>
              {premium && !entitlement?.stripe_customer_id && periodEnd
                ? `Complimentary through ${periodEnd}`
                : periodEnd
                ? `${entitlement?.cancel_at_period_end ? "Cancels" : "Renews"} ${periodEnd}`
                : compUntil
                ? `Referral Pro until ${compUntil}`
                : "Billing status syncs after checkout completes."}
            </span>
            {premium && !entitlement?.stripe_customer_id ? (
              /* Complimentary/special accounts have no Stripe objects — the billing
                 portal 400s ("Please subscribe first") and funnels them into checkout.
                 There is nothing to manage or cancel; say so instead. */
              <span className="account-renewal-note">
                Complimentary access{periodEnd ? ` — active through ${periodEnd}` : ""}. No
                billing to manage.
              </span>
            ) : premium ? (
              <>
                <button className="btn btn-outline" onClick={handleManageBilling} disabled={portalLoading}>
                  {portalLoading ? "Opening..." : "Manage Billing"}
                </button>
                <button className="locker-link-btn" onClick={handleManageBilling} disabled={portalLoading}>
                  Cancel subscription
                </button>
                <span className="account-renewal-note">
                  Your plan renews automatically until you cancel. Cancel anytime, you keep
                  access through the end of the paid period, no fees.
                </span>
              </>
            ) : (
              <button className="btn btn-gold" onClick={handleUpgrade} disabled={checkoutLoading}>
                {checkoutLoading ? "Preparing checkout..." : "Upgrade to Premium"}
              </button>
            )}
          </div>
        </section>

        {error && <p className="error-msg account-error">{error}</p>}

        {user && <ReferralCard userId={user.id} />}

        {user && (
          <section className="card account-privacy-card" aria-labelledby="privacy-rights-h">
            <h2 id="privacy-rights-h">Privacy &amp; your data</h2>
            <p className="account-privacy-copy">
              Your data belongs to you. Export everything we hold, or delete your account
              and all of it, no email required, effective immediately.
            </p>
            <div className="account-privacy-actions">
              <button className="btn btn-outline" onClick={handleExportData} disabled={exporting}>
                {exporting ? "Preparing..." : "Download my data"}
              </button>
              <button className="btn btn-danger" onClick={handleDeleteAccount} disabled={deleting}>
                {deleting ? "Deleting..." : "Delete my account"}
              </button>
            </div>
          </section>
        )}

        {dashboard && user ? (
          <LockerDashboard
            dashboard={dashboard}
            userId={user.id}
            userEmail={user.email ?? ""}
            premium={premium}
            onChanged={loadAccount}
            onUpgrade={handleUpgrade}
            upgradeLoading={checkoutLoading}
          />
        ) : (
          <div className="card">No app data was found for this account yet.</div>
        )}
      </main>

      <SiteFooter />

      {checkoutToken && (
        <EmbeddedCheckoutPanel
          accessToken={checkoutToken}
          checkoutUrl={CHECKOUT_URL}
          onClose={handleCloseCheckout}
        />
      )}
    </>
  );
}

function makeInviteCode() {
  // 12 hex chars (~48 bits), matches the iOS generator.
  const bytes = crypto.getRandomValues(new Uint8Array(6));
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("").toUpperCase();
}

function ReferralCard({ userId }: { userId: string }) {
  const [code, setCode] = useState<string | null>(null);
  const [referred, setReferred] = useState(0);
  const [copied, setCopied] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const { data: existing } = await supabase
          .from("invite_codes").select("code").eq("user_id", userId)
          .order("created_at", { ascending: true }).limit(1).maybeSingle();
        let c = existing?.code as string | undefined;
        if (!c) {
          c = makeInviteCode();
          const { error } = await supabase.from("invite_codes").insert({ code: c, user_id: userId });
          if (error) {
            const { data: re } = await supabase.from("invite_codes").select("code").eq("user_id", userId).limit(1).maybeSingle();
            c = (re?.code as string | undefined) ?? c;
          }
        }
        const { count } = await supabase
          .from("referrals").select("*", { count: "exact", head: true }).eq("referrer_id", userId);
        if (!cancelled) { setCode(c ?? null); setReferred(count ?? 0); }
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, [userId]);

  async function copy() {
    if (!code) return;
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      /* clipboard may be blocked */
    }
  }

  return (
    <div className="card account-panel referral-card">
      <div className="panel-head">
        <div>
          <span className="badge">Invite friends</span>
          <h2>Give 14 days, get 14 days</h2>
        </div>
        {referred > 0 && <span className="account-pill">{referred} referred</span>}
      </div>
      <p className="referral-copy">
        Share your invite code. When a friend joins True Carry and enters it in the app,
        you <strong>both</strong> get 14 days of Pro, free.
      </p>
      <div className="referral-code-row">
        <code className="referral-code">{loading ? "…" : code ?? ", "}</code>
        <button type="button" className="device-remove" onClick={copy} disabled={!code}>
          {copied ? "Copied" : "Copy code"}
        </button>
      </div>
    </div>
  );
}

function DevicesPanel({ devices, onChanged }: { devices: AccountDashboard["devices"]; onChanged: () => void }) {
  const [removing, setRemoving] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);

  async function removeDevice(id: string) {
    setErr(null);
    setRemoving(id);
    try {
      const { error } = await supabase.from("user_devices").delete().eq("id", id);
      if (error) throw error;
      onChanged();
    } catch (e: unknown) {
      setErr(e instanceof Error ? e.message : "Could not remove device.");
    } finally {
      setRemoving(null);
    }
  }

  return (
    <div className="card account-panel">
      <div className="panel-head">
        <div>
          <span className="badge">Devices</span>
          <h2>Signed-in devices</h2>
        </div>
        <span className="account-pill">{devices.length} of 2</span>
      </div>
      {err && <p className="error-msg" style={{ marginBottom: 12 }}>{err}</p>}
      {devices.length === 0 ? (
        <div className="device-card">
          <strong>No device registered</strong>
          <span>Open the iOS app and sign in to register this account.</span>
        </div>
      ) : (
        <div className="device-list">
          {devices.map((d) => (
            <div className="device-row" key={d.id}>
              <div>
                <strong>{d.device_name || "Unnamed device"}</strong>
                <span>{d.platform} · {d.app_version || "app version unknown"}</span>
                <small>Last seen {formatDate(d.last_seen_at)}</small>
              </div>
              <button type="button" className="device-remove" onClick={() => removeDevice(d.id)} disabled={removing === d.id}>
                {removing === d.id ? "Removing…" : "Remove"}
              </button>
            </div>
          ))}
        </div>
      )}
      <p className="device-hint">Each account can be active on up to 2 devices. Remove one here to free a slot for a new phone or tablet.</p>
    </div>
  );
}

function LockerDashboard({
  dashboard,
  userId,
  userEmail,
  premium,
  onChanged,
  onUpgrade,
  upgradeLoading,
}: {
  dashboard: AccountDashboard;
  userId: string;
  userEmail: string;
  premium: boolean;
  onChanged: () => void;
  onUpgrade: () => void;
  upgradeLoading: boolean;
}) {
  const usageTotal = dashboard.usage.reduce(
    (sum, day) => sum + day.range_shots + day.sim_shots + day.course_rounds,
    0
  );

  return (
    <>
      {premium && (
        <section className="account-kpis">
          <MetricCard label="Saved shots" value={dashboard.totals.shots} detail="Camera captures synced from iOS" />
          <MetricCard label="Avg carry" value={dashboard.totals.avgCarry ?? ", "} suffix={dashboard.totals.avgCarry ? "yd" : ""} detail="Recent tracked shots" />
          <MetricCard label="Best carry" value={dashboard.totals.bestCarry ?? ", "} suffix={dashboard.totals.bestCarry ? "yd" : ""} detail="Best synced carry number" />
          <MetricCard label="Rounds" value={dashboard.totals.courseRounds} detail="Course mode scorecards" />
        </section>
      )}

      <section className="account-grid">
        <ProfilePanel profile={dashboard.profile} userId={userId} userEmail={userEmail} onChanged={onChanged} />

        <DevicesPanel devices={dashboard.devices} onChanged={onChanged} />

        <BagPanel clubs={dashboard.clubs} userId={userId} onChanged={onChanged} />

        {!premium && (
          <div className="card account-panel account-panel-wide account-lock">
            <span className="badge">Premium analytics</span>
            <h2>Shot history, usage, and activity unlock with Premium.</h2>
            <p>
              Your profile, bag, and devices are always available. Upgrade to see synced shot
              history, carry analytics, 14-day usage, and round activity here.
            </p>
            <div className="account-lock-row">
              <span>{userEmail}</span>
              <button className="btn btn-gold" onClick={onUpgrade} disabled={upgradeLoading}>
                {upgradeLoading ? "Preparing checkout..." : "Upgrade to Premium"}
              </button>
            </div>
          </div>
        )}

        {premium && (
        <div className="card account-panel">
          <div className="panel-head">
            <div>
              <span className="badge">Usage</span>
              <h2>Last 14 days</h2>
            </div>
            <span className="account-pill">{usageTotal} actions</span>
          </div>
          {dashboard.usage.length ? (
            <div className="usage-stack">
              {dashboard.usage.slice(0, 7).map((day) => (
                <div className="usage-row" key={day.date}>
                  <span>{formatShortDate(day.date)}</span>
                  <strong>{day.range_shots + day.sim_shots + day.course_rounds}</strong>
                  <small>{day.range_shots} range · {day.sim_shots} sim · {day.course_rounds} rounds</small>
                </div>
              ))}
            </div>
          ) : (
            <EmptyState title="No recent usage" body="Your daily usage counters will fill in as the app records shots and rounds." />
          )}
        </div>
        )}

        {premium && (
        <div className="card account-panel account-panel-wide">
          <div className="panel-head">
            <div>
              <span className="badge">Activity</span>
              <h2>Latest from the app</h2>
            </div>
          </div>
          {dashboard.recentActivity.length ? (
            <div className="activity-list">
              {dashboard.recentActivity.map((item) => (
                <div className="activity-row" key={`${item.type}-${item.id}`}>
                  <span className={`activity-dot activity-${item.type}`} />
                  <div>
                    <strong>{item.title}</strong>
                    <span>{item.detail} · {formatDate(item.timestamp)}</span>
                  </div>
                  <b>{item.metric}</b>
                </div>
              ))}
            </div>
          ) : (
            <EmptyState title="No shots or rounds yet" body="Once your iPhone syncs practice, sim, or course activity, it will land here." />
          )}
        </div>
        )}
      </section>
    </>
  );
}

function ProfilePanel({
  profile,
  userId,
  userEmail,
  onChanged,
}: {
  profile: AccountProfile | null;
  userId: string;
  userEmail: string;
  onChanged: () => void;
}) {
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [displayName, setDisplayName] = useState(profile?.display_name ?? "");
  const [handedness, setHandedness] = useState(profile?.handedness ?? "");
  const [homeCourse, setHomeCourse] = useState(profile?.home_course_name ?? "");

  async function save() {
    setSaving(true);
    setErr(null);
    try {
      await updateAccountProfile(userId, {
        display_name: displayName.trim(),
        handedness,
        home_course_name: homeCourse.trim(),
      });
      setEditing(false);
      onChanged();
    } catch (e: unknown) {
      setErr(e instanceof Error ? e.message : "Could not save profile");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="card account-panel account-panel-wide">
      <div className="panel-head">
        <div>
          <span className="badge">Player profile</span>
          <h2>Golf app identity</h2>
        </div>
        <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
          <span className="account-pill">{userEmail}</span>
          {!editing && (
            <button className="btn btn-outline locker-mini-btn" onClick={() => setEditing(true)}>Edit</button>
          )}
        </div>
      </div>

      {editing ? (
        <div className="locker-form">
          <label>
            Display name
            <input value={displayName} onChange={(e) => setDisplayName(e.target.value)} maxLength={40} placeholder="Your name" />
          </label>
          <label>
            Handedness
            <select value={handedness} onChange={(e) => setHandedness(e.target.value)}>
              <option value="">Not set</option>
              <option value="right">Right</option>
              <option value="left">Left</option>
            </select>
          </label>
          <label>
            Home course
            <input value={homeCourse} onChange={(e) => setHomeCourse(e.target.value)} maxLength={80} placeholder="e.g. Pebble Beach" />
          </label>
          {err && <p className="error-msg">{err}</p>}
          <div className="locker-form-actions">
            <button className="btn btn-gold locker-mini-btn" onClick={save} disabled={saving}>
              {saving ? "Saving..." : "Save"}
            </button>
            <button className="btn btn-muted locker-mini-btn" onClick={() => setEditing(false)} disabled={saving}>
              Cancel
            </button>
          </div>
        </div>
      ) : (
        <div className="profile-grid">
          <ProfileFact label="Display name" value={profile?.display_name || "Not set"} />
          <ProfileFact label="Handedness" value={profile?.handedness || "Not set"} />
          <ProfileFact label="Distance" value={profile?.distance_unit || "Yards"} />
          <ProfileFact label="Speed" value={profile?.speed_unit || "mph"} />
          <ProfileFact label="Home course" value={profile?.home_course_name || "Not set"} />
          <ProfileFact label="Profile image" value={profile?.profile_image_path ? "Uploaded" : "Not uploaded"} />
        </div>
      )}
    </div>
  );
}

const CLUB_TYPES = ["driver", "wood", "hybrid", "iron", "wedge", "putter"];

function BagPanel({ clubs, userId, onChanged }: { clubs: AccountClub[]; userId: string; onChanged: () => void }) {
  const [adding, setAdding] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function remove(clubId: string) {
    setBusy(true);
    setErr(null);
    try {
      await deactivateAccountClub(userId, clubId);
      onChanged();
    } catch (e: unknown) {
      setErr(e instanceof Error ? e.message : "Could not remove club");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="card account-panel account-panel-wide">
      <div className="panel-head">
        <div>
          <span className="badge">Club bag</span>
          <h2>Carry map</h2>
        </div>
        <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
          <span className="account-pill">{clubs.length} active clubs</span>
          {!adding && editingId === null && (
            <button className="btn btn-outline locker-mini-btn" onClick={() => setAdding(true)}>Add club</button>
          )}
        </div>
      </div>

      {err && <p className="error-msg">{err}</p>}

      {adding && (
        <ClubForm
          userId={userId}
          onDone={() => { setAdding(false); onChanged(); }}
          onCancel={() => setAdding(false)}
        />
      )}

      {clubs.length ? (
        <div className="club-table">
          {clubs.slice(0, 16).map((club) =>
            editingId === club.id ? (
              <ClubForm
                key={club.id}
                userId={userId}
                club={club}
                onDone={() => { setEditingId(null); onChanged(); }}
                onCancel={() => setEditingId(null)}
              />
            ) : (
              <div className="club-row" key={club.id}>
                <span>{club.name}</span>
                <span>{club.type}</span>
                <strong>{club.expected_carry_yards} yd carry</strong>
                <span>{club.expected_total_yards} yd total</span>
                <span className="club-row-actions">
                  <button className="locker-link-btn" onClick={() => setEditingId(club.id)} disabled={busy}>Edit</button>
                  <button className="locker-link-btn danger" onClick={() => remove(club.id)} disabled={busy}>Remove</button>
                </span>
              </div>
            )
          )}
        </div>
      ) : (
        !adding && <EmptyState title="No clubs yet" body="Add your clubs here or build your bag in the iOS app, they stay in sync." />
      )}
    </div>
  );
}

function ClubForm({
  userId,
  club,
  onDone,
  onCancel,
}: {
  userId: string;
  club?: AccountClub;
  onDone: () => void;
  onCancel: () => void;
}) {
  const [name, setName] = useState(club?.name ?? "");
  const [type, setType] = useState(club?.type ?? "iron");
  const [carry, setCarry] = useState(club ? String(club.expected_carry_yards) : "");
  const [total, setTotal] = useState(club ? String(club.expected_total_yards) : "");
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function save() {
    const carryN = Number(carry);
    const totalN = Number(total || carry);
    if (!name.trim() || !Number.isFinite(carryN) || carryN <= 0) {
      setErr("Enter a club name and a carry distance.");
      return;
    }
    setSaving(true);
    setErr(null);
    try {
      await saveAccountClub(userId, {
        id: club?.id,
        name: name.trim(),
        type,
        expected_carry_yards: Math.round(carryN),
        expected_total_yards: Math.round(Math.max(totalN, carryN)),
        sort_order: club?.sort_order,
      });
      onDone();
    } catch (e: unknown) {
      setErr(e instanceof Error ? e.message : "Could not save club");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="locker-form locker-club-form">
      <label>
        Club
        <input value={name} onChange={(e) => setName(e.target.value)} maxLength={30} placeholder="7 Iron" />
      </label>
      <label>
        Type
        <select value={type} onChange={(e) => setType(e.target.value)}>
          {CLUB_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
        </select>
      </label>
      <label>
        Carry (yd)
        <input value={carry} onChange={(e) => setCarry(e.target.value)} inputMode="numeric" placeholder="152" />
      </label>
      <label>
        Total (yd)
        <input value={total} onChange={(e) => setTotal(e.target.value)} inputMode="numeric" placeholder="160" />
      </label>
      {err && <p className="error-msg">{err}</p>}
      <div className="locker-form-actions">
        <button className="btn btn-gold locker-mini-btn" onClick={save} disabled={saving}>
          {saving ? "Saving..." : club ? "Save" : "Add"}
        </button>
        <button className="btn btn-muted locker-mini-btn" onClick={onCancel} disabled={saving}>Cancel</button>
      </div>
    </div>
  );
}

function MetricCard({ label, value, detail, suffix = "" }: { label: string; value: string | number; detail: string; suffix?: string }) {
  return (
    <div className="card metric-card">
      <span>{label}</span>
      <strong>{value}{suffix && <em>{suffix}</em>}</strong>
      <small>{detail}</small>
    </div>
  );
}

function ProfileFact({ label, value }: { label: string; value: string }) {
  return (
    <div className="profile-fact">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function EmptyState({ title, body }: { title: string; body: string }) {
  return (
    <div className="empty-state">
      <strong>{title}</strong>
      <span>{body}</span>
    </div>
  );
}

function hasPremiumAccess(entitlement: Entitlement | null) {
  if (!entitlement) return false;
  // Referral comp Pro grants access regardless of Stripe tier/status.
  if (entitlement.comp_pro_until && new Date(entitlement.comp_pro_until) > new Date()) return true;
  if (entitlement.tier === "free") return false;
  return ["active", "trialing"].includes(entitlement.payment_status);
}

function formatDate(value: string) {
  return new Date(value).toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" });
}

function formatShortDate(value: string) {
  return new Date(value).toLocaleDateString(undefined, { month: "short", day: "numeric" });
}
