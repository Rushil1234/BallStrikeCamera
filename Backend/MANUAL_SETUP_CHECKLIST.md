# Manual Setup Checklist — True Carry

Everything in this file requires your input before production can go live.
Code, infrastructure, and docs are already created. You provide the keys and decisions.

---

## 🔑 Keys you must provide

- [ ] **Supabase anon key**
  - Dashboard → Settings → API → `anon` (public) key
  - Add to `BallStrikeCamera/Secrets.plist` (not committed)
  - Add to Vercel env: `NEXT_PUBLIC_SUPABASE_ANON_KEY`

- [ ] **Supabase service-role key** *(for Edge Functions only — never in app or website)*
  - Dashboard → Settings → API → `service_role` key
  - `supabase secrets set SUPABASE_SERVICE_ROLE_KEY=<key>`

- [ ] **Stripe secret key**
  - Dashboard → Developers → API keys → secret key
  - `supabase secrets set STRIPE_SECRET_KEY=sk_live_...`

- [ ] **Stripe webhook signing secret**
  - Created when you add the webhook endpoint in Stripe Dashboard
  - `supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_...`

- [ ] **Stripe price IDs** (6 total)
  - Basic monthly, Basic yearly
  - Pro monthly, Pro yearly
  - Unlimited monthly, Unlimited yearly
  - See `Backend/stripe/README.md` for exact setup steps

---

## 🗄️ Supabase database

- [ ] Run migrations in order via SQL Editor or CLI
  - `001_initial_schema.sql`
  - `002_entitlements.sql`
  - `003_rls_policies.sql`
  - `004_storage_policies.sql`
  - Full instructions: `Backend/supabase/DEPLOYMENT.md`

- [ ] Verify tables exist in Table Editor

- [ ] Verify RLS is enabled on all tables

- [ ] Create Storage buckets:
  - `avatars` — private
  - `shot-media` — private
  - `course-cache` — private

---

## 🌐 Website hosting

- [ ] Choose hosting (recommended: **Vercel** — free tier, zero-config Next.js)
  - Full instructions: `Website/DEPLOYMENT.md`

- [ ] Deploy site and copy the generated `.vercel.app` URL

- [ ] Add `.vercel.app` URL to:
  - Supabase Edge Function secrets: `TRUECARRY_WEBSITE_URL`
  - Stripe webhook success/cancel URLs (via `create-checkout-session` Edge Function env var)

- [ ] (Optional) Buy `truecarry.app` and connect to Vercel
  - Registrar options: Namecheap, Cloudflare Registrar, Google Domains
  - After DNS propagation, update `TRUECARRY_WEBSITE_URL` everywhere

---

## 📱 iOS app

- [ ] Copy `Config/Secrets.example.plist` to `BallStrikeCamera/Secrets.plist`
- [ ] Fill in `SupabaseAnonKey` (the anon/public key only)
- [ ] Add `Secrets.plist` to Xcode project target (if not already added)
- [ ] Confirm `BallStrikeCamera/Secrets.plist` is in `.gitignore`

---

## 🏌️ Business decisions needed

- [ ] **Device policy** — recommended: one active device per paid account;
  users can request a transfer via email or account page.
  Reset frequency: suggested once every 30 days per user request.

- [ ] **Shot storage limits** (current recommendation):
  | Tier | Cloud shots | Original frames |
  |------|-------------|-----------------|
  | Free | 0 (local only) | No |
  | Basic | 100 active | No |
  | Pro | 1,000 active | Selected shots optional |
  | Unlimited | Unlimited | Full storage |

- [ ] **Trial period** — optional 7-day free trial on Basic/Pro?
  (Add `trial_period_days: 7` to Stripe price if desired)

- [ ] **Refund policy** — 24–48 hr window? Document in Terms.

---

## ✅ Pre-launch verification

- [ ] App builds without Secrets.plist (LocalBackendService fallback works)
- [ ] App signs in with Supabase when Secrets.plist is present
- [ ] Stripe test checkout completes
- [ ] `user_entitlements` row updates after checkout
- [ ] Webhook events appear in Stripe Dashboard
- [ ] Website runs locally: `npm run dev`
- [ ] All 8 website pages render
- [ ] Stripe Customer Portal opens from /account

---

## 🚫 Security reminder

- Do **NOT** commit `Secrets.plist`, `.env.local`, or any file with real keys.
- Do **NOT** put `SUPABASE_SERVICE_ROLE_KEY` or `STRIPE_SECRET_KEY` anywhere in the iOS app bundle or website frontend.
- Rotate any key that was accidentally committed before going to production.
