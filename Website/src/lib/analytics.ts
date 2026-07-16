// First-party web analytics, appends events to the same Supabase
// analytics_events table the iOS app uses (platform: "web"), so the existing
// aggregate RPCs / dashboards cover the site with no extra vendor.
//
// The table's RLS policy allows anonymous inserts with a null user_id and the
// app can never read the firehose back, so this is safe to call client-side.

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

// One id per browser tab session, lets the dashboards group page flows.
let sessionId: string | null = null;
function getSessionId(): string {
  if (!sessionId) {
    sessionId =
      typeof crypto !== "undefined" && "randomUUID" in crypto
        ? crypto.randomUUID()
        : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  }
  return sessionId;
}

/** Fire-and-forget event append. Never throws, never blocks the UI. */
export function track(event: string, properties: Record<string, unknown> = {}): void {
  if (!url || !anon) return;
  try {
    const body = JSON.stringify({
      event,
      properties,
      session_id: getSessionId(),
      platform: "web",
    });
    // sendBeacon survives page navigations; fall back to fetch(keepalive).
    const endpoint = `${url}/rest/v1/analytics_events`;
    const useFetch = () =>
      fetch(endpoint, {
        method: "POST",
        keepalive: true,
        headers: {
          "Content-Type": "application/json",
          apikey: anon,
          Authorization: `Bearer ${anon}`,
          Prefer: "return=minimal",
        },
        body,
      }).catch(() => {});
    useFetch();
  } catch {
    /* telemetry must never break the site */
  }
}

/** Convenience: page_view with the current path. */
export function trackPageView(path: string): void {
  track("page_view", { path, referrer: typeof document !== "undefined" ? document.referrer : "" });
}
