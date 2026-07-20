// True Carry — Stripe Webhook Edge Function
// Deploy: supabase functions deploy stripe-webhook
// All secrets via: supabase secrets set KEY=value  (never hardcode here)

import Stripe from "npm:stripe@14";
import { createClient } from "npm:@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

// API version is pinned intentionally. This handler reads
// `subscription.current_period_start` / `current_period_end`, which were moved
// onto subscription *items* in the 2025-03-31 (basil) release. Do NOT bump this
// to a basil/dahlia version without also rewriting tierFromSubscription and the
// period-date reads below, or entitlements will be written with Invalid Dates.
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
  [Deno.env.get("STRIPE_ATLAS_MONTHLY_PRICE_ID") ?? ""]: "unlimited",
  // Yearly billing (site's default toggle) — without these, a yearly
  // subscriber would fall through to the "basic" default below.
  [Deno.env.get("STRIPE_PRO_YEARLY_PRICE_ID")   ?? ""]: "pro",
  [Deno.env.get("STRIPE_ATLAS_YEARLY_PRICE_ID") ?? ""]: "unlimited",
};
// Unset env vars all collapse onto the "" key — make sure that key can never
// match a real price id lookup.
delete PRICE_TO_TIER[""];

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
  // Gift-card purchases are one-time payments (no subscription, no logged-in
  // user). Branch before the subscription path, which requires both.
  if (session.metadata?.type === "giftcard") {
    await handleGiftCardPurchase(session);
    return;
  }

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

// ── Gift cards ──────────────────────────────────────────────────────────────

async function handleGiftCardPurchase(session: Stripe.Checkout.Session) {
  const amountCents = Number(session.metadata?.amountCents ?? session.amount_total ?? 0);
  const recipientEmail = session.metadata?.recipientEmail ?? "";
  const purchaserEmail = session.metadata?.purchaserEmail ?? session.customer_details?.email ?? "";
  const message = session.metadata?.message ?? "";

  if (![2500, 5000, 10000].includes(amountCents) || !recipientEmail) {
    console.error("[stripe-webhook] gift card: bad metadata", { amountCents, recipientEmail });
    return;
  }

  const code = generateGiftCode();
  const codeHash = await sha256Hex(code);

  // Idempotent on stripe_session_id: a re-delivered webhook hits the unique
  // constraint (23505) and we skip re-issuing / re-emailing.
  const { error } = await supabase.from("gift_cards").insert({
    code_hash: codeHash,
    amount_cents: amountCents,
    currency: session.currency ?? "usd",
    status: "active",
    purchaser_email: purchaserEmail || null,
    recipient_email: recipientEmail,
    message: message || null,
    stripe_session_id: session.id,
    stripe_payment_intent_id: (session.payment_intent as string) ?? null,
  });

  if (error) {
    if (error.code === "23505") {
      console.log("[stripe-webhook] gift card already issued for session", session.id);
      return;
    }
    console.error("[stripe-webhook] gift card insert error:", error);
    throw error;
  }

  console.log(`[stripe-webhook] Gift card issued — $${amountCents / 100} → ${recipientEmail}`);

  // Email is best-effort: the card exists regardless, and the code is
  // recoverable from the founder side if delivery hiccups.
  try {
    await sendGiftEmail({ code, amountCents, recipientEmail, purchaserEmail, message });
  } catch (err) {
    console.error("[stripe-webhook] gift card email failed (card still issued):", err);
  }
}

// TC-XXXX-XXXX-XXXX in Crockford base32 (no I,L,O,U — avoids ambiguity).
function generateGiftCode(): string {
  const alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
  const bytes = new Uint8Array(12);
  crypto.getRandomValues(bytes);
  const chars = Array.from(bytes, (b) => alphabet[b % alphabet.length]);
  const group = (i: number) => chars.slice(i, i + 4).join("");
  return `TC-${group(0)}-${group(4)}-${group(8)}`;
}

async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

async function sendGiftEmail(g: {
  code: string;
  amountCents: number;
  recipientEmail: string;
  purchaserEmail: string;
  message: string;
}) {
  const user = Deno.env.get("ZOHO_SMTP_USER");
  const pass = Deno.env.get("ZOHO_SMTP_PASSWORD");
  if (!user || !pass) {
    console.warn("[stripe-webhook] ZOHO_SMTP_* not set — skipping gift email");
    return;
  }
  const websiteURL = Deno.env.get("TRUECARRY_WEBSITE_URL") ?? "https://truecarry.golf";
  const dollars = g.amountCents / 100;
  const redeemUrl = `${websiteURL}/account?redeem=${g.code}`;
  const from = g.purchaserEmail ? `someone (${g.purchaserEmail})` : "someone";

  const html = `
  <div style="font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;max-width:520px;margin:0 auto;color:#16201a">
    <p style="font-family:Georgia,serif;font-size:26px;color:#1E2A22;margin:0 0 6px">True <em style="color:#8C7240">Carry.</em></p>
    <h1 style="font-size:22px;margin:18px 0 6px">You&rsquo;ve got a gift card.</h1>
    <p style="font-size:15px;line-height:1.6;color:#5C5A4F;margin:0 0 20px">
      ${from} sent you a <strong>$${dollars}</strong> True Carry gift card &mdash; credit toward Pro or Atlas.
    </p>
    ${g.message ? `<p style="font-size:15px;font-style:italic;line-height:1.6;color:#5C5A4F;border-left:3px solid #B89A5E;padding-left:14px;margin:0 0 20px">&ldquo;${escapeHtml(g.message)}&rdquo;</p>` : ""}
    <div style="background:#F4EFE2;border:1px solid #B89A5E;border-radius:10px;padding:18px;text-align:center;margin:0 0 20px">
      <div style="font-family:mono,Menlo,monospace;font-size:11px;letter-spacing:.18em;text-transform:uppercase;color:#8A8576;margin-bottom:6px">Your code</div>
      <div style="font-family:mono,Menlo,monospace;font-size:22px;letter-spacing:.12em;color:#16201a">${g.code}</div>
    </div>
    <a href="${redeemUrl}" style="display:inline-block;background:#16201a;color:#F4EFE2;text-decoration:none;font-size:14px;padding:13px 26px;border-radius:999px">Redeem it &rarr;</a>
    <p style="font-size:12.5px;line-height:1.6;color:#8A8576;margin:22px 0 0">
      Redeem at ${websiteURL}/account &mdash; the credit comes off your next plan automatically. Never expires.
    </p>
  </div>`;

  const text =
    `You've got a $${dollars} True Carry gift card.\n\n` +
    (g.message ? `"${g.message}"\n\n` : "") +
    `Code: ${g.code}\nRedeem: ${redeemUrl}\n\n` +
    `The credit applies to your next Pro or Atlas plan automatically. Never expires.`;

  const client = new SMTPClient({
    connection: { hostname: "smtp.zoho.com", port: 465, tls: true, auth: { username: user, password: pass } },
  });
  await client.send({
    from: `True Carry <${user}>`,
    to: g.recipientEmail,
    subject: `Your $${dollars} True Carry gift card`,
    content: text,
    html,
  });
  await client.close();
  console.log(`[stripe-webhook] Gift email sent to ${g.recipientEmail}`);
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string)
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function tierFromSubscription(sub: Stripe.Subscription): string {
  const priceId = sub.items.data[0]?.price?.id ?? "";
  return normalizeTier(PRICE_TO_TIER[priceId] ?? sub.metadata?.app_tier ?? "basic");
}

function normalizeTier(tier: string): string {
  if (tier === "atlas") return "unlimited";
  if (tier === "premium") return "pro";
  return tier;
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
