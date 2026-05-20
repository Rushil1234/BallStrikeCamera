-- 009_geometry_backfill_policy_hardening.sql
-- Keep the queue public, but constrain anonymous rows to valid queued requests.

drop policy if exists "public can queue geometry backfill" on geometry_backfill_requests;
drop policy if exists "public can refresh geometry backfill" on geometry_backfill_requests;

create policy "public can queue geometry backfill"
    on geometry_backfill_requests for insert
    with check (
        length(course_id) between 1 and 180
        and length(course_name) <= 240
        and status = 'queued'
        and reason in ('missing_geometry', 'smoke_test')
    );

create policy "public can refresh geometry backfill"
    on geometry_backfill_requests for update
    using (
        length(course_id) between 1 and 180
        and status in ('queued', 'failed')
    )
    with check (
        length(course_id) between 1 and 180
        and length(course_name) <= 240
        and status = 'queued'
        and reason in ('missing_geometry', 'smoke_test')
    );
