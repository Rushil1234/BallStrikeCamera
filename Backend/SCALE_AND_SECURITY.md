# True Carry — Scale & Security Runbook

Everything needed to take the backend from launch to ~1M users / 20M shots / 50 TB video,
and the manual (dashboard / Apple / infra) steps that can't live in code.

Architecture stays the same the whole way up: **iPhone → HTTPS → PostgREST/Auth → RLS +
SECURITY DEFINER RPCs → Postgres → Storage**. The phone never manipulates trusted data
directly — RLS is the enforcement boundary and subscriptions are written only by the Stripe
webhook (service role).

---

## 1. Apply the new migrations (026–030)

Additive and idempotent. **Easiest path (no CLI):** open Supabase Dashboard → **SQL Editor** →
paste the contents of [`supabase/APPLY_IN_SQL_EDITOR.sql`](supabase/APPLY_IN_SQL_EDITOR.sql)
(all five migrations concatenated) → **Run**.

Or with the CLI:

```bash
supabase link --project-ref aoxturoezgecwceudeef
supabase db push        # applies 026..030
```

| Migration | Adds |
|-----------|------|
| `026_rate_limiting` | `rate_limits` table + `enforce_rate_limit()` + BEFORE INSERT triggers on shots/rounds/sessions/feed/friend-requests **and storage.objects** (video/frame/avatar upload caps). |
| `027_audit_log` | Append-only `audit_log` + triggers on entitlement changes and round/shot deletions; `write_audit()` for app events. |
| `028_analytics_events` | Month-partitioned `analytics_events` (insert-own, no read) + `ensure_analytics_partition()` + `analytics_retention()` / `analytics_top_clubs()` read models. |
| `029_scale_indexes_columns` | FK/query indexes across every hot table + STORED generated columns (club, carry, ball speed, score) on shots/course_rounds. |
| `030_data_export` | `export_my_data()` — full per-user JSON export (GDPR/CCPA). |

> ✅ **029's table rewrite is trivial right now** — prod has ~187 shots and ~17 rounds, so the
> generated-column rewrite is instant. (If you ever re-run this pattern on a table with millions of
> rows, add the columns first then build indexes `CONCURRENTLY` out-of-band.) The `to_double_safe()`
> cast returns NULL on any bad row so the rewrite can't fail mid-flight.

**Verify after apply:**
```sql
select count(*) from rate_limits;                 -- table exists
select public.export_my_data();                   -- returns your JSON (run as a logged-in user)
\d+ shots                                          -- shows club_name, carry_yards, ... columns
```

---

## 2. Scheduled jobs (pg_cron)

Enable the `pg_cron` extension (Dashboard → Database → Extensions), then:

```sql
-- Trim rate-limit windows nightly.
select cron.schedule('purge-rate-limits', '17 3 * * *', $$ select public.purge_rate_limits(); $$);

-- Pre-create next month's analytics partition on the 25th.
select cron.schedule('analytics-partition', '0 0 25 * *',
    $$ select public.ensure_analytics_partition((current_date + interval '1 month')::date); $$);

-- Optional: drop analytics partitions older than 18 months (archive first if needed).
```

---

## 3. Sign in with Apple — provider setup (manual)

Client code is done (native `SignInWithAppleButton` + id_token grant + `applesignin` entitlement).
To make it work end-to-end:

1. **Apple Developer portal**
   - Enable the *Sign In with Apple* capability on App ID `com.rushilkakkad.BallStrikeCamera`.
   - Create a **Services ID** (for the Supabase callback), and a **Sign in with Apple Key** (.p8).
   - Note your **Team ID**, **Key ID**, and the Services ID.
2. **Supabase → Auth → Providers → Apple**: enable it, paste the Services ID (client id),
   Team ID, Key ID, and the .p8 contents. Add redirect
   `https://aoxturoezgecwceudeef.supabase.co/auth/v1/callback`.
3. **Xcode**: confirm the *Sign in with Apple* capability is on the target (entitlement already added).

Apple **requires** Sign in with Apple because the app also offers Google — this unblocks review.

---

## 4. Deploy the new Edge Function

```bash
supabase functions deploy delete-account
# secrets already set for the Stripe functions cover SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY
```

`delete-account` verifies the caller's JWT, wipes their Storage folders, then
`auth.admin.deleteUser()` → cascade removes every owned row. Wired to Settings → **Delete Account**.

---

## 5. Backups & disaster recovery (manual, do before launch)

- **Supabase Pro** (or higher): Dashboard → Database → Backups → enable **daily backups** and
  **Point-in-Time Recovery (PITR)**. PITR is what lets you restore to a minute before an incident.
- **Test a restore quarterly**: spin up a branch/clone from a backup and confirm row counts +
  a login work. An untested backup is not a backup.
- Storage (avatars/video/frames) is replicated by the platform; for 50 TB video, budget for
  Storage egress + consider a CDN in front (Supabase Smart CDN is already used for public objects).

---

## 6. Monitoring & alerting (manual — "know before users do")

| Signal | Where | Alert on |
|--------|-------|----------|
| Crashes | **CrashReporter** (already wired: handled errors + NSExceptions → `analytics_events` as `client_error`/`client_crash`). For full Swift-trap/signal coverage add Sentry — see below. | new crash / spike |
| Backend errors, latency | Supabase → Logs / Reports; **Log Drains** → Datadog/Grafana | 5xx rate, p95 latency, DB CPU/connections |
| Storage usage | Supabase → Storage | % of quota |
| Stripe failures | Stripe Dashboard → **Alerts** + the `invoice.payment_failed` webhook (already handled) | failed payments, webhook 5xx |
| Auth abuse | `audit_log` + Supabase auth logs | failed-login spikes, mass deletions |
| Rate-limit hits | `select action, count(*) from rate_limits group by 1` | sustained ceilings = abuse or a too-tight limit |

Product analytics is now first-party: query `analytics_retention()` / `analytics_top_clubs()`
(service role) for DAU/retention/most-used-club. The app already emits `app_open`, `shot_saved`,
`client_error`, and `client_crash`; extend `logAnalyticsEvent` for `round_completed`,
`camera_failure`, `sim_connected`, etc.

**Activate Sentry (full crash coverage), when ready:**
1. Xcode → *Package Dependencies* → add `https://github.com/getsentry/sentry-cocoa`.
2. In `CrashReporter.configure(dsn:)` uncomment the `SentrySDK.start` block and the
   `SentrySDK.capture` line in `capture(_:)`.
3. Put your DSN in `Secrets.plist` and pass it in `BallStrikeCameraApp.init()`
   (`CrashReporter.shared.configure(dsn: …)`).
The `AnalyticsView` screen now renders **real per-user** club averages / dispersion / trend from
the player's shots (no more mock data).

---

## 7. Scaling path (50 → 5k → 50k → 500k → 1M users)

The design already carries you most of the way; do these as you grow, not up front:

- **Now (done):** RLS everywhere, FK indexes, generated columns, partitioned telemetry, rate
  limits, connection via PostgREST (stateless, scales horizontally).
- **~50k users:** turn on **PgBouncer / Supavisor** transaction pooling (Dashboard → Database →
  Connection Pooling); point the app/functions at the pooled port. Bump compute add-on.
- **~200k users / 5M+ shots:** move `shot-videos` reads behind a CDN; add read replicas for the
  analytics/aggregate queries so they don't touch the primary.
- **~1M users / 20M+ shots:** RANGE-partition `shots` and `course_rounds` by month (same pattern
  as `analytics_events`) so vacuum/index maintenance stays bounded; archive cold partitions to
  cheaper storage. The generated columns + indexes already keep per-user reads O(log n).

Because reads are per-user and indexed, and writes are append-mostly, the primary bottleneck at
1M is **connections** (fix with pooling) and **video storage/egress** (fix with CDN), not schema.

---

## 8. Security checklist status

- ✅ RLS on every user table + storage + courses
- ✅ Subscriptions server-only (Stripe webhook, signature-verified)
- ✅ Private buckets, MIME allowlists, size limits, entitlement-gated video
- ✅ IDOR-hardened RPCs, `search_path` pinned, 2-device cap
- ✅ App-level rate limiting (026) + auth rate limits (config.toml)
- ✅ Audit log (027)
- ✅ Account deletion (edge fn) + data export (030)
- ✅ Sign in with Apple (code; provider config = §3)
- ⚙️ Backups/PITR + restore test = §5 (manual)
- ⚙️ Crash/latency/Stripe monitoring = §6 (manual)
