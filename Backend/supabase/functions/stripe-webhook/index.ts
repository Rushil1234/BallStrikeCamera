// True Carry — Stripe Webhook Edge Function
// Deploy: supabase functions deploy stripe-webhook
// All secrets via: supabase secrets set KEY=value  (never hardcode here)

import Stripe from "npm:stripe@14";
import { createClient } from "npm:@supabase/supabase-js@2";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2024-04-10",
  httpClient: Stripe.createFetchHttpClient(),
});

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!  // service role — only in Edge Function
);

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "stripe-signature, content-type",
};

const PRICE_TO_TIER: Record<string, string> = {
  [Deno.env.get("STRIPE_BASIC_MONTHLY_PRICE_ID") ?? ""]: "basic",
  [Deno.env.get("STRIPE_PRO_MONTHLY_PRICE_ID")   ?? ""]: "pro",
  [Deno.env.get("STRIPE_ATLAS_MONTHLY_PRICE_ID") ?? ""]: "atlas",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  const body = await req.text();
  const sig  = req.headers.get("stripe-signature") ?? "";

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      body,
      sig,
      Deno.env.get("STRIPE_WEBHOOK_SECRET")!
    );
  } catch (err) {
    console.error("[stripe-webhook] Signature verification failed:", err);
    return new Response("Bad signature", { status: 400, headers: CORS_HEADERS });
  }

  console.log("[stripe-webhook] Event:", event.type);

  try {
    switch (event.type) {
      case "checkout.session.completed":
        await handleCheckoutCompleted(event.data.object as Stripe.Checkout.Session);
        break;
      case "customer.subscription.created":
      case "customer.subscription.updated":
        await handleSubscriptionUpsert(event.data.object as Stripe.Subscription);
        break;
      case "customer.subscription.deleted":
        await handleSubscriptionDeleted(event.data.object as Stripe.Subscription);
        break;
      case "invoice.payment_succeeded":
        await handlePaymentSucceeded(event.data.object as Stripe.Invoice);
        break;
      case "invoice.payment_failed":
        await handlePaymentFailed(event.data.object as Stripe.Invoice);
        break;
      default:
        console.log("[stripe-webhook] Unhandled event:", event.type);
    }
  } catch (err) {
    console.error("[stripe-webhook] Handler error:", err);
    return new Response("Handler error", { status: 500, headers: CORS_HEADERS });
  }

  return new Response("OK", { status: 200, headers: CORS_HEADERS });
});

// ── Handlers ──────────────────────────────────────────────────────────────────

async function handleCheckoutCompleted(session: Stripe.Checkout.Session) {
  const userId = session.client_reference_id ?? session.metadata?.supabase_user_id;
  if (!userId) {
    console.error("[stripe-webhook] checkout.session.completed: no userId in metadata");
    return;
  }

  const subId = session.subscription as string;
  if (!subId) return;

  const sub  = await stripe.subscriptions.retrieve(subId);
  const tier = tierFromSubscription(sub);

  await upsertEntitlement({
    userId,
    tier,
    paymentStatus: sub.status,
    stripeCustomerId:     session.customer as string,
    stripeSubscriptionId: sub.id,
    currentPeriodStart:   new Date(sub.current_period_start * 1000).toISOString(),
    currentPeriodEnd:     new Date(sub.current_period_end   * 1000).toISOString(),
    cancelAtPeriodEnd:    sub.cancel_at_period_end,
  });
  console.log(`[stripe-webhook] Checkout complete — user=${userId} tier=${tier}`);
}

async function handleSubscriptionUpsert(sub: Stripe.Subscription) {
  const userId = sub.metadata?.supabase_user_id;
  if (!userId) {
    console.warn("[stripe-webhook] subscription upsert: no supabase_user_id in metadata");
    return;
  }

  const tier = tierFromSubscription(sub);
  await upsertEntitlement({
    userId,
    tier,
    paymentStatus:        sub.status,
    stripeCustomerId:     sub.customer as string,
    stripeSubscriptionId: sub.id,
    currentPeriodStart:   new Date(sub.current_period_start * 1000).toISOString(),
    currentPeriodEnd:     new Date(sub.current_period_end   * 1000).toISOString(),
    cancelAtPeriodEnd:    sub.cancel_at_period_end,
  });
  console.log(`[stripe-webhook] Subscription upserted — user=${userId} tier=${tier} status=${sub.status}`);
}

async function handleSubscriptionDeleted(sub: Stripe.Subscription) {
  const userId = sub.metadata?.supabase_user_id;
  if (!userId) return;

  await upsertEntitlement({
    userId,
    tier: "free",
    paymentStatus:        "canceled",
    stripeCustomerId:     sub.customer as string,
    stripeSubscriptionId: sub.id,
    cancelAtPeriodEnd:    false,
  });
  console.log(`[stripe-webhook] Subscription deleted — user=${userId} → free`);
}

async function handlePaymentSucceeded(inv: Stripe.Invoice) {
  if (!inv.subscription) return;
  const sub = await stripe.subscriptions.retrieve(inv.subscription as string);
  await handleSubscriptionUpsert(sub);
}

async function handlePaymentFailed(inv: Stripe.Invoice) {
  if (!inv.subscription) return;
  const sub    = await stripe.subscriptions.retrieve(inv.subscription as string);
  const userId = sub.metadata?.supabase_user_id;
  if (!userId) return;

  await upsertEntitlement({
    userId,
    tier:                 tierFromSubscription(sub),
    paymentStatus:        "past_due",
    stripeCustomerId:     sub.customer as string,
    stripeSubscriptionId: sub.id,
    cancelAtPeriodEnd:    sub.cancel_at_period_end,
  });
  console.log(`[stripe-webhook] Payment failed — user=${userId}`);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function tierFromSubscription(sub: Stripe.Subscription): string {
  const priceId = sub.items.data[0]?.price.id ?? "";
  return PRICE_TO_TIER[priceId] ?? sub.metadata?.app_tier ?? "basic";
}

interface EntitlementRow {
  userId: string;
  tier: string;
  paymentStatus: string;
  stripeCustomerId?: string;
  stripeSubscriptionId?: string;
  currentPeriodStart?: string;
  currentPeriodEnd?: string;
  cancelAtPeriodEnd?: boolean;
}

async function upsertEntitlement(e: EntitlementRow) {
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
    console.error("[stripe-webhook] upsertEntitlement error:", error);
    throw error;
  }
}
