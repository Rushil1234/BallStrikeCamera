-- 001_initial_schema.sql
-- True Carry — core tables

create extension if not exists "uuid-ossp";

-- ── Profiles ─────────────────────────────────────────────────────────────────
create table if not exists profiles (
    id               uuid primary key default uuid_generate_v4(),
    user_id          uuid not null references auth.users(id) on delete cascade,
    display_name     text not null default '',
    handedness       text not null default 'Right-handed',
    distance_unit    text not null default 'Yards',
    speed_unit       text not null default 'mph',
    home_course_name text not null default '',
    profile_image_path text,
    created_at       timestamptz not null default now(),
    updated_at       timestamptz not null default now(),
    unique(user_id)
);

-- ── Clubs ─────────────────────────────────────────────────────────────────────
create table if not exists clubs (
    id                   uuid primary key default uuid_generate_v4(),
    user_id              uuid not null references auth.users(id) on delete cascade,
    name                 text not null,
    type                 text not null,
    expected_carry_yards int  not null default 0,
    expected_total_yards int  not null default 0,
    is_active            boolean not null default true,
    sort_order           int  not null default 0,
    shot_count           int  not null default 0,
    created_at           timestamptz not null default now()
);

-- ── Shots ─────────────────────────────────────────────────────────────────────
create table if not exists shots (
    id          uuid primary key default uuid_generate_v4(),
    user_id     uuid not null references auth.users(id) on delete cascade,
    payload     jsonb not null,              -- full SavedShot JSON
    timestamp   timestamptz not null default now()
);

-- ── Range Sessions ────────────────────────────────────────────────────────────
create table if not exists range_sessions (
    id         uuid primary key default uuid_generate_v4(),
    user_id    uuid not null references auth.users(id) on delete cascade,
    payload    jsonb not null,
    started_at timestamptz not null default now()
);

-- ── Sim Sessions ──────────────────────────────────────────────────────────────
create table if not exists sim_sessions (
    id         uuid primary key default uuid_generate_v4(),
    user_id    uuid not null references auth.users(id) on delete cascade,
    payload    jsonb not null,
    started_at timestamptz not null default now()
);

-- ── Course Rounds ─────────────────────────────────────────────────────────────
create table if not exists course_rounds (
    id          uuid primary key default uuid_generate_v4(),
    user_id     uuid not null references auth.users(id) on delete cascade,
    payload     jsonb not null,
    started_at  timestamptz not null default now()
);

-- ── Feed Posts ────────────────────────────────────────────────────────────────
create table if not exists feed_posts (
    id          uuid primary key default uuid_generate_v4(),
    user_id     uuid not null references auth.users(id) on delete cascade,
    payload     jsonb not null,
    visibility  text not null default 'friends',
    timestamp   timestamptz not null default now()
);

-- ── Feed Reactions ────────────────────────────────────────────────────────────
create table if not exists feed_reactions (
    id         uuid primary key default uuid_generate_v4(),
    post_id    uuid not null references feed_posts(id) on delete cascade,
    user_id    uuid not null references auth.users(id) on delete cascade,
    emoji      text not null,
    created_at timestamptz not null default now(),
    unique(post_id, user_id)
);

-- ── Feed Comments ─────────────────────────────────────────────────────────────
create table if not exists feed_comments (
    id          uuid primary key default uuid_generate_v4(),
    post_id     uuid not null references feed_posts(id) on delete cascade,
    user_id     uuid not null references auth.users(id) on delete cascade,
    author_name text not null,
    body        text not null,
    created_at  timestamptz not null default now()
);

-- ── Friendships ───────────────────────────────────────────────────────────────
create table if not exists friend_requests (
    id           uuid primary key default uuid_generate_v4(),
    from_user_id uuid not null references auth.users(id) on delete cascade,
    to_user_id   uuid not null references auth.users(id) on delete cascade,
    status       text not null default 'pending',
    sent_at      timestamptz not null default now(),
    resolved_at  timestamptz
);

create table if not exists friendships (
    id         uuid primary key default uuid_generate_v4(),
    user_id    uuid not null references auth.users(id) on delete cascade,
    friend_id  uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now(),
    unique(user_id, friend_id)
);
