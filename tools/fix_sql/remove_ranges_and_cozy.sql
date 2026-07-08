-- 2026-07-08: standalone driving ranges / practice facilities have no place in
-- a course catalog (user report: "Golf Range Bremen" — that one was already
-- inactivated with the phantom batch). Playable hybrids are kept: names with
-- golf course/club, country club, links, par-3, or "golf & driving range"
-- (facility with a real course attached) are excluded from the match.
-- Reversible: status flip only; search_courses (migration 039) hides them.
update public.courses set status = 'inactive'
where status = 'active'
  and name ~* '(driving range|golf range|practice (center|centre|facility|range))'
  and name !~* '(golf.?(course|club)|country club|links|par.?3|mashie|golf (&|and) (driving|practice))';

-- Explicit user-requested removal: Cozy Acres Golf Course (no city/state, blob
-- quarantined in the 2026-07-07 audit, namesake of the phantom pattern).
update public.courses set status = 'inactive'
where id = '4a946649-7ce3-5ed9-814b-00c8308de2b9';
