# Supabase Deployment Guide

Project: `aoxturoezgecwceudeef`
Dashboard: https://supabase.com/dashboard/project/aoxturoezgecwceudeef

---

## Option A — SQL Editor (manual, no CLI needed)

1. Open the SQL Editor:
   https://supabase.com/dashboard/project/aoxturoezgecwceudeef/sql

2. Run each migration file **in order**, pasting the contents and clicking Run:
   ```
   Backend/supabase/migrations/001_initial_schema.sql
   Backend/supabase/migrations/002_entitlements.sql
   Backend/supabase/migrations/003_rls_policies.sql
   Backend/supabase/migrations/004_storage_policies.sql
   ```

3. Verify in Table Editor that these tables exist:
   - `profiles`
   - `clubs`
   - `shots`
   - `range_sessions`
   - `sim_sessions`
   - `course_rounds`
   - `feed_posts`
   - `user_entitlements`
   - `usage_counters`
   - `user_devices`
   - `friend_requests`
   - `friendships`

4. Verify RLS is enabled on each table:
   Dashboard → Authentication → Policies → confirm each table has policies.

5. Create Storage buckets:
   Dashboard → Storage → New bucket
   - `avatars` — private
   - `shot-media` — private
   - `course-cache` — private

---

## Option B — Supabase CLI

### Install
```bash
brew install supabase/tap/supabase
```

### Login
```bash
supabase login
```

### Link project
```bash
supabase link --project-ref aoxturoezgecwceudeef
```

### Push migrations
```bash
supabase db push
```

### Deploy Edge Functions
```bash
supabase functions deploy stripe-webhook
supabase functions deploy create-checkout-session
supabase functions deploy create-customer-portal-session
```

---

## Edge Function secrets

Set all secrets before deploying functions:
```bash
supabase secrets set SUPABASE_URL=https://aoxturoezgecwceudeef.supabase.co
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=<your service role key>
supabase secrets set STRIPE_SECRET_KEY=<sk_live_...>
supabase secrets set STRIPE_WEBHOOK_SECRET=<whsec_...>
supabase secrets set STRIPE_BASIC_MONTHLY_PRICE_ID=<price_...>
supabase secrets set STRIPE_BASIC_YEARLY_PRICE_ID=<price_...>
supabase secrets set STRIPE_PRO_MONTHLY_PRICE_ID=<price_...>
supabase secrets set STRIPE_PRO_YEARLY_PRICE_ID=<price_...>
supabase secrets set STRIPE_UNLIMITED_MONTHLY_PRICE_ID=<price_...>
supabase secrets set STRIPE_UNLIMITED_YEARLY_PRICE_ID=<price_...>
supabase secrets set TRUECARRY_WEBSITE_URL=https://truecarry.app
```

Or set via Dashboard → Edge Functions → Manage secrets.

---

## Edge Function URLs

Once deployed:
- Stripe webhook: `https://aoxturoezgecwceudeef.functions.supabase.co/stripe-webhook`
- Checkout: `https://aoxturoezgecwceudeef.functions.supabase.co/create-checkout-session`
- Portal: `https://aoxturoezgecwceudeef.functions.supabase.co/create-customer-portal-session`

---

## Security reminders

- Never commit `.env` files.
- Never put `SUPABASE_SERVICE_ROLE_KEY` or `STRIPE_SECRET_KEY` in the iOS app or website frontend.
- Rotate any key that was accidentally committed before production launch.
- The iOS app uses the **anon key only** (from `Secrets.plist`).
- The website uses the **anon key only** (from `NEXT_PUBLIC_SUPABASE_ANON_KEY`).
- Only Edge Functions use service-role and Stripe secret keys.
