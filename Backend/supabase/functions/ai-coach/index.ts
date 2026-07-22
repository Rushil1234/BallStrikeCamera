// True Carry — AI Coach Edge Function
// Deploy: cd Backend && supabase functions deploy ai-coach --project-ref aoxturoezgecwceudeef
// Secret:  supabase secrets set OPENROUTER_API_KEY=sk-or-...
//
// Called by the iOS app's AICoachService as the OPT-IN "deep read" layer (the app
// also ships a free on-device rule engine; this endpoint only fires on an explicit
// Pro tap, so tokens are spent on intent). Routes to Claude via OpenRouter — the key
// stays server-side. Modes: shot / session / round / bag.
//
// Differentiator vs. swing-video coaches (e.g. SneakySwing/Perflection): True Carry
// feeds the model PRECISE MEASURED ball+club data plus on-course round context and
// per-club baselines, so the coaching is data-grounded, longitudinal, and connects
// range work to scoring — things a pure video app can't do.

import { createClient } from "npm:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const OPENROUTER_KEY = Deno.env.get("OPENROUTER_API_KEY") ?? "";
const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

// Model routing is decided server-side so the client can't request an expensive
// model. Haiku for the quick per-shot read; Sonnet for the deeper multi-shot,
// round, and bag plans.
const MODELS: Record<string, string> = {
  shot:    "anthropic/claude-haiku-4.5",
  session: "anthropic/claude-sonnet-4.5",
  round:   "anthropic/claude-sonnet-4.5",
  bag:     "anthropic/claude-sonnet-4.5",
};

const MAX_TOKENS: Record<string, number> = {
  shot: 320, session: 550, round: 600, bag: 550,
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

// Per-club rollup the app computes on-device and sends as baseline context so the
// model can talk about gapping, dispersion, and trend — not just this instant.
type ClubStat = {
  clubName: string; count: number;
  avgCarry?: number; carrySD?: number;
  avgBall?: number; avgSmash?: number; avgLaunch?: number;
  avgSideDeg?: number; // signed: + right, - left
};

type RoundCtx = {
  courseName?: string; score?: number; toPar?: number; holes?: number;
  fairwaysHit?: number; fairwaysTotal?: number;
  gir?: number; girTotal?: number; putts?: number;
};

const SYSTEM_PROMPT =
  `You are a PGA-level golf coach embedded in True Carry, a launch-monitor app that MEASURES real \
ball and club data (carry, ball/club speed, smash, launch, spin, club path, face angle) and tracks \
rounds. You are better than a swing-video app because you reason from the golfer's ACTUAL measured \
numbers and their history, not a guess at their mechanics. Rules:
- Ground every claim in the numbers you were given. Face angle vs club path explains curve and start \
direction; smash + launch/spin explain distance and strike; carry dispersion explains consistency.
- When baseline/trend context is provided, USE it — reference gapping between clubs, whether dispersion \
is tightening, and connect range patterns to on-course scoring when round data is present.
- Name ONE primary thing to work on, say WHY in terms of the data, then give ONE concrete drill or feel.
- Tight and plain: 4-6 short sentences, no jargon dumps, no markdown headers, no invented numbers. If a \
value is missing or zero, don't mention it. Encouraging but honest.`;

function num(v: number | undefined, unit = "", digits = 0): string | null {
  if (v === undefined || v === null || Number.isNaN(v) || v === 0) return null;
  return `${v.toFixed(digits)}${unit}`;
}

function shotLine(m: Metrics): string {
  const p: string[] = [];
  const add = (label: string, v: number | undefined, unit = "", digits = 0) => {
    const s = num(v, unit, digits);
    if (s) p.push(`${label} ${s}`);
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

function clubLine(c: ClubStat): string {
  const p: string[] = [`${c.clubName} (${c.count} shot${c.count === 1 ? "" : "s"})`];
  const add = (label: string, v: number | undefined, unit = "", digits = 0) => {
    const s = num(v, unit, digits);
    if (s) p.push(`${label} ${s}`);
  };
  add("avg carry", c.avgCarry, " yd");
  add("carry ±", c.carrySD, " yd");
  add("avg ball", c.avgBall, " mph", 1);
  add("smash", c.avgSmash, "", 2);
  add("launch", c.avgLaunch, "°", 1);
  if (c.avgSideDeg !== undefined && Math.abs(c.avgSideDeg) >= 1) {
    p.push(`start ${Math.abs(c.avgSideDeg).toFixed(1)}° ${c.avgSideDeg >= 0 ? "right" : "left"}`);
  }
  return p.join(", ");
}

function roundLine(r: RoundCtx): string {
  const p: string[] = [];
  if (r.courseName) p.push(`Course: ${r.courseName}`);
  if (r.score !== undefined) {
    const tp = r.toPar === undefined ? "" : ` (${r.toPar === 0 ? "E" : r.toPar > 0 ? "+" + r.toPar : r.toPar})`;
    p.push(`Score ${r.score}${tp}${r.holes ? " over " + r.holes + " holes" : ""}`);
  }
  if (r.fairwaysHit !== undefined) p.push(`Fairways ${r.fairwaysHit}${r.fairwaysTotal ? "/" + r.fairwaysTotal : ""}`);
  if (r.gir !== undefined) p.push(`GIR ${r.gir}${r.girTotal ? "/" + r.girTotal : ""}`);
  if (r.putts !== undefined) p.push(`Putts ${r.putts}`);
  return p.join(", ");
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// Mirrors the app's UserEntitlement.effectiveTier: a paid tier only counts while
// active/trialing, and an unexpired referral comp grants Pro on top.
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
  if (!data) return false;
  const paidActive = data.payment_status === "active" || data.payment_status === "trialing";
  const baseTier = paidActive ? data.tier : "free";
  const compPro = !!data.comp_pro_until && new Date(data.comp_pro_until) > new Date();
  const effective = compPro && baseTier !== "unlimited" ? "pro" : baseTier;
  return effective === "pro" || effective === "unlimited";
}

// What the coach KNOWS about this golfer: their profile + the last few coaching notes,
// so advice is personal and longitudinal instead of one-off. Runs with the service-role
// client, scoped to this user_id — never another golfer's data.
async function fetchGolferContext(userId: string): Promise<string> {
  const parts: string[] = [];
  const { data: prof } = await supabase
    .from("profiles")
    .select("display_name, home_course_name")
    .eq("user_id", userId)
    .maybeSingle();
  if (prof?.home_course_name) parts.push(`Golfer's home course: ${prof.home_course_name}.`);

  const { data: notes } = await supabase
    .from("ai_coach_notes")
    .select("mode, context_label, summary, created_at")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(4);
  if (notes && notes.length) {
    const lines = notes.map((n) => {
      const when = new Date(n.created_at).toISOString().slice(0, 10);
      const lbl = n.context_label ? ` (${n.context_label})` : "";
      return `- ${when} ${n.mode}${lbl}: ${n.summary}`;
    });
    parts.push(
      `Your previous coaching notes for this golfer (most recent first). Build on them, ` +
      `acknowledge progress or a recurring pattern, and don't repeat yourself verbatim:\n${lines.join("\n")}`,
    );
  }
  return parts.join("\n\n");
}

// A short label stored with the saved note so the golfer's coach history is scannable.
function deriveLabel(mode: string, shots: Metrics[], round?: RoundCtx): string | null {
  switch (mode) {
    case "round":   return round?.courseName ?? "Round";
    case "bag":     return "Bag gapping";
    case "session": return "Range session";
    default:        return shots[0]?.clubName ?? "Shot";
  }
}

// Cost guard: this endpoint spends real OpenRouter credits per call, and the Pro gate alone
// wouldn't stop a Pro user (or a leaked Pro JWT) from hammering it. Cap successful reads per
// user using the saved-note timestamps — cheap (two COUNT queries) and it counts exactly the
// billed calls (errors don't save a note). Generous for real use, protective against abuse.
const RATE_PER_HOUR = 20;
const RATE_PER_DAY = 120;
async function withinRateLimit(userId: string): Promise<boolean> {
  const since = (ms: number) => new Date(Date.now() - ms).toISOString();
  const hour = await supabase.from("ai_coach_notes")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId).gte("created_at", since(3_600_000));
  if ((hour.count ?? 0) >= RATE_PER_HOUR) return false;
  const day = await supabase.from("ai_coach_notes")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId).gte("created_at", since(86_400_000));
  return (day.count ?? 0) < RATE_PER_DAY;
}

async function saveNote(userId: string, mode: string, summary: string, label: string | null) {
  // Collapse rapid re-reads of the SAME thing (e.g. the card's refresh button, or reopening a
  // shot minutes later) into one history entry — otherwise near-duplicates pile up and re-feed
  // themselves as context. A refresh within 10 min UPDATES the existing note instead of inserting.
  const tenMinAgo = new Date(Date.now() - 600_000).toISOString();
  let recentQ = supabase
    .from("ai_coach_notes")
    .select("id")
    .eq("user_id", userId)
    .eq("mode", mode)
    .gte("created_at", tenMinAgo)
    .order("created_at", { ascending: false })
    .limit(1);
  recentQ = label === null ? recentQ.is("context_label", null) : recentQ.eq("context_label", label);
  const { data: recent } = await recentQ.maybeSingle();

  if (recent?.id) {
    const { error } = await supabase
      .from("ai_coach_notes")
      .update({ summary, created_at: new Date().toISOString() })
      .eq("id", recent.id);
    if (error) console.error("saveNote update failed", error.message);
    return;
  }
  const { error } = await supabase
    .from("ai_coach_notes")
    .insert({ user_id: userId, mode, summary, context_label: label });
  if (error) console.error("saveNote insert failed", error.message); // best-effort, don't fail the request
}

function buildUserPrompt(
  mode: string,
  shots: Metrics[],
  clubs: ClubStat[],
  round: RoundCtx | undefined,
  notes: string | undefined,
): string {
  let body: string;
  switch (mode) {
    case "session":
      body = `Here are my recent range shots. Find my main pattern (miss tendency, gapping, or strike) ` +
        `and give me a short practice plan.\n\n${shots.map((s, i) => `Shot ${i + 1}: ${shotLine(s)}`).join("\n")}`;
      break;
    case "round":
      body = `I just finished a round. Read the round and my shots, connect any ball-striking pattern to ` +
        `the scoring, and give me the ONE thing to practice before next time.\n\n` +
        (round ? `Round: ${roundLine(round)}\n\n` : "") +
        (shots.length ? `Shots this round:\n${shots.map((s, i) => `Shot ${i + 1}: ${shotLine(s)}`).join("\n")}` : "");
      break;
    case "bag":
      body = `Here are my per-club averages. Check my gapping (are any clubs overlapping or leaving a ` +
        `big yardage gap?), flag the least consistent club, and tell me what to work on.\n\n` +
        clubs.map((c) => `- ${clubLine(c)}`).join("\n");
      break;
    default: // shot
      body = `Coach me on this shot:\n${shotLine(shots[0])}`;
  }
  if (notes && notes.trim()) body += `\n\nContext about me: ${notes.trim()}`;
  return body;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Missing Authorization header" }, 401);
  const { data: { user }, error: authErr } = await supabase.auth.getUser(
    authHeader.replace("Bearer ", ""),
  );
  if (authErr || !user) return json({ error: "Unauthorized" }, 401);

  if (!(await hasProAccess(user.id))) {
    return json({ error: "AI Coach is a Pro feature. Upgrade to unlock coaching." }, 403);
  }
  if (!OPENROUTER_KEY) return json({ error: "AI coach is not configured yet." }, 503);
  // Rate-limit BEFORE spending any OpenRouter credits.
  if (!(await withinRateLimit(user.id))) {
    return json({ error: "You've reached the AI Coach limit for now — try again a little later." }, 429);
  }

  let body: { mode?: string; shots?: Metrics[]; clubs?: ClubStat[]; round?: RoundCtx; notes?: string; contextLabel?: string };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON body" }, 400); }

  const mode = ["session", "round", "bag"].includes(body.mode ?? "") ? body.mode! : "shot";
  const shots = Array.isArray(body.shots) ? body.shots.slice(0, 60) : [];
  const clubs = Array.isArray(body.clubs) ? body.clubs.slice(0, 16) : [];

  // Each mode needs its own minimum data.
  const hasData = mode === "bag" ? clubs.length > 0
    : mode === "round" ? (shots.length > 0 || !!body.round)
    : shots.length > 0;
  if (!hasData) return json({ error: "No data provided" }, 400);

  let userPrompt = buildUserPrompt(mode, shots, clubs, body.round, body.notes);
  const golferContext = await fetchGolferContext(user.id);
  if (golferContext) userPrompt += `\n\n--- What you know about this golfer ---\n${golferContext}`;

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
      max_tokens: MAX_TOKENS[mode] ?? 400,
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
    // Map the common upstream failures to clearer guidance. 402 = the OpenRouter key is out
    // of credit / over its spend cap; 429 = upstream rate limit.
    const msg = orRes.status === 402
      ? "The AI Coach is temporarily unavailable (out of credits). Please try again later."
      : orRes.status === 429
      ? "The AI Coach is busy right now — give it a few seconds and try again."
      : "Coaching is unavailable right now. Try again in a moment.";
    return json({ error: msg }, 502);
  }

  const data = await orRes.json();
  const coaching = data?.choices?.[0]?.message?.content?.trim();
  if (!coaching) return json({ error: "No coaching returned." }, 502);

  // Persist the summary with the golfer's profile so it feeds future context and their
  // coach history. Best-effort — a save failure must not fail the coaching response.
  const label = (body.contextLabel && body.contextLabel.trim()) || deriveLabel(mode, shots, body.round);
  await saveNote(user.id, mode, coaching, label);

  return json({ coaching, mode, saved: true });
});
