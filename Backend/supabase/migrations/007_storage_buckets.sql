-- 007_storage_buckets.sql
-- Create private storage buckets referenced by 004_storage_policies.sql.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
    ('profile-images', 'profile-images', false, 5242880, array['image/jpeg', 'image/png', 'image/webp']),
    ('shot-videos', 'shot-videos', false, 209715200, array['video/mp4', 'video/quicktime']),
    ('shot-frames', 'shot-frames', false, 20971520, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types,
    updated_at = now();
