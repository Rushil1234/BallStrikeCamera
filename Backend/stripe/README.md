# Stripe Setup — True Carry

## Architecture

The iOS app and website **never** hold Stripe secret keys.
All Stripe API calls happen in Supabase Edge Functions, which read secrets from environment variables.

```
User → Website /pricing → create-checkout-session (Edge Fn) → Stripe Checkout
Stripe event → stripe-webhook (Edge Fn) → upsert user_entitlements in Supabase
iOS app → SupabaseBackendService → reads user_entitlements → EntitlementViewModel
```

---

## Step-by-step Stripe setup

### 1. Create Stripe account
https://dashboard.stripe.com/register

### 2. Create Products

In Dashboard → Product catalog → Add product:

| Product | Price model |
|---------|-------------|
| True Carry Basic | Recurring |
| True Carry Pro | Recurring |
| True Carry Unlimited | Recurring |

For each product, create **two prices** (monthly + yearly):

| Product | Monthly | Yearly |
|---------|---------|--------|
| Basic | $9.99/mo | $79.99/yr |
| Pro | $19.99/mo | $159.99/yr |
| Unlimited | $39.99/mo | $319.99/yr |

### 3. Copy price IDs

Each price gets an ID like `price_1PxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxA`.
Copy all 6 and add them to Supabase secrets:

```bash
supabase secrets set STRIPE_BASIC_MONTHLY_PRICE_ID=price_...
supabase secrets set STRIPE_BASIC_YEARLY_PRICE_ID=price_...
supabase secrets set STRIPE_PRO_MONTHLY_PRICE_ID=price_...
supabase secrets set STRIPE_PRO_YEARLY_PRICE_ID=price_...
supabase secrets set STRIPE_UNLIMITED_MONTHLY_PRICE_ID=price_...
supabase secrets set STRIPE_UNLIMITED_YEARLY_PRICE_ID=price_...
```

### 4. Add Stripe secret key to Supabase

Dashboard → Developers → API keys → copy **Secret key** (starts with `sk_live_` or `sk_test_`).

```bash
supabase secrets set STRIPE_SECRET_KEY=sk_live_...
```

### 5. Deploy Edge Functions

```bash
supabase functions deploy create-checkout-session
supabase functions deploy create-customer-portal-session
supabase functions deploy stripe-webhook
```

### 6. Register Stripe webhook

Stripe Dashboard → Developers → Webhooks → Add endpoint

- **Endpoint URL:**
  `https://aoxturoezgecwceudeef.functions.supabase.co/stripe-webhook`

- **Events to listen for:**
  - `checkout.session.completed`
  - `customer.subscription.created`
  - `customer.subscription.updated`
  - `customer.subscription.deleted`
  - `invoice.payment_succeeded`
  - `invoice.payment_failed`

### 7. Add webhook signing secret

After creating the webhook, reveal the **Signing secret** (`whsec_...`) and add it:

```bash
supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_...
```

### 8. Subscription metadata requirement

The `create-checkout-session` Edge Function sets `client_reference_id` and `subscription_data.metadata.supabase_user_id` on every checkout session.
The webhook uses this to match Stripe subscriptions to Supabase users.

**Required:** users must be logged in on the website before clicking Upgrade.

### 9. Test the flow (test mode)

1. Use Stripe test mode keys (`sk_test_...`, `whsec_test_...`).
2. Use test card `4242 4242 4242 4242`, any future date, any CVC.
3. Complete checkout → check `user_entitlements` table in Supabase.
4. Cancel subscription → verify `payment_status = 'canceled'` and `tier = 'free'`.

### 10. Customer Portal setup

Dashboard → Settings → Billing → Customer portal

Enable:
- Cancel subscriptions
- Upgrade/downgrade subscriptions
- Update payment method

The `create-customer-portal-session` function creates a portal session for the logged-in user.

---

## Security reminders

- `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET` are **only** in Supabase secrets.
- Never put them in the website frontend, iOS app, or `.env.local`.
- The webhook always verifies the Stripe signature before trusting the event.
- Rotate any key exposed in source control immediately.
