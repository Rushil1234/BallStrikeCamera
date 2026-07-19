// True Carry — Create Stripe Checkout Session Edge Function
// Deploy: supabase functions deploy create-checkout-session
// Called by: website /pricing page when user clicks upgrade button.

import Stripe from "npm:stripe@21";
import { createClient } from "npm:@supabase/supabase-js@2";

// Pinned explicitly so SDK updates can't silently change checkout behaviour.
// This surface intentionally runs a newer (dahlia) API version than the webhook
// because it relies on the embedded Checkout params (ui_mode "embedded_page",
// redirect_on_completion). It does not read subscription period fields, so the
// 2025-03-31 (basil) period-field move does not affect it.
const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2026-05-27.dahlia",
  httpClient: Stripe.createFetchHttpClient(),
});

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

const websiteURL = Deno.env.get("TRUECARRY_WEBSITE_URL") ?? "https://truecarry.app";

const PRICE_IDS: Record<string, Record<string, string>> = {
  pro: {
    monthly: Deno.env.get("STRIPE_PRO_MONTHLY_PRICE_ID") ?? "",
    yearly:  Deno.env.get("STRIPE_PRO_YEARLY_PRICE_ID")  ?? "",
  },
  atlas: {
    monthly: Deno.env.get("STRIPE_ATLAS_MONTHLY_PRICE_ID") ?? "",
    yearly:  Deno.env.get("STRIPE_ATLAS_YEARLY_PRICE_ID")  ?? "",
  },
};

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  // Verify caller is authenticated
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "Missing Authorization header" }, 401);
  }

  const { data: { user }, error: authErr } = await supabase.auth.getUser(
    authHeader.replace("Bearer ", "")
  );
  if (authErr || !user) {
    return json({ error: "Unauthorized" }, 401);
  }

  let body: { tier?: string; billingInterval?: string; uiMode?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const tier            = (body.tier ?? "pro").toLowerCase();
  const billingInterval = (body.billingInterval ?? "monthly").toLowerCase();
  const useEmbeddedCheckout = (body.uiMode ?? "").toLowerCase() === "embedded";

  const priceId = PRICE_IDS[tier]?.[billingInterval];
  if (!priceId) {
    return json({ error: `Unknown tier/interval: ${tier}/${billingInterval}` }, 400);
  }

  // Look up the caller's current entitlement (customer + premium status).
  const { data: entRow } = await supabase
    .from("user_entitlements")
    .select("stripe_customer_id, tier, payment_status, comp_pro_until")
    .eq("user_id", user.id)
    .maybeSingle();

  // Guard: never open a new subscription checkout for someone who already has
  // premium access. Without this a subscribed user (or a comped/founder account)
  // who clicks "Get the app" would be charged for a SECOND subscription. This
  // mirrors the website's hasPremiumAccess() so both sides agree.
  const compActive =
    Boolean(entRow?.comp_pro_until) &&
    new Date(entRow!.comp_pro_until as string) > new Date();
  const stripeActive =
    (entRow?.tier ?? "free") !== "free" &&
    ["active", "trialing"].includes((entRow?.payment_status as string) ?? "");
  if (compActive || stripeActive) {
    return json(
      {
        alreadySubscribed: true,
        tier: entRow?.tier ?? null,
        reason: compActive ? "comp_pro" : "active_subscription",
      },
      200
    );
  }

  const existingCustomer = entRow?.stripe_customer_id as string | undefined;

  const sessionParams: Stripe.Checkout.SessionCreateParams = {
    mode: "subscription",
    payment_method_types: ["card"],
    line_items: [{ price: priceId, quantity: 1 }],
    client_reference_id: user.id,
    metadata: {
      supabase_user_id: user.id,
      tier,
    },
    subscription_data: {
      metadata: {
        supabase_user_id: user.id,
        app_tier: tier,
      },
    },
    ...(useEmbeddedCheckout
      ? {
          ui_mode: "embedded_page",
          return_url: `${websiteURL}/billing/success?session_id={CHECKOUT_SESSION_ID}`,
          redirect_on_completion: "if_required",
        }
      : {
          success_url: `${websiteURL}/billing/success?session_id={CHECKOUT_SESSION_ID}`,
          cancel_url: `${websiteURL}/billing/cancel`,
        }),
  };

  if (existingCustomer) {
    sessionParams.customer = existingCustomer;
  } else {
    sessionParams.customer_email = user.email;
  }

  try {
    let checkoutSession;
    if (useEmbeddedCheckout) {
      // Stripe renamed the embedded ui_mode ("embedded" <-> "embedded_page")
      // across API versions. Try the current value, fall back to the legacy one.
      try {
        checkoutSession = await stripe.checkout.sessions.create(sessionParams);
      } catch (e) {
        console.warn("[create-checkout-session] embedded_page failed, retrying ui_mode=embedded:", e);
        checkoutSession = await stripe.checkout.sessions.create({
          ...sessionParams,
          ui_mode: "embedded" as Stripe.Checkout.SessionCreateParams.UiMode,
        });
      }
    } else {
      checkoutSession = await stripe.checkout.sessions.create(sessionParams);
    }
    return json({
      url: checkoutSession.url,
      clientSecret: checkoutSession.client_secret,
    }, 200);
  } catch (err) {
    console.error("[create-checkout-session] Stripe error:", err);
    return json({ error: "Failed to create checkout session" }, 500);
  }
});

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}
