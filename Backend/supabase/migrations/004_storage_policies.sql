-- 004_storage_policies.sql
-- True Carry — Supabase Storage buckets & policies

-- ── Buckets ───────────────────────────────────────────────────────────────────
-- Create via Supabase dashboard or CLI:
--   supabase storage create profile-images --public false --file-size-limit 5MB
--   supabase storage create shot-videos    --public false --file-size-limit 200MB
--   supabase storage create shot-frames    --public false --file-size-limit 20MB

-- ── Profile Images ────────────────────────────────────────────────────────────
-- Path convention: profile-images/{user_id}/avatar.jpg

create policy "users upload own avatar"
    on storage.objects for insert
    with check (
        bucket_id = 'profile-images'
        and auth.uid()::text = (storage.foldername(name))[1]
    );

create policy "users update own avatar"
    on storage.objects for update
    using (
        bucket_id = 'profile-images'
        and auth.uid()::text = (storage.foldername(name))[1]
    );

create policy "users read own avatar"
    on storage.objects for select
    using (
        bucket_id = 'profile-images'
        and auth.uid()::text = (storage.foldername(name))[1]
    );

-- ── Shot Videos ───────────────────────────────────────────────────────────────
-- Path convention: shot-videos/{user_id}/{shot_id}.mp4
-- Only Pro/Unlimited users can write; enforced via entitlement check in app + RLS below.

create policy "users upload own shot videos"
    on storage.objects for insert
    with check (
        bucket_id = 'shot-videos'
        and auth.uid()::text = (storage.foldername(name))[1]
        and exists (
            select 1 from user_entitlements
            where user_id = auth.uid()
            and tier in ('pro', 'unlimited')
            and payment_status in ('active', 'trialing')
        )
    );

create policy "users read own shot videos"
    on storage.objects for select
    using (
        bucket_id = 'shot-videos'
        and auth.uid()::text = (storage.foldername(name))[1]
    );

create policy "users delete own shot videos"
    on storage.objects for delete
    using (
        bucket_id = 'shot-videos'
        and auth.uid()::text = (storage.foldername(name))[1]
    );

-- ── Shot Frames ───────────────────────────────────────────────────────────────
-- Path convention: shot-frames/{user_id}/{shot_id}/{frame_n}.jpg

create policy "users upload own shot frames"
    on storage.objects for insert
    with check (
        bucket_id = 'shot-frames'
        and auth.uid()::text = (storage.foldername(name))[1]
    );

create policy "users read own shot frames"
    on storage.objects for select
    using (
        bucket_id = 'shot-frames'
        and auth.uid()::text = (storage.foldername(name))[1]
    );
