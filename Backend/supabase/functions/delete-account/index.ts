// True Carry — Delete Account Edge Function
// Deploy: supabase functions deploy delete-account
// Called by: the iOS app's Settings → "Delete Account" (Apple App Store requires
// in-app account deletion). Verifies the caller's JWT, then hard-deletes the auth
// user with the service role. Every user table is ON DELETE CASCADE from
// auth.users, so profile/clubs/shots/rounds/sessions/feed/devices go with it.
// Storage objects (avatars, shot videos/frames) are removed explicitly.

import { createClient } from "npm:@supabase/supabase-js@2";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, // service role — Edge Function only
);

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, content-type",
};

const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });

async function emptyUserFolder(bucket: string, userId: string) {
  // List and remove everything under <bucket>/<userId>/... (best-effort).
  const { data, error } = await admin.storage.from(bucket).list(userId, { limit: 1000 });
  if (error || !data?.length) return;
  const paths: string[] = [];
  for (const entry of data) {
    if (entry.id === null) {
      // subfolder (e.g. shot-frames/<uid>/<shotId>/) — one level deeper
      const { data: sub } = await admin.storage.from(bucket).list(`${userId}/${entry.name}`, { limit: 1000 });
      for (const f of sub ?? []) paths.push(`${userId}/${entry.name}/${f.name}`);
    } else {
      paths.push(`${userId}/${entry.name}`);
    }
  }
  if (paths.length) await admin.storage.from(bucket).remove(paths);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  // 1) Authenticate the caller from their JWT.
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Missing Authorization header" }, 401);
  const { data: { user }, error: authErr } = await admin.auth.getUser(
    authHeader.replace("Bearer ", ""),
  );
  if (authErr || !user) return json({ error: "Unauthorized" }, 401);

  const userId = user.id;

  try {
    // 2) Audit the deletion BEFORE the cascade removes the trail owner.
    await admin.from("audit_log").insert({
      actor_id: userId,
      action: "account.deleted",
      entity: "auth.users",
      entity_id: userId,
      detail: { email: user.email },
    });

    // 3) Remove the user's storage objects (not cascaded by the DB).
    await Promise.allSettled([
      emptyUserFolder("profile-images", userId),
      emptyUserFolder("shot-videos", userId),
      emptyUserFolder("shot-frames", userId),
    ]);

    // 4) Hard-delete the auth user → cascades all owned rows.
    const { error: delErr } = await admin.auth.admin.deleteUser(userId);
    if (delErr) return json({ error: `Delete failed: ${delErr.message}` }, 500);

    return json({ deleted: true });
  } catch (err) {
    console.error("[delete-account] error:", err);
    return json({ error: "Internal error" }, 500);
  }
});
