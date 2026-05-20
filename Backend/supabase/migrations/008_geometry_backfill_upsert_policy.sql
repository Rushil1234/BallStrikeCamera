-- 008_geometry_backfill_upsert_policy.sql
-- PostgREST upserts need SELECT visibility in addition to INSERT/UPDATE policies.

drop policy if exists "public can read geometry backfill requests" on geometry_backfill_requests;

create policy "public can read geometry backfill requests"
    on geometry_backfill_requests for select
    using (true);
