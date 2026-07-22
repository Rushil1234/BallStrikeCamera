-- Anti-vandalism guard for the crowdsourced course_geometries table. Migration 057 stopped
-- authorship spoofing, but the UPDATE policy is still USING (true) by design (any player may
-- refresh the shared snapshot). That leaves a griefing vector: a bad actor could overwrite a
-- good, scorecard-verified or high-confidence snapshot with worse data.
--
-- This BEFORE UPDATE trigger makes quality one-directional: a refresh can improve a row but
-- never DOWNGRADE it — a verified flag can't be cleared, and confidence can't be lowered.
-- (Mirrors the app's own "only set the flag forward" write-through, enforced server-side.)

create or replace function tg_course_geometry_no_downgrade()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.scorecard_verified is true then
    new.scorecard_verified := true;
  end if;
  if old.confidence is not null
     and (new.confidence is null or new.confidence < old.confidence) then
    new.confidence := old.confidence;
  end if;
  return new;
end $$;

revoke execute on function public.tg_course_geometry_no_downgrade() from public;

drop trigger if exists course_geometry_no_downgrade on public.course_geometries;
create trigger course_geometry_no_downgrade
  before update on public.course_geometries
  for each row execute function tg_course_geometry_no_downgrade();
