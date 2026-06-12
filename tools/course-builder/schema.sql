-- Run this in Supabase SQL Editor to create the sim_courses table.
-- This stores converted course definitions for the browser simulator.

create table if not exists sim_courses (
  id          uuid primary key default gen_random_uuid(),
  course_id   text unique not null,      -- matches course_geometries.course_id
  course_name text not null,
  holes_json  jsonb not null,            -- array of hole definitions in sim format
  latitude    double precision,
  longitude   double precision,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

-- Index for quick lookup by lat/lng
create index if not exists sim_courses_location_idx
  on sim_courses (latitude, longitude);

-- Row Level Security
alter table sim_courses enable row level security;

-- Anyone can read (the sim loads courses without auth)
create policy "Public read sim_courses"
  on sim_courses for select
  using (true);

-- Only authenticated users can insert / update
create policy "Auth insert sim_courses"
  on sim_courses for insert
  with check (auth.role() = 'authenticated');

create policy "Auth update sim_courses"
  on sim_courses for update
  using (auth.role() = 'authenticated');
