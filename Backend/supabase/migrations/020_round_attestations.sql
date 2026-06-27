-- 020_round_attestations.sql
-- Lets a golfer ask a specific friend to attest (verify) one of their course rounds.
-- The requester creates a row addressed to the attester; the attester responds (attested/declined).
-- requester_name is denormalized so the attester can render the request without a join/RPC.

create table if not exists round_attestations (
    id             uuid primary key,
    round_id       uuid not null,
    requester_id   uuid not null references auth.users(id) on delete cascade,
    requester_name text not null default '',
    attester_id    uuid not null references auth.users(id) on delete cascade,
    course_name    text not null default '',
    round_date     timestamptz,
    score          integer,
    to_par         integer,
    status         text not null default 'pending',   -- pending | attested | declined
    created_at     timestamptz not null default now(),
    responded_at   timestamptz
);

create index if not exists round_attestations_attester_idx  on round_attestations (attester_id, status);
create index if not exists round_attestations_requester_idx on round_attestations (requester_id);

alter table round_attestations enable row level security;

-- Requester: create requests as themselves, and read their own (to see status).
create policy "requester inserts own" on round_attestations for insert
    with check (auth.uid() = requester_id);
create policy "requester reads own"   on round_attestations for select
    using (auth.uid() = requester_id);

-- Attester: read requests addressed to them and respond (update status only).
create policy "attester reads"    on round_attestations for select
    using (auth.uid() = attester_id);
create policy "attester responds" on round_attestations for update
    using (auth.uid() = attester_id);
