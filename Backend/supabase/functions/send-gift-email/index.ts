// True Carry — Send Gift-Card Email (HTTP, Resend)
// Deploy: supabase functions deploy send-gift-email
//
// WHY HTTP, NOT SMTP: raw SMTP (denomailer) exceeds the Supabase Edge Function
// compute limit on the Free plan (WORKER_RESOURCE_LIMIT / 546). A plain fetch to
// an HTTP email API is lightweight and reliable.
//
// Secrets (env): RESEND_API_KEY, optional RESEND_FROM (a verified sender; until a
// domain is verified in Resend, use onboarding@resend.dev which only delivers to
// the Resend account owner's own address). GIFT_EMAIL_KEY gates internal calls.

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-gift-key",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const key = Deno.env.get("GIFT_EMAIL_KEY");
  if (!key || req.headers.get("x-gift-key") !== key) {
    return json({ error: "Forbidden" }, 403);
  }

  let g: {
    code?: string; amountCents?: number; recipientEmail?: string;
    purchaserEmail?: string; message?: string;
  };
  try {
    g = await req.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }
  if (!g.code || !g.recipientEmail || !g.amountCents) {
    return json({ error: "Missing fields" }, 400);
  }

  const apiKey = Deno.env.get("RESEND_API_KEY") ?? (await vaultSecret("RESEND_API_KEY"));
  if (!apiKey) return json({ error: "RESEND_API_KEY not configured" }, 500);
  const from =
    Deno.env.get("RESEND_FROM") ??
    (await vaultSecret("RESEND_FROM")) ??
    "True Carry <onboarding@resend.dev>";

  const websiteURL = Deno.env.get("TRUECARRY_WEBSITE_URL") ?? "https://truecarry.golf";
  const dollars = g.amountCents / 100;
  const redeemUrl = `${websiteURL}/account?redeem=${g.code}`;
  const fromWho = g.purchaserEmail ? `someone (${g.purchaserEmail})` : "someone";

  const html = `
  <div style="font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;max-width:520px;margin:0 auto;color:#16201a">
    <p style="font-family:Georgia,serif;font-size:26px;color:#1E2A22;margin:0 0 6px">True <em style="color:#8C7240">Carry.</em></p>
    <h1 style="font-size:22px;margin:18px 0 6px">You&rsquo;ve got a gift card.</h1>
    <p style="font-size:15px;line-height:1.6;color:#5C5A4F;margin:0 0 20px">
      ${fromWho} sent you a <strong>$${dollars}</strong> True Carry gift card &mdash; credit toward Pro or Atlas.
    </p>
    ${g.message ? `<p style="font-size:15px;font-style:italic;line-height:1.6;color:#5C5A4F;border-left:3px solid #B89A5E;padding-left:14px;margin:0 0 20px">&ldquo;${escapeHtml(g.message)}&rdquo;</p>` : ""}
    <div style="background:#F4EFE2;border:1px solid #B89A5E;border-radius:10px;padding:18px;text-align:center;margin:0 0 20px">
      <div style="font-family:monospace;font-size:11px;letter-spacing:.18em;text-transform:uppercase;color:#8A8576;margin-bottom:6px">Your code</div>
      <div style="font-family:monospace;font-size:22px;letter-spacing:.12em;color:#16201a">${escapeHtml(g.code)}</div>
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

  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from,
        to: [g.recipientEmail],
        subject: `Your $${dollars} True Carry gift card`,
        html,
        text,
      }),
    });
    const bodyText = await res.text();
    if (!res.ok) {
      console.error("[send-gift-email] Resend error:", res.status, bodyText);
      return json({ error: "email provider rejected", status: res.status, detail: bodyText.slice(0, 400) }, 502);
    }
    return json({ ok: true, sentTo: g.recipientEmail, provider: JSON.parse(bodyText || "{}") }, 200);
  } catch (err) {
    console.error("[send-gift-email] send failed:", err);
    return json({ error: String(err) }, 502);
  }
});

async function vaultSecret(name: string): Promise<string | undefined> {
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const res = await fetch(`${url}/rest/v1/rpc/get_vault_secret`, {
      method: "POST",
      headers: { apikey: svc, Authorization: `Bearer ${svc}`, "Content-Type": "application/json" },
      body: JSON.stringify({ p_name: name }),
    });
    if (!res.ok) return undefined;
    const val = await res.json();
    return typeof val === "string" && val.length ? val : undefined;
  } catch {
    return undefined;
  }
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string)
  );
}

function json(data: unknown, status: number) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
