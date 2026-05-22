# True Carry Supabase Auth Email Setup

These templates are for the hosted Supabase Dashboard under:

`Authentication -> Email Templates`

## Templates

- `confirm-signup.html`: use for `Confirm signup`
- `recovery.html`: use for `Reset password`

Both templates use Supabase's `{{ .ConfirmationURL }}` variable, so they work with the existing website routes and redirect allowlist.

## Recommended Custom SMTP

For production, use a transactional email provider with a True Carry sending domain.

Recommended setup:

- Provider: Resend, Postmark, SendGrid, Brevo, or AWS SES
- From name: `True Carry`
- From address: `no-reply@auth.truecarry.app`
- Reply-to/support address: `support@truecarry.app`

Keep auth emails separate from marketing email. A subdomain like `auth.truecarry.app` protects deliverability and makes SPF/DKIM/DMARC easier to reason about.

## Supabase Dashboard Fields

Go to:

`Authentication -> SMTP Settings`

Set:

- Enable custom SMTP: `on`
- Sender name: `True Carry`
- Sender email: `no-reply@auth.truecarry.app`
- SMTP host: from your email provider
- SMTP port: usually `587`
- SMTP username: from your email provider
- SMTP password: from your email provider

Then go to:

`Authentication -> Email Templates`

Set subjects:

- Confirm signup: `Confirm your True Carry account`
- Reset password: `Reset your True Carry password`

Paste the matching HTML template into each template body.

## DNS Checklist

Your email provider will give exact DNS records, but expect:

- SPF record for `auth.truecarry.app`
- DKIM CNAME/TXT records for `auth.truecarry.app`
- DMARC record for `_dmarc.truecarry.app`

Do not enable link tracking for auth emails. Supabase auth links are security-sensitive and link tracking can break confirmation/reset flows.
