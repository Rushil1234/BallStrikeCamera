-- Consolidate the two GENUINE multiple-permissive-policy cases (linter:
-- multiple_permissive_policies). Most of the linter's count is the benign public-vs-
-- authenticated layering pattern (a broad public read + a narrower authenticated policy),
-- which is intentional and left alone. Only these two are real redundancy:
--
-- 1. `courses` has TWO identical SELECT policies (`public read courses` and
--    `public_read_courses`), both USING (true) TO public — a straight duplicate. Drop one.
-- 2. `round_attestations` has two separate SELECT policies (attester vs requester) that
--    Postgres OR's anyway — merge into one so it's evaluated as a single policy.

-- 1. Drop the duplicate courses read policy (keep public_read_courses).
drop policy if exists "public read courses" on public.courses;

-- 2. Merge the two round_attestations SELECT policies into one.
drop policy if exists "attester reads" on public.round_attestations;
drop policy if exists "requester reads own" on public.round_attestations;
create policy "read own attestations" on public.round_attestations
  for select to public
  using ((select auth.uid()) = attester_id or (select auth.uid()) = requester_id);
