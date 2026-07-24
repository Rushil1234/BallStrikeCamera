import Link from "next/link";
import type { Metadata } from "next";
import { supabase } from "@/lib/supabase";

// Public share-link landing page for a golfer's profile (truecarry.golf/u/<id>).
// Server-rendered for Open Graph previews; reads only the public_profile projection,
// which returns nothing for private accounts.
export const dynamic = "force-dynamic";

interface PublicProfile {
  display_name: string | null;
  username: string | null;
  home_course: string | null;
  follower_count: number;
  following_count: number;
}

async function fetchProfile(id: string): Promise<PublicProfile | null> {
  try {
    const { data, error } = await supabase.rpc("public_profile", { pid: id });
    if (error || !data || (Array.isArray(data) && data.length === 0)) return null;
    return (Array.isArray(data) ? data[0] : data) as PublicProfile;
  } catch {
    return null;
  }
}

function baseCourse(name: string | null): string | null {
  if (!name) return null;
  return name.split(" ~ ")[0] || name;
}

export async function generateMetadata({ params }: { params: Promise<{ id: string }> }): Promise<Metadata> {
  const { id } = await params;
  const p = await fetchProfile(id);
  if (!p) return { title: "True Carry", description: "Launch-monitor golf, in your pocket." };
  const name = p.display_name || "A golfer";
  const desc = [baseCourse(p.home_course), `${p.follower_count} followers`].filter(Boolean).join(" · ") || "On True Carry.";
  return {
    title: `${name} on True Carry`,
    description: desc,
    openGraph: { title: `${name} on True Carry`, description: desc, type: "profile" },
    twitter: { card: "summary_large_image", title: `${name} on True Carry`, description: desc },
  };
}

export default async function ProfilePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const p = await fetchProfile(id);
  const appLink = `truecarry://user/${id}`;
  const course = baseCourse(p?.home_course ?? null);

  return (
    <div className="auth-page">
      <header className="auth-nav">
        <Link href="/" className="auth-brand" aria-label="True Carry home">
          <img src="/truecarry-logo.png" alt="" aria-hidden />
          <span>True <em>Carry.</em></span>
        </Link>
      </header>

      <main className="auth-main">
        <section className="auth-panel">
          <div className="auth-copy">
            <span className="auth-kicker">Golfer profile</span>
            <h1>{p ? p.display_name || "A golfer" : "Profile unavailable"}</h1>
            <p>
              {p
                ? "Following golfers on True Carry — the launch-monitor app that measures every shot."
                : "This profile is private or no longer available."}
            </p>
          </div>

          <div className="auth-card">
            {p ? (
              <>
                <div className="auth-card-head">
                  <span className="auth-card-label">{p.username ? `@${p.username}` : "Golfer"}</span>
                  <h2>{p.display_name || "A golfer"}</h2>
                </div>
                {course && (
                  <p style={{ color: "var(--muted)", marginTop: 0 }}>🏌️ {course}</p>
                )}
                <div style={{ display: "flex", gap: 28, margin: "16px 0 4px" }}>
                  <div>
                    <div style={{ fontSize: 24, fontWeight: 800, color: "var(--cream)", fontFamily: "var(--font-mono)" }}>{p.follower_count}</div>
                    <div style={{ fontSize: 11, letterSpacing: 0.6, color: "var(--muted)", textTransform: "uppercase" }}>Followers</div>
                  </div>
                  <div>
                    <div style={{ fontSize: 24, fontWeight: 800, color: "var(--cream)", fontFamily: "var(--font-mono)" }}>{p.following_count}</div>
                    <div style={{ fontSize: 11, letterSpacing: 0.6, color: "var(--muted)", textTransform: "uppercase" }}>Following</div>
                  </div>
                </div>
                <a className="auth-submit" href={appLink} style={{ display: "block", textAlign: "center", marginTop: 18, textDecoration: "none" }}>
                  Open in the True Carry app
                </a>
                <Link href="/#pricing" className="auth-switch" style={{ display: "block", textAlign: "center", marginTop: 14 }}>
                  Don’t have the app? Get True Carry →
                </Link>
              </>
            ) : (
              <>
                <p className="auth-switch" style={{ marginTop: 0 }}>
                  This golfer’s profile is private, or the link is no longer valid.
                </p>
                <Link href="/#pricing" className="auth-submit" style={{ display: "block", textAlign: "center", marginTop: 12, textDecoration: "none" }}>
                  Get True Carry
                </Link>
              </>
            )}
          </div>
        </section>
      </main>
    </div>
  );
}
