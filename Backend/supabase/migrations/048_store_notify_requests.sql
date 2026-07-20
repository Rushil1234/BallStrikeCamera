-- ============================================================================
-- 048_store_notify_requests.sql   (APPLIED 2026-07-19)
-- Waitlist capture for the store's "Notify me" buttons (was a mailto: link).
--
-- SECURITY: anon may INSERT only, and there is deliberately NO SELECT policy —
-- with RLS enabled, no policy means no reads. Anyone with the public anon key
-- must never be able to dump the customer email list. (This is the same class
-- of mistake that made live_sim_state fully readable; see migration 043.)
-- Verified after apply, as anon: INSERT -> 201, SELECT -> [], bad email -> 4xx,
-- duplicate -> 409.
-- ============================================================================

create table if not exists public.store_notify_requests (
  id           uuid primary key default gen_random_uuid(),
  email        text not null,
  product_id   text not null,
  product_name text,
  source       text default 'store',
  created_at   timestamptz not null default now(),
  constraint store_notify_email_format check (email ~* '^[^@\s]+@[^@\s.]+\.[^@\s]+$'),
  constraint store_notify_email_len    check (char_length(email) between 5 and 254),
  constraint store_notify_product_len  check (char_length(product_id) between 1 and 64),
  unique (email, product_id)   -- one signup per person per product
);

create index if not exists store_notify_created_idx on public.store_notify_requests (created_at desc);
create index if not exists store_notify_product_idx on public.store_notify_requests (product_id);

alter table public.store_notify_requests enable row level security;

drop policy if exists "notify insert" on public.store_notify_requests;
create policy "notify insert" on public.store_notify_requests
  for insert to anon, authenticated
  with check (
    email ~* '^[^@\s]+@[^@\s.]+\.[^@\s]+$'
    and char_length(product_id) between 1 and 64
  );

-- Founder-dashboard readers (service_role only, same rules as 042/044).
create or replace function public.founder_notify_signups(p_limit int default 200)
returns table(email text, product_id text, product_name text, created_at timestamptz)
language sql security definer set search_path = public
as $$
  select email, product_id, product_name, created_at
  from public.store_notify_requests
  order by created_at desc
  limit least(p_limit, 1000);
$$;

create or replace function public.founder_notify_counts()
returns table(product_id text, product_name text, signups bigint, latest timestamptz)
language sql security definer set search_path = public
as $$
  select product_id, max(product_name), count(*)::bigint, max(created_at)
  from public.store_notify_requests
  group by product_id
  order by count(*) desc;
$$;

revoke all on function public.founder_notify_signups(int) from public, anon, authenticated;
revoke all on function public.founder_notify_counts() from public, anon, authenticated;
grant execute on function public.founder_notify_signups(int) to service_role;
grant execute on function public.founder_notify_counts() to service_role;
