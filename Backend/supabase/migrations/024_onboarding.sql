-- 024_onboarding.sql
-- Track whether a user has completed the first-run in-app tutorial, so it shows
-- once and the state is known server-side (and on the website if needed).
alter table profiles add column if not exists onboarding_completed    boolean not null default false;
alter table profiles add column if not exists onboarding_completed_at  timestamptz;
