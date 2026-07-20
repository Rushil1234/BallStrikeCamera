# AI Coach — setup

The `ai-coach` edge function routes shot metrics to Claude (via OpenRouter) and
returns short coaching. The OpenRouter API key lives **only** as a Supabase
secret — never in the app, never committed to git.

## 1. Set the secret (do NOT paste the key into code or chat)

```bash
supabase secrets set OPENROUTER_API_KEY=sk-or-...   # your OpenRouter key
```

## 2. Deploy the function

```bash
supabase functions deploy ai-coach
```

That's it. The iOS app calls it automatically (Insights → "AI Coach"), gated to
Pro/Unlimited tiers. Until the secret is set, the function returns a friendly
"not configured yet" message and the app shows the error inline.

## Models / cost

Model routing is server-side (`index.ts` → `MODELS`):

- `shot`    → `anthropic/claude-haiku-4.5`  (fast, cheap per-shot read)
- `session` → `anthropic/claude-sonnet-4.5` (deeper recent-shots plan)

Adjust those slugs if you want different Claude models on OpenRouter. Each
coaching call is a fraction of a cent on Haiku.

## Security notes

- The pasted OpenRouter key should be **rotated** on OpenRouter now that it has
  been shared in chat — generate a new one and set it via step 1.
- To enforce Pro server-side (not just in the app UI), add a tier lookup in
  `index.ts` where the `NOTE:` comment is and 403 non-Pro callers.
