-- 013_pro_course_data.sql
-- Normalized schema for licensed professional course data (18Birdies-grade).
-- Source feed ships four tables: clubs, courses, tees, coordinates (per-hole POIs).
-- These store the full-fidelity purchased data; an importer derives the app-facing
-- `course_geometries` GolfCourse JSON from them so the iOS app needs no rework.
--
-- Writes are service-role only (server-side ingestion). Reads are public so the app
-- can surface club/course detail beyond what the GolfCourse JSON carries.

-- ── Clubs (facilities) ────────────────────────────────────────────────────
create table if not exists pro_clubs (
    club_id      text primary key,           -- ClubID
    name         text not null default '',
    address      text not null default '',
    city         text not null default '',
    postal_code  text not null default '',
    state        text not null default '',
    country      text not null default '',
    continent    text not null default '',
    latitude     double precision,
    longitude    double precision,
    website      text,
    email        text,
    telephone    text,
    updated_at   timestamptz not null default now()
);

-- ── Courses (a club can have several) ─────────────────────────────────────
create table if not exists pro_courses (
    course_id        text primary key,        -- CourseID
    club_id          text references pro_clubs(club_id) on delete cascade,
    long_course_id   text,                     -- LongCourseID
    name             text not null default '',
    num_holes        integer not null default 18,
    measure_meters   boolean not null default false,  -- MeasureMeters flag from feed
    -- Per-hole arrays (index 0 = hole 1). Men + women pars/handicaps and match/split index.
    par_men          integer[] not null default '{}',
    par_women        integer[] not null default '{}',
    hcp_men          integer[] not null default '{}',
    hcp_women        integer[] not null default '{}',
    match_index      integer[] not null default '{}',
    split_index      integer[] not null default '{}',
    source_updated   bigint,                   -- TimestampUpdated (epoch secs from feed)
    updated_at       timestamptz not null default now()
);
create index if not exists pro_courses_club_idx on pro_courses (club_id);

-- ── Tees (per course, each with per-hole lengths) ─────────────────────────
create table if not exists pro_tees (
    tee_id            text primary key,        -- TeeID
    course_id         text references pro_courses(course_id) on delete cascade,
    name              text not null default '',
    color             text,                    -- hex
    measure_unit      text not null default 'y',  -- 'm' or 'y' from feed
    slope             integer,
    slope_front9      integer,
    slope_back9       integer,
    cr                double precision,        -- course rating
    cr_front9         double precision,
    cr_back9          double precision,
    slope_women       integer,
    slope_women_front9 integer,
    slope_women_back9  integer,
    cr_women          double precision,
    cr_women_front9   double precision,
    cr_women_back9    double precision,
    lengths           integer[] not null default '{}',  -- per-hole, in measure_unit
    updated_at        timestamptz not null default now()
);
create index if not exists pro_tees_course_idx on pro_tees (course_id);

-- ── Per-hole points of interest (greens, tees, hazards, markers) ──────────
create table if not exists pro_hole_pois (
    id            bigserial primary key,
    course_id     text references pro_courses(course_id) on delete cascade,
    hole          integer not null,
    poi           text not null,              -- Green, Tee Front, Tee Back, Fairway Bunker, ...
    location      text,                        -- F / C / B
    side          text,                        -- L / C / R (SideOfFairway)
    latitude      double precision not null,
    longitude     double precision not null
);
create index if not exists pro_hole_pois_course_hole_idx on pro_hole_pois (course_id, hole);

-- ── RLS: public read, service-role-only write ────────────────────────────
alter table pro_clubs     enable row level security;
alter table pro_courses   enable row level security;
alter table pro_tees      enable row level security;
alter table pro_hole_pois enable row level security;

create policy "public read pro_clubs"     on pro_clubs     for select using (true);
create policy "public read pro_courses"   on pro_courses   for select using (true);
create policy "public read pro_tees"      on pro_tees      for select using (true);
create policy "public read pro_hole_pois" on pro_hole_pois for select using (true);
-- No insert/update/delete policies: only the service role (ingestion) may write.
