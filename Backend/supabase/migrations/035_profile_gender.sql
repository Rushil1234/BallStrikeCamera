-- 035_profile_gender.sql
-- Gender preference on the profile, mirroring handedness (001_initial_schema.sql:11). Drives
-- which tee rating/slope a round captures for handicap calculation (see TeeBox.resolvedRating/
-- resolvedSlope in CourseModels.swift) — not a gameplay setting, just which of a tee's two
-- rating/slope pairs (men's vs. women's) applies.

alter table profiles
    add column if not exists gender text not null default 'Male';
