-- Persisted AI coaching summaries, saved with the golfer's profile. Every deep-read the
-- AI Coach produces is stored here so (a) the golfer can revisit their coaching history and
-- (b) the coach itself reads the last few notes as context, making advice longitudinal
-- ("last time we worked on X — it's tightening") instead of one-off.
--
-- Writes come from the ai-coach edge function (service role, sets user_id explicitly). The
-- policies below let each golfer read + delete their OWN notes from the app; there is no
-- client insert policy because only the trusted function should create them.

create table if not exists ai_coach_notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  mode text not null check (mode in ('shot','session','round','bag')),
  summary text not null,
  context_label text,            -- e.g. course name, club, "Range session"
  created_at timestamptz not null default now()
);

create index if not exists ai_coach_notes_user_idx on ai_coach_notes(user_id, created_at desc);

alter table ai_coach_notes enable row level security;

drop policy if exists "read own coach notes" on ai_coach_notes;
create policy "read own coach notes" on ai_coach_notes
  for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "delete own coach notes" on ai_coach_notes;
create policy "delete own coach notes" on ai_coach_notes
  for delete to authenticated using ((select auth.uid()) = user_id);
