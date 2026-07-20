// True Carry — Redeem Gift Card
// Deploy: supabase functions deploy redeem-gift-card
// Called by: website /account redeem field. Authenticated. Atomically claims a
// gift card and adds its value as Stripe customer-balance credit, which Stripe
// auto-applies to the user's next Pro/Atlas invoice.

import Stripe from "npm:stripe@21";
import { createClient } from "npm:@supabase/supabase-js@2";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2026-05-27.dahlia",
  httpClient: Stripe.createFetchHttpClient(),
});

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Codes are TC-XXXX-XXXX-XXXX in Crockford base32. Validate the shape so we
// never hash arbitrary input; the ~10^18 keyspace is the real brute-force guard.
const CODE_RE = /^TC-[0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{4}$/;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  // 1. Authenticate the caller.
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Sign in to redeem a gift card." }, 401);
  const { data: { user }, error: authErr } = await supabase.auth.getUser(
    authHeader.replace("Bearer ", "")
  );
  if (authErr || !user) return json({ error: "Unauthorized" }, 401);

  // 2. Normalize + validate the code.
  let body: { code?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request." }, 400);
  }
  const code = (body.code ?? "").trim().toUpperCase().replace(/\s+/g, "");
  if (!CODE_RE.test(code)) {
    return json({ error: "That doesn't look like a gift card code." }, 400);
  }
  const codeHash = await sha256Hex(code);

  // 3. Atomically claim the card (marks redeemed, returns amount or null).
  const { data: amountCents, error: claimErr } = await supabase.rpc("claim_gift_card", {
    p_user: user.id,
    p_code_hash: codeHash,
  });
  if (claimErr) {
    console.error("[redeem-gift-card] claim error:", claimErr);
    return json({ error: "Could not redeem right now. Try again." }, 500);
  }
  if (!amountCents) {
    // Generic on purpose — don't reveal whether a code exists.
    return json({ error: "This code is invalid or has already been used." }, 400);
  }

  // 4. Ensure the user has a Stripe customer (so the credit applies at checkout).
  let customerId: string | undefined;
  try {
    const { data: ent } = await supabase
      .from("user_entitlements")
      .select("stripe_customer_id")
      .eq("user_id", user.id)
      .maybeSingle();
    customerId = ent?.stripe_customer_id ?? undefined;

    if (!customerId) {
      const customer = await stripe.customers.create({
        email: user.email,
        metadata: { supabase_user_id: user.id },
      });
      customerId = customer.id;
      await supabase
        .from("user_entitlements")
        .update({ stripe_customer_id: customerId, updated_at: new Date().toISOString() })
        .eq("user_id", user.id);
    }

    // 5. Add the credit (negative balance = money owed TO the customer).
    const tx = await stripe.customers.createBalanceTransaction(customerId, {
      amount: -amountCents,
      currency: "usd",
      description: `Gift card redemption (${code.slice(0, 5)}…)`,
    });

    return json(
      {
        ok: true,
        amountCents,
        creditBalanceCents: -(tx.ending_balance ?? -amountCents), // report as positive credit
      },
      200
    );
  } catch (err) {
    // 6. Stripe failed after we claimed the row — revert so the code still works.
    console.error("[redeem-gift-card] Stripe credit failed, reverting claim:", err);
    await supabase.rpc("unclaim_gift_card", { p_user: user.id, p_code_hash: codeHash });
    return json({ error: "Could not apply the credit. Please try again." }, 500);
  }
});

async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

function json(data: unknown, status: number) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}
