// True Carry — Create Stripe Checkout Session Edge Function
// Deploy: supabase functions deploy create-checkout-session
// Called by: website /pricing page when user clicks upgrade button.

import Stripe from "npm:stripe@14";
import { createClient } from "npm:@supabase/supabase-js@2";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2024-04-10",
  httpClient: Stripe.createFetchHttpClient(),
});

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

const websiteURL = Deno.env.get("TRUECARRY_WEBSITE_URL") ?? "https://truecarry.app";

const PRICE_IDS: Record<string, Record<string, string>> = {
  basic:     { monthly: Deno.env.get("STRIPE_BASIC_MONTHLY_PRICE_ID")     ?? "", yearly: Deno.env.get("STRIPE_BASIC_YEARLY_PRICE_ID")     ?? "" },
  pro:       { monthly: Deno.env.get("STRIPE_PRO_MONTHLY_PRICE_ID")       ?? "", yearly: Deno.env.get("STRIPE_PRO_YEARLY_PRICE_ID")       ?? "" },
  unlimited: { monthly: Deno.env.get("STRIPE_UNLIMITED_MONTHLY_PRICE_ID") ?? "", yearly: Deno.env.get("STRIPE_UNLIMITED_YEARLY_PRICE_ID") ?? "" },
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

  let body: { tier?: string; billingInterval?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const tier            = (body.tier ?? "pro").toLowerCase();
  const billingInterval = (body.billingInterval ?? "monthly").toLowerCase();

  const priceId = PRICE_IDS[tier]?.[billingInterval];
  if (!priceId) {
    return json({ error: `Unknown tier/interval: ${tier}/${billingInterval}` }, 400);
  }

  // Look up or keep existing Stripe customer
  const { data: entRow } = await supabase
    .from("user_entitlements")
    .select("stripe_customer_id")
    .eq("user_id", user.id)
    .maybeSingle();

  const customerParams: Stripe.Checkout.SessionCreateParams["customer_creation"] = undefined;
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
    success_url: `${websiteURL}/billing/success?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url:  `${websiteURL}/billing/cancel`,
  };

  if (existingCustomer) {
    sessionParams.customer = existingCustomer;
  } else {
    sessionParams.customer_email = user.email;
  }

  try {
    const checkoutSession = await stripe.checkout.sessions.create(sessionParams);
    return json({ url: checkoutSession.url }, 200);
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
