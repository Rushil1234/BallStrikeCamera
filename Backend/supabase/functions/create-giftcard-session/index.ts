// True Carry — Create Gift-Card Checkout Session
// Deploy: supabase functions deploy create-giftcard-session
// Called by: website /store GiftCardPanel. No auth — anyone can buy a gift card
// (including for someone else). One-time PAYMENT session (not a subscription).

import Stripe from "npm:stripe@21";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2026-05-27.dahlia",
  httpClient: Stripe.createFetchHttpClient(),
});

const websiteURL = Deno.env.get("TRUECARRY_WEBSITE_URL") ?? "https://truecarry.golf";

// The ONLY amounts we sell. Never trust a client-supplied number against this.
const ALLOWED_CENTS = new Set([2500, 5000, 10000]);
const EMAIL_RE = /^[^@\s]+@[^@\s.]+\.[^@\s]+$/;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let body: {
    amountCents?: number;
    recipientEmail?: string;
    purchaserEmail?: string;
    message?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const amountCents = Number(body.amountCents);
  const recipientEmail = (body.recipientEmail ?? "").trim().toLowerCase();
  const purchaserEmail = (body.purchaserEmail ?? "").trim().toLowerCase();
  const message = (body.message ?? "").trim().slice(0, 500);

  if (!ALLOWED_CENTS.has(amountCents)) {
    return json({ error: "Pick a gift amount of $25, $50, or $100." }, 400);
  }
  if (!EMAIL_RE.test(recipientEmail)) {
    return json({ error: "Enter a valid recipient email." }, 400);
  }
  if (!EMAIL_RE.test(purchaserEmail)) {
    return json({ error: "Enter a valid email for your receipt." }, 400);
  }

  const dollars = amountCents / 100;
  // Metadata rides on BOTH the session and the payment intent so the webhook
  // can read it from checkout.session.completed regardless of expansion.
  const meta: Record<string, string> = {
    type: "giftcard",
    amountCents: String(amountCents),
    recipientEmail,
    purchaserEmail,
    message,
  };

  try {
    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      payment_method_types: ["card"],
      customer_email: purchaserEmail,
      line_items: [
        {
          quantity: 1,
          price_data: {
            currency: "usd",
            unit_amount: amountCents,
            product_data: {
              name: `True Carry Gift Card — $${dollars}`,
              description: `Store credit for ${recipientEmail}. Redeemable against Pro or Atlas.`,
            },
          },
        },
      ],
      metadata: meta,
      payment_intent_data: { metadata: meta },
      success_url: `${websiteURL}/store?gift=success`,
      cancel_url: `${websiteURL}/store?gift=cancel`,
    });

    return json({ url: session.url }, 200);
  } catch (err) {
    console.error("[create-giftcard-session] Stripe error:", err);
    return json({ error: "Could not start checkout. Please try again." }, 500);
  }
});

function json(data: unknown, status: number) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}
