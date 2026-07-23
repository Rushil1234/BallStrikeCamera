-- 062_block_reserved_email_signups.sql
-- Reserved / guaranteed-undeliverable email domains (RFC 2606 & 6761): example.com/org/net
-- publish a Null MX record, and .test / .invalid / .localhost / .example never resolve. GoTrue
-- still sends a confirmation email on signup, so every one HARD-bounces back to our Zoho SMTP
-- sender (noah.tobias@truecarrygolf.com) — automated test signups like
-- tc.aitest4+<ts>@example.com were flooding that inbox with mailer-daemon bounces
-- ("5.7.27 Delivery failed: Null MX found for the domain").
--
-- Reject these at the auth.users INSERT: no user row is created and no confirmation email is
-- ever sent, for EVERY signup path (web form, iOS app, and direct GoTrue API — the web form
-- also validates client-side for a friendlier message, but that alone can't stop an API-direct
-- bot). Only guaranteed-undeliverable reserved domains are blocked; no real domain is affected.
-- Email CHANGES are UPDATEs and are intentionally not touched. Rollback:
--   drop trigger reject_reserved_email_domains on auth.users;

create or replace function auth.reject_reserved_email_domains()
returns trigger
language plpgsql
security definer
set search_path = auth, public
as $$
declare
  addr   text := lower(coalesce(new.email, ''));
  domain text;
begin
  if addr = '' then
    return new;                       -- phone / anonymous signups carry no email
  end if;
  domain := split_part(addr, '@', 2);
  if domain in ('example.com', 'example.org', 'example.net', 'localhost')
     or domain ~ '\.(test|example|invalid|localhost)$' then
    raise exception 'Email domain "%" is not deliverable (reserved). Use a real email address.', domain
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists reject_reserved_email_domains on auth.users;
create trigger reject_reserved_email_domains
  before insert on auth.users
  for each row execute function auth.reject_reserved_email_domains();
