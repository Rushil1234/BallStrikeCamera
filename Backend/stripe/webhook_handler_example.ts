// True Carry — Stripe Webhook Handler (Deno / Supabase Edge Function)
// Deploy as: supabase functions deploy stripe-webhook
//
// Set secrets:
//   supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_...
//   supabase secrets set STRIPE_SECRET_KEY=sk_...
//   supabase secrets set SUPABASE_SERVICE_ROLE_KEY=...
//   supabase secrets set SUPABASE_URL=https://YOUR_PROJECT.supabase.co

import Stripe from "npm:stripe@14";
import { createClient } from "npm:@supabase/supabase-js@2";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2024-04-10",
});

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

const TIER_MAP: Record<string, string> = {
  basic:     "basic",
  pro:       "pro",
  premium:   "pro",
  atlas:     "unlimited",
  unlimited: "unlimited",
};

Deno.serve(async (req: Request) => {
  const body = await req.text();
  const sig  = req.headers.get("stripe-signature") ?? "";

  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(
      body,
      sig,
      Deno.env.get("STRIPE_WEBHOOK_SECRET")!
    );
  } catch (err) {
    console.error("Webhook signature verification failed:", err);
    return new Response("Bad signature", { status: 400 });
  }

  switch (event.type) {
    case "checkout.session.completed": {
      const session = event.data.object as Stripe.Checkout.Session;
      await handleCheckoutCompleted(session);
      break;
    }
    case "customer.subscription.updated": {
      const sub = event.data.object as Stripe.Subscription;
      await handleSubscriptionUpdated(sub);
      break;
    }
    case "customer.subscription.deleted": {
      const sub = event.data.object as Stripe.Subscription;
      await handleSubscriptionDeleted(sub);
      break;
    }
    case "invoice.payment_failed": {
      const inv = event.data.object as Stripe.Invoice;
      await handlePaymentFailed(inv);
      break;
    }
    default:
      console.log("Unhandled event type:", event.type);
  }

  return new Response("OK", { status: 200 });
});

// ── Handlers ──────────────────────────────────────────────────────────────────

async function handleCheckoutCompleted(session: Stripe.Checkout.Session) {
  const userId = session.metadata?.supabase_user_id;
  const tier   = session.metadata?.app_tier;
  if (!userId || !tier) return;

  const sub = await stripe.subscriptions.retrieve(session.subscription as string);
  await upsertEntitlement({
    userId,
    tier: TIER_MAP[tier] ?? "basic",
    paymentStatus: sub.status,
    stripeCustomerId: session.customer as string,
    stripeSubscriptionId: sub.id,
    currentPeriodStart: new Date(sub.current_period_start * 1000).toISOString(),
    currentPeriodEnd:   new Date(sub.current_period_end   * 1000).toISOString(),
    cancelAtPeriodEnd:  sub.cancel_at_period_end,
  });
}

async function handleSubscriptionUpdated(sub: Stripe.Subscription) {
  const userId = sub.metadata?.supabase_user_id;
  const tier   = sub.metadata?.app_tier;
  if (!userId) return;

  await upsertEntitlement({
    userId,
    tier: TIER_MAP[tier ?? ""] ?? "free",
    paymentStatus: sub.status,
    stripeCustomerId: sub.customer as string,
    stripeSubscriptionId: sub.id,
    currentPeriodStart: new Date(sub.current_period_start * 1000).toISOString(),
    currentPeriodEnd:   new Date(sub.current_period_end   * 1000).toISOString(),
    cancelAtPeriodEnd:  sub.cancel_at_period_end,
  });
}

async function handleSubscriptionDeleted(sub: Stripe.Subscription) {
  const userId = sub.metadata?.supabase_user_id;
  if (!userId) return;

  await upsertEntitlement({
    userId,
    tier: "free",
    paymentStatus: "canceled",
    stripeCustomerId: sub.customer as string,
    stripeSubscriptionId: sub.id,
    cancelAtPeriodEnd: false,
  });
}

async function handlePaymentFailed(inv: Stripe.Invoice) {
  const sub = inv.subscription
    ? await stripe.subscriptions.retrieve(inv.subscription as string)
    : null;
  if (!sub) return;

  const userId = sub.metadata?.supabase_user_id;
  if (!userId) return;

  await upsertEntitlement({
    userId,
    tier: sub.metadata?.app_tier ? (TIER_MAP[sub.metadata.app_tier] ?? "free") : "free",
    paymentStatus: "past_due",
    stripeCustomerId: sub.customer as string,
    stripeSubscriptionId: sub.id,
    cancelAtPeriodEnd: sub.cancel_at_period_end,
  });
}

// ── Supabase upsert ───────────────────────────────────────────────────────────

interface EntitlementUpsert {
  userId: string;
  tier: string;
  paymentStatus: string;
  stripeCustomerId?: string;
  stripeSubscriptionId?: string;
  currentPeriodStart?: string;
  currentPeriodEnd?: string;
  cancelAtPeriodEnd?: boolean;
}

async function upsertEntitlement(e: EntitlementUpsert) {
  const { error } = await supabase
    .from("user_entitlements")
    .upsert({
      user_id:                  e.userId,
      tier:                     e.tier,
      payment_status:           e.paymentStatus,
      stripe_customer_id:       e.stripeCustomerId,
      stripe_subscription_id:   e.stripeSubscriptionId,
      current_period_start:     e.currentPeriodStart,
      current_period_end:       e.currentPeriodEnd,
      cancel_at_period_end:     e.cancelAtPeriodEnd ?? false,
      updated_at:               new Date().toISOString(),
    }, { onConflict: "user_id" });

  if (error) {
    console.error("Failed to upsert entitlement:", error);
    throw error;
  }
}
