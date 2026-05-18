// True Carry — Create Stripe Customer Portal Session Edge Function
// Deploy: supabase functions deploy create-customer-portal-session
// Called by: website /account page "Manage Billing" button.

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

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

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

  // Get Stripe customer ID from entitlements table
  const { data: entRow, error: dbErr } = await supabase
    .from("user_entitlements")
    .select("stripe_customer_id, tier")
    .eq("user_id", user.id)
    .maybeSingle();

  if (dbErr) {
    console.error("[create-customer-portal-session] DB error:", dbErr);
    return json({ error: "Database error" }, 500);
  }

  const customerId = entRow?.stripe_customer_id as string | undefined;
  if (!customerId) {
    return json({ error: "No Stripe customer found. Please subscribe first." }, 400);
  }

  try {
    const portalSession = await stripe.billingPortal.sessions.create({
      customer:   customerId,
      return_url: `${websiteURL}/account`,
    });
    return json({ url: portalSession.url }, 200);
  } catch (err) {
    console.error("[create-customer-portal-session] Stripe error:", err);
    return json({ error: "Failed to create portal session" }, 500);
  }
});

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}
