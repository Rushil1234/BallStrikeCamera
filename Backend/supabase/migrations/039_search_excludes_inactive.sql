-- 039_search_excludes_inactive.sql
-- `courses.status = 'inactive'` is the reversible removal mechanism for phantom
-- listings (Cozy Acres pattern), standalone driving ranges, and duplicate
-- catalog rows — but search_courses never filtered it, so marking a course
-- inactive changed nothing in the app. Now inactive courses vanish from search
-- and Nearby while their rows (and any saved rounds referencing them) survive.

-- The original check constraint predates the cleanup tooling and lacked
-- 'inactive'; extend it rather than overload 'closed' (a real course that shut
-- down) or 'duplicate' (a redundant row of a real course).
alter table courses drop constraint if exists courses_status_check;
alter table courses add constraint courses_status_check
    check (status = any (array['active','closed','duplicate','inactive','needs_review','unknown']));

create or replace function search_courses(
    q text default null,
    lat double precision default null,
    lon double precision default null,
    only_geometry boolean default false,
    lim integer default 20
) returns setof courses
language sql stable as $$
    select *
    from courses c
    where (c.status is null or c.status not in ('inactive', 'closed', 'duplicate'))
      and (not only_geometry or c.data_tier = 'gps_ready')
      and (q is null or q = '' or c.name ilike '%'||q||'%')
    order by
      (case when q is not null and q <> '' then similarity(c.name, q) else 0 end) desc,
      (case when lat is not null and c.latitude is not null
            then ((c.latitude-lat)*(c.latitude-lat) + (c.longitude-lon)*(c.longitude-lon))
            else 1e9 end) asc,
      c.name asc
    limit greatest(1, least(lim, 50));
$$;
