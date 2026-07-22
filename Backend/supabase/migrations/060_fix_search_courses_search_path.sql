-- 060_fix_search_courses_search_path.sql
-- Migration 055 re-pinned public.search_courses to `search_path = public`, which DROPPED the
-- `extensions` schema that 025 had deliberately included. pg_trgm's similarity() lives in
-- `extensions`, so from 055 onward every search_courses() call failed with
--   "function similarity(text, text) does not exist"  (SQLSTATE 42883).
-- Because runSearch() treats a non-200 as "backend unreachable" (nil), this silently returned
-- ZERO catalog results app-wide — Course Mode Nearby and search both came back empty.
--
-- Restore the superset search_path so similarity() resolves again. Still SECURITY INVOKER,
-- still non-mutable (pinned) — this only re-adds the extensions schema 055 removed.
alter function public.search_courses(q text, lat double precision, lon double precision, only_geometry boolean, lim integer)
  set search_path = public, extensions;
