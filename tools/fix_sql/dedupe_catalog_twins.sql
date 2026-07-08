-- 2026-07-08: catalog duplicate merge (Sparta / Sky View pattern).
-- Same normalized name within ~1 km (2-decimal rounded lat/lon) where at least
-- one twin is gps_ready and another isn't: the mapped row is authoritative, the
-- unmapped twin is marked 'duplicate' (hidden by search_courses since 039).
-- Both-gps_ready collisions are NOT touched here — those need the geometry
-- fingerprint audit (tools/course_audit.py) to say which blob is real.
with g as (
  select normalized_name, round(latitude::numeric,2) rlat, round(longitude::numeric,2) rlon
  from public.courses
  where status='active' and latitude is not null
  group by 1,2,3
  having count(*) > 1
     and count(*) filter (where data_tier='gps_ready') >= 1
     and count(*) filter (where data_tier <> 'gps_ready') >= 1
)
update public.courses c set status='duplicate'
from g
where c.normalized_name = g.normalized_name
  and round(c.latitude::numeric,2) = g.rlat
  and round(c.longitude::numeric,2) = g.rlon
  and c.status = 'active'
  and c.data_tier <> 'gps_ready';
