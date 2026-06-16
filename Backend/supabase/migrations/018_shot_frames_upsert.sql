-- 018_shot_frames_upsert.sql
-- The shot-frames bucket (007) + insert/select policies (004) already exist and
-- match the client path convention shot-frames/{user_id}/{shot_id}/frame_N.png.
-- Add update + delete so the client's upsert upload is robust (re-saving the
-- same shot id overwrites cleanly) and so frames can be removed when a shot is
-- deleted. Same owner check: the first path folder must be the caller's user id.
-- Idempotent: safe to re-run (these may already have been applied by hand).

drop policy if exists "users update own shot frames" on storage.objects;
create policy "users update own shot frames"
    on storage.objects for update
    using (
        bucket_id = 'shot-frames'
        and auth.uid()::text = (storage.foldername(name))[1]
    )
    with check (
        bucket_id = 'shot-frames'
        and auth.uid()::text = (storage.foldername(name))[1]
    );

drop policy if exists "users delete own shot frames" on storage.objects;
create policy "users delete own shot frames"
    on storage.objects for delete
    using (
        bucket_id = 'shot-frames'
        and auth.uid()::text = (storage.foldername(name))[1]
    );
