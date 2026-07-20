// True Carry — AI Coach Edge Function
// Deploy: supabase functions deploy ai-coach
// Secret:  supabase secrets set OPENROUTER_API_KEY=sk-or-...
//
// Called by: the iOS app's AICoachService. Takes a shot's launch-monitor
// metrics (or a set of recent shots) and returns short, specific coaching via
// Claude, routed through OpenRouter. The OpenRouter key stays server-side and is
// never exposed to the client. Gated to authenticated Pro/Unlimited users —
// the tier check runs HERE (mirroring the app's effectiveTier logic) so a
// non-Pro caller with a valid JWT can't hit the paid model directly.

import { createClient } from "npm:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const OPENROUTER_KEY = Deno.env.get("OPENROUTER_API_KEY") ?? "";
const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

// Model routing is decided server-side so the client can't request an expensive
// model. Haiku for the quick per-shot read; Sonnet for the deeper session plan.
const MODELS: Record<string, string> = {
  shot:    "anthropic/claude-haiku-4.5",
  session: "anthropic/claude-sonnet-4.5",
};

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, content-type",
};

type Metrics = {
  clubName?: string;
  carryYards?: number; totalYards?: number; rolloutYards?: number;
  ballSpeedMph?: number; clubSpeedMph?: number; smashFactor?: number;
  hlaDegrees?: number; hlaDirection?: string; vlaDegrees?: number;
  backspinRpm?: number; sidespinRpm?: number; spinAxisDegrees?: number;
  clubPathDegrees?: number; faceAngleDegrees?: number; faceToPathDegrees?: number;
};

const SYSTEM_PROMPT = `You are a PGA-level golf coach embedded in the True Carry launch-monitor app. \
You receive precise ball- and club-data for a shot (or a set of recent shots) and give the golfer \
short, concrete, encouraging coaching. Rules:
- Read the numbers like a coach: face angle vs club path explains curve and start direction; \
smash factor and launch/spin explain distance and strike quality.
- Be specific and actionable. Name ONE primary thing to work on, then one drill or feel to try.
- Keep it tight: 3-5 short sentences, plain English, no jargon dumps. Assume a beginner-to-intermediate golfer.
- Never invent numbers you weren't given. If a value is missing or zero, don't comment on it.
- Encouraging but honest. No hedging, no filler, no markdown headers.`;

function shotLine(m: Metrics): string {
  const p: string[] = [];
  const add = (label: string, v: number | undefined, unit = "", digits = 0) => {
    if (v !== undefined && v !== null && !Number.isNaN(v) && v !== 0)
      p.push(`${label} ${v.toFixed(digits)}${unit}`);
  };
  if (m.clubName) p.push(`Club: ${m.clubName}`);
  add("Carry", m.carryYards, " yd");
  add("Total", m.totalYards, " yd");
  add("Ball speed", m.ballSpeedMph, " mph", 1);
  add("Club speed", m.clubSpeedMph, " mph", 1);
  add("Smash", m.smashFactor, "", 2);
  add("Launch (VLA)", m.vlaDegrees, "°", 1);
  if (m.hlaDegrees) p.push(`Start dir ${m.hlaDegrees.toFixed(1)}° ${m.hlaDirection ?? ""}`.trim());
  add("Backspin", m.backspinRpm, " rpm");
  add("Sidespin", m.sidespinRpm, " rpm");
  add("Club path", m.clubPathDegrees, "°", 1);
  add("Face angle", m.faceAngleDegrees, "°", 1);
  add("Face-to-path", m.faceToPathDegrees, "°", 1);
  return p.join(", ");
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// Mirrors the app's UserEntitlement.effectiveTier: a paid tier only counts while
// the subscription is active/trialing, and an unexpired referral comp grants
// Pro-level access on top. Coaching requires effective pro or unlimited.
async function hasProAccess(userId: string): Promise<boolean> {
  const { data, error } = await supabase
    .from("user_entitlements")
    .select("tier, payment_status, comp_pro_until")
    .eq("user_id", userId)
    .maybeSingle();
  if (error) {
    console.error("entitlement lookup failed", error.message);
    return false; // fail closed — this endpoint spends real money per call
  }
  if (!data) return false; // no entitlement row = free tier

  const paidActive = data.payment_status === "active" || data.payment_status === "trialing";
  const baseTier = paidActive ? data.tier : "free";
  const compPro = !!data.comp_pro_until && new Date(data.comp_pro_until) > new Date();
  const effective = compPro && baseTier !== "unlimited" ? "pro" : baseTier;
  return effective === "pro" || effective === "unlimited";
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  // Require an authenticated caller.
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Missing Authorization header" }, 401);
  const { data: { user }, error: authErr } = await supabase.auth.getUser(
    authHeader.replace("Bearer ", ""),
  );
  if (authErr || !user) return json({ error: "Unauthorized" }, 401);

  // Server-side Pro gate. The app hides the feature for non-Pro tiers, but a
  // valid JWT alone must not be enough to spend OpenRouter credits.
  if (!(await hasProAccess(user.id))) {
    return json({ error: "AI Coach is a Pro feature. Upgrade to unlock coaching." }, 403);
  }

  if (!OPENROUTER_KEY) return json({ error: "AI coach is not configured yet." }, 503);

  let body: { mode?: string; shots?: Metrics[] };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON body" }, 400); }

  const mode = body.mode === "session" ? "session" : "shot";
  const shots = Array.isArray(body.shots) ? body.shots.slice(0, 40) : [];
  if (shots.length === 0) return json({ error: "No shot data provided" }, 400);

  const userPrompt = mode === "session"
    ? `Here are my recent shots. Find my main pattern (miss tendency, gapping, or strike) and give me a short practice plan.\n\n${
        shots.map((s, i) => `Shot ${i + 1}: ${shotLine(s)}`).join("\n")
      }`
    : `Coach me on this shot:\n${shotLine(shots[0])}`;

  const orRes = await fetch(OPENROUTER_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${OPENROUTER_KEY}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://truecarry.app",
      "X-Title": "True Carry AI Coach",
    },
    body: JSON.stringify({
      model: MODELS[mode],
      max_tokens: mode === "session" ? 500 : 300,
      temperature: 0.6,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: userPrompt },
      ],
    }),
  });

  if (!orRes.ok) {
    const detail = await orRes.text();
    console.error("OpenRouter error", orRes.status, detail);
    return json({ error: "Coaching is unavailable right now. Try again in a moment." }, 502);
  }

  const data = await orRes.json();
  const coaching = data?.choices?.[0]?.message?.content?.trim();
  if (!coaching) return json({ error: "No coaching returned." }, 502);

  return json({ coaching, mode });
});
