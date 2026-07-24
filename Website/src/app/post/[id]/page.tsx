import Link from "next/link";
import type { Metadata } from "next";
import { supabase } from "@/lib/supabase";

// Public share-link landing page for a shared post (truecarry.golf/post/<id>).
// Server-rendered so links get real Open Graph previews. Reads ONLY the public,
// RLS-safe projection (public_post RPC) — private / friends-only posts resolve to
// the "unavailable" state, never leaking content.
export const dynamic = "force-dynamic";

interface PublicPost {
  author_id: string | null;
  author_name: string | null;
  title: string | null;
  subtitle: string | null;
  kind: string | null;
  metric_highlight: string | null;
  created_at: string | null;
}

async function fetchPost(id: string): Promise<PublicPost | null> {
  try {
    const { data, error } = await supabase.rpc("public_post", { pid: id });
    if (error || !data || (Array.isArray(data) && data.length === 0)) return null;
    return (Array.isArray(data) ? data[0] : data) as PublicPost;
  } catch {
    return null;
  }
}

function kindLabel(kind: string | null): string {
  switch (kind) {
    case "round":       return "Round";
    case "session":     return "Practice session";
    case "shot":        return "Shot";
    case "achievement": return "Achievement";
    default:            return "Activity";
  }
}

export async function generateMetadata({ params }: { params: Promise<{ id: string }> }): Promise<Metadata> {
  const { id } = await params;
  const post = await fetchPost(id);
  if (!post) return { title: "True Carry", description: "Launch-monitor golf, in your pocket." };
  const who = post.author_name || "A golfer";
  const title = `${who}: ${post.title ?? "True Carry activity"}`;
  const desc = [post.metric_highlight, post.subtitle].filter(Boolean).join(" · ") || "Shared from True Carry.";
  return {
    title,
    description: desc,
    openGraph: { title, description: desc, type: "article" },
    twitter: { card: "summary_large_image", title, description: desc },
  };
}

export default async function PostPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const post = await fetchPost(id);
  const appLink = `truecarry://post/${id}`;

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
            <span className="auth-kicker">Shared activity</span>
            <h1>{post ? `${post.author_name || "A golfer"}’s activity` : "Post unavailable"}</h1>
            <p>
              {post
                ? "Shared from True Carry — the launch-monitor golf app that measures every shot."
                : "This post is private, shared with friends only, or no longer available."}
            </p>
          </div>

          <div className="auth-card">
            {post ? (
              <>
                <div className="auth-card-head">
                  <span className="auth-card-label">{kindLabel(post.kind)}</span>
                  <h2>{post.title || "True Carry activity"}</h2>
                </div>
                {post.metric_highlight && (
                  <div style={{ fontSize: 36, fontWeight: 800, color: "var(--gold)", fontFamily: "var(--font-mono)", margin: "4px 0 8px" }}>
                    {post.metric_highlight}
                  </div>
                )}
                {post.subtitle && (
                  <p style={{ color: "var(--muted)", marginTop: 0, lineHeight: 1.6 }}>{post.subtitle}</p>
                )}
                {post.author_id && (
                  <Link
                    href={`/u/${post.author_id}`}
                    style={{ display: "inline-block", marginTop: 6, color: "var(--gold)", fontWeight: 600, textDecoration: "none" }}
                  >
                    View {post.author_name || "this golfer"}’s profile →
                  </Link>
                )}
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
                  The golfer may have shared this with friends only, or it was removed.
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
