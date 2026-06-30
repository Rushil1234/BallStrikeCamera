-- 025_function_search_path_hardening.sql
-- Clears the `function_search_path_mutable` advisor on existing SECURITY INVOKER
-- course/geo functions by pinning search_path to a superset of what they already
-- resolve against (PostGIS lives in `extensions`), so behavior is unchanged.
alter function public.set_course_location() set search_path = public, extensions;
alter function public.nearby_courses(double precision, double precision, integer, integer) set search_path = public, extensions;
alter function public.search_courses(text, double precision, double precision, boolean, integer) set search_path = public, extensions;
alter function golfmapper.upsert_course(text, text, text, jsonb) set search_path = golfmapper, public, extensions;
alter function golfmapper.import_feature_collection(uuid, jsonb) set search_path = golfmapper, public, extensions;
alter function golfmapper.upsert_hole(uuid, integer, jsonb, real, text, text) set search_path = golfmapper, public, extensions;
