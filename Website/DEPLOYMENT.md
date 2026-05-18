# True Carry Website — Deployment Guide

## Local development

```bash
cd Website
npm install
cp .env.example .env.local
# Fill in .env.local with your Supabase anon key
npm run dev
# Open http://localhost:3000
```

## Deploy to Vercel (recommended)

### 1. Push repo to GitHub
```bash
git add Website/
git commit -m "Add True Carry website"
git push
```

### 2. Create Vercel project
1. Go to vercel.com → Add New Project
2. Import your GitHub repo
3. Set **Root Directory** to `Website`
4. Vercel auto-detects Next.js

### 3. Set environment variables in Vercel
Project → Settings → Environment Variables. Add:

| Variable | Value |
|----------|-------|
| `NEXT_PUBLIC_SUPABASE_URL` | `https://aoxturoezgecwceudeef.supabase.co` |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | your Supabase anon key |
| `NEXT_PUBLIC_SITE_URL` | your Vercel URL or `https://truecarry.app` |
| `NEXT_PUBLIC_CREATE_CHECKOUT_FUNCTION_URL` | `https://aoxturoezgecwceudeef.functions.supabase.co/create-checkout-session` |
| `NEXT_PUBLIC_CUSTOMER_PORTAL_FUNCTION_URL` | `https://aoxturoezgecwceudeef.functions.supabase.co/create-customer-portal-session` |

**Never add** `SUPABASE_SERVICE_ROLE_KEY` or `STRIPE_SECRET_KEY` here — those are Edge Function secrets only.

### 4. Deploy
Click **Deploy**. Vercel gives you a URL like `truecarry-xyz.vercel.app`.

### 5. Use the Vercel URL as TRUECARRY_WEBSITE_URL
Copy that URL and set it in your Supabase Edge Function secrets:
```bash
supabase secrets set TRUECARRY_WEBSITE_URL=https://truecarry-xyz.vercel.app
```

Stripe success/cancel URLs will route correctly. Update again once you connect a custom domain.

## Custom domain (optional — truecarry.app)

1. Buy `truecarry.app` from a registrar (Namecheap, Cloudflare Registrar, etc.)
2. In Vercel → Project → Settings → Domains → Add `truecarry.app`
3. Vercel shows you DNS records to add at your registrar
4. Add the A and CNAME records, wait for propagation (up to 48 hrs)
5. Vercel auto-provisions SSL
6. Update `TRUECARRY_WEBSITE_URL` and Supabase Edge Function secrets to `https://truecarry.app`
7. Update Stripe success/cancel URLs via the `create-checkout-session` Edge Function env var

## Google Search Console (optional, after launch)

1. Deploy site with custom domain
2. Go to search.google.com/search-console
3. Add property → Domain → enter `truecarry.app`
4. Verify via DNS TXT record (add at registrar)
5. Submit sitemap if desired

Search indexing happens automatically after verification; you don't need to "publish to Google."

## Pages checklist

| Route | Status |
|-------|--------|
| `/` | Home / hero |
| `/pricing` | Plan comparison + Stripe Checkout |
| `/login` | Supabase email auth |
| `/account` | Subscription status + Stripe Portal |
| `/billing/success` | Post-checkout confirmation |
| `/billing/cancel` | Checkout canceled message |
| `/privacy` | Privacy policy |
| `/terms` | Terms of service |
