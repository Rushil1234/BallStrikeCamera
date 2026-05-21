import { createClient, SupabaseClient } from "@supabase/supabase-js";

let _client: SupabaseClient | null = null;

function getClient(): SupabaseClient {
  if (!_client) {
    const url  = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    if (!url || !anon) throw new Error("Supabase env vars not set");
    _client = createClient(url, anon);
  }
  return _client;
}

export const supabase = new Proxy({} as SupabaseClient, {
  get(_target, prop) {
    return (getClient() as unknown as Record<string | symbol, unknown>)[prop];
  },
});

export async function getSession() {
  const { data } = await supabase.auth.getSession();
  return data.session;
}

export async function getCurrentUser() {
  const { data } = await supabase.auth.getUser();
  return data.user;
}

export async function getUserEntitlement(userId: string) {
  const { data } = await supabase
    .from("user_entitlements")
    .select("*")
    .eq("user_id", userId)
    .maybeSingle();
  return data;
}

type RecordRow = Record<string, unknown>;

export interface AccountProfile {
  display_name: string;
  handedness: string;
  distance_unit: string;
  speed_unit: string;
  home_course_name: string;
  profile_image_path: string | null;
}

export interface AccountClub {
  id: string;
  name: string;
  type: string;
  expected_carry_yards: number;
  expected_total_yards: number;
  shot_count: number;
  is_active: boolean;
  sort_order: number;
}

export interface AccountDevice {
  id: string;
  device_name: string;
  platform: string;
  app_version: string;
  last_seen_at: string;
  is_active: boolean;
}

export interface AccountUsageDay {
  date: string;
  range_shots: number;
  sim_shots: number;
  course_rounds: number;
}

export interface RecentActivity {
  id: string;
  type: "shot" | "range" | "sim" | "round";
  title: string;
  detail: string;
  metric: string;
  timestamp: string;
}

export interface AccountDashboard {
  profile: AccountProfile | null;
  clubs: AccountClub[];
  devices: AccountDevice[];
  usage: AccountUsageDay[];
  totals: {
    shots: number;
    rangeSessions: number;
    simSessions: number;
    courseRounds: number;
    activeClubs: number;
    avgCarry: number | null;
    bestCarry: number | null;
  };
  recentActivity: RecentActivity[];
}

export async function getAccountDashboard(userId: string): Promise<AccountDashboard> {
  const [
    profileResult,
    clubsResult,
    devicesResult,
    usageResult,
    shotsResult,
    rangeResult,
    simResult,
    roundsResult,
  ] = await Promise.all([
    supabase.from("profiles").select("*").eq("user_id", userId).maybeSingle(),
    supabase.from("clubs").select("*").eq("user_id", userId).order("sort_order", { ascending: true }),
    supabase.from("user_devices").select("*").eq("user_id", userId).order("last_seen_at", { ascending: false }),
    supabase.from("usage_counters").select("*").eq("user_id", userId).order("date", { ascending: false }).limit(14),
    supabase.from("shots").select("*", { count: "exact" }).eq("user_id", userId).order("timestamp", { ascending: false }).limit(100),
    supabase.from("range_sessions").select("*", { count: "exact" }).eq("user_id", userId).order("started_at", { ascending: false }).limit(12),
    supabase.from("sim_sessions").select("*", { count: "exact" }).eq("user_id", userId).order("started_at", { ascending: false }).limit(12),
    supabase.from("course_rounds").select("*", { count: "exact" }).eq("user_id", userId).order("started_at", { ascending: false }).limit(12),
  ]);

  const shots = (shotsResult.data ?? []) as RecordRow[];
  const rangeSessions = (rangeResult.data ?? []) as RecordRow[];
  const simSessions = (simResult.data ?? []) as RecordRow[];
  const rounds = (roundsResult.data ?? []) as RecordRow[];
  const carryValues = shots
    .map((shot) => numberFromPath(payloadFor(shot), ["metrics", "carryYards"]))
    .filter((value): value is number => typeof value === "number" && Number.isFinite(value) && value > 0);

  const recentActivity = [
    ...shots.slice(0, 8).map(activityFromShot),
    ...rangeSessions.slice(0, 4).map(activityFromRangeSession),
    ...simSessions.slice(0, 4).map(activityFromSimSession),
    ...rounds.slice(0, 4).map(activityFromRound),
  ]
    .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime())
    .slice(0, 10);

  return {
    profile: (profileResult.data as AccountProfile | null) ?? null,
    clubs: ((clubsResult.data ?? []) as AccountClub[]).filter((club) => club.is_active),
    devices: (devicesResult.data ?? []) as AccountDevice[],
    usage: (usageResult.data ?? []) as AccountUsageDay[],
    totals: {
      shots: shotsResult.count ?? shots.length,
      rangeSessions: rangeResult.count ?? rangeSessions.length,
      simSessions: simResult.count ?? simSessions.length,
      courseRounds: roundsResult.count ?? rounds.length,
      activeClubs: ((clubsResult.data ?? []) as AccountClub[]).filter((club) => club.is_active).length,
      avgCarry: carryValues.length ? Math.round(avg(carryValues)) : null,
      bestCarry: carryValues.length ? Math.round(Math.max(...carryValues)) : null,
    },
    recentActivity,
  };
}

function activityFromShot(row: RecordRow): RecentActivity {
  const payload = payloadFor(row);
  const club = textFromPath(payload, ["clubName"]) || "Shot";
  const carry = numberFromPath(payload, ["metrics", "carryYards"]);
  const ballSpeed = numberFromPath(payload, ["metrics", "ballSpeedMph"]);

  return {
    id: String(row.id),
    type: "shot",
    title: `${club}`,
    detail: ballSpeed ? `${Math.round(ballSpeed)} mph ball speed` : "Launch monitor capture",
    metric: carry ? `${Math.round(carry)} yd` : "Saved",
    timestamp: String(row.timestamp ?? textFromPath(payload, ["timestamp"]) ?? new Date().toISOString()),
  };
}

function activityFromRangeSession(row: RecordRow): RecentActivity {
  const payload = payloadFor(row);
  const summary = objectFromPath(payload, ["summary"]);
  const shotCount = numberFromPath(summary, ["shotCount"]) ?? (arrayFromPath(payload, ["shotIds"])?.length ?? 0);
  const avgCarry = numberFromPath(summary, ["avgCarry"]);

  return {
    id: String(row.id),
    type: "range",
    title: "Range session",
    detail: `${shotCount} shot${shotCount === 1 ? "" : "s"}`,
    metric: avgCarry ? `${Math.round(avgCarry)} yd avg` : "Practice",
    timestamp: String(row.started_at ?? textFromPath(payload, ["startedAt"]) ?? new Date().toISOString()),
  };
}

function activityFromSimSession(row: RecordRow): RecentActivity {
  const payload = payloadFor(row);
  const provider = textFromPath(payload, ["provider"]) || "Simulator";
  const shotCount = arrayFromPath(payload, ["shotIds"])?.length ?? 0;

  return {
    id: String(row.id),
    type: "sim",
    title: `${provider} session`,
    detail: `${shotCount} shot${shotCount === 1 ? "" : "s"} logged`,
    metric: "Sim",
    timestamp: String(row.started_at ?? textFromPath(payload, ["startedAt"]) ?? new Date().toISOString()),
  };
}

function activityFromRound(row: RecordRow): RecentActivity {
  const payload = payloadFor(row);
  const summary = objectFromPath(payload, ["scoreSummary"]);
  const score = numberFromPath(summary, ["totalScore"]);
  const par = numberFromPath(summary, ["totalPar"]);
  const course = textFromPath(payload, ["courseName"]) || "Course round";

  return {
    id: String(row.id),
    type: "round",
    title: course,
    detail: par ? `Par ${par}` : "On-course round",
    metric: score ? `${score}` : "Round",
    timestamp: String(row.started_at ?? textFromPath(payload, ["startedAt"]) ?? new Date().toISOString()),
  };
}

function payloadFor(row: RecordRow): RecordRow {
  if (row.payload && typeof row.payload === "object") return row.payload as RecordRow;
  return row;
}

function objectFromPath(source: unknown, path: string[]): RecordRow {
  const value = valueFromPath(source, path);
  return value && typeof value === "object" && !Array.isArray(value) ? (value as RecordRow) : {};
}

function arrayFromPath(source: unknown, path: string[]): unknown[] | null {
  const value = valueFromPath(source, path);
  return Array.isArray(value) ? value : null;
}

function textFromPath(source: unknown, path: string[]): string | null {
  const value = valueFromPath(source, path);
  return typeof value === "string" && value.trim() ? value : null;
}

function numberFromPath(source: unknown, path: string[]): number | null {
  const value = valueFromPath(source, path);
  return typeof value === "number" ? value : null;
}

function valueFromPath(source: unknown, path: string[]): unknown {
  return path.reduce<unknown>((current, key) => {
    if (!current || typeof current !== "object") return undefined;
    return (current as RecordRow)[key];
  }, source);
}

function avg(values: number[]) {
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}
