# Auth email setup — sending from rushil@truecarrygolf.com

This makes the **email verification** and **forgot-password** flows send branded
mail from `rushil@truecarrygolf.com`.

The React flows already work (`/login` requests them, `/auth/callback` and
`/reset-password` complete them). What's left is **project configuration**, which
lives in [`config.toml`](./config.toml) + [`templates/`](./templates) and must be
applied to the hosted Supabase project. There are two routes — pick one.

## What you must provide first: a domain-verified SMTP sender

Supabase's built-in email **cannot** send from a custom address and is rate-limited.
To send from `rushil@truecarrygolf.com` you need an SMTP provider with the
`truecarrygolf.com` domain verified (SPF + DKIM), e.g. Resend, Postmark, SendGrid,
or AWS SES. From that provider you get: `SMTP_HOST`, `SMTP_USER`, `SMTP_PASS`.

> Without domain verification, mail will land in spam or be rejected.

## Route A — Supabase Dashboard (simplest, no CLI)

1. **Authentication → Emails → SMTP Settings** → enable custom SMTP:
   - Sender email: `rushil@truecarrygolf.com`  ·  Sender name: `True Carry`
   - Host / Port (587) / Username / Password from your provider.
2. **Authentication → Emails → Templates** → for **Confirm signup**, **Reset
   password**, **Magic Link**, and **Change email address**, paste the matching
   file from [`templates/`](./templates) and set the subjects from `config.toml`.
3. **Authentication → URL Configuration**:
   - Site URL = your production origin (e.g. `https://truecarry.app`).
   - Redirect URLs: add `/auth/callback` and `/reset-password` for each origin
     you use (see `additional_redirect_urls` in `config.toml`).

## Route B — CLI (infrastructure-as-code)

1. Put the secrets in a project-root `.env` (git-ignored — see `.env.example`):
   ```
   SMTP_HOST=...
   SMTP_USER=...
   SMTP_PASS=...
   ```
2. ⚠️ `config.toml` here only contains the auth/email blocks. Before pushing, run
   `supabase init` and merge these `[auth.*]` blocks into the generated full
   config, or `supabase config push` may reset other remote auth settings
   (OAuth providers, etc.).
3. Authenticate and push:
   ```bash
   export SUPABASE_ACCESS_TOKEN=<token>
   supabase config push        # applies SMTP + templates + URL config to the linked project
   ```
   (The SMTP block is ignored for local `supabase start`, which routes mail to
   Mailpit at http://localhost:54324 — handy for previewing the templates.)

## Verify it works

- Sign up with a real address → confirmation email arrives **from
  rushil@truecarrygolf.com**, branded; clicking it lands on `/auth/callback`
  and signs you in.
- Use “Forgot password?” on `/login` → reset email arrives; the link opens
  `/reset-password`, lets you set a new password, and signs you in.
- Check the message headers show SPF=pass / DKIM=pass for `truecarrygolf.com`.
