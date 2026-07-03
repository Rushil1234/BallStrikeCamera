#!/usr/bin/env bash
# One-shot backend deploy for True Carry. Run AFTER `supabase login` (opens a browser).
# Deploys the delete-account Edge Function and pushes config.toml auth settings.
#
#   cd Backend && ./deploy_backend.sh
#
# Everything here can ALSO be done in the Supabase Dashboard (no CLI) — see
# SCALE_AND_SECURITY.md. This script is just the fast path once the CLI is set up.
set -euo pipefail

PROJECT_REF="aoxturoezgecwceudeef"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"   # repo root (config.toml lives at ./supabase)

echo "→ Linking project $PROJECT_REF …"
supabase link --project-ref "$PROJECT_REF"

echo "→ Deploying delete-account Edge Function …"
# --no-verify-jwt is NOT passed: the platform verifies the caller's JWT before the
# function runs, and the function double-checks the user. Service role env is auto-injected.
supabase functions deploy delete-account --project-ref "$PROJECT_REF"

echo "→ Pushing auth config (rate limits, anonymous cap) from supabase/config.toml …"
# Optional: only if you manage auth settings via config. Comment out to keep dashboard-managed.
supabase config push --project-ref "$PROJECT_REF" || \
  echo "  (config push skipped/unsupported on this CLI version — set these in Dashboard → Auth instead)"

echo "✓ Done. Verify: curl -i -X POST https://$PROJECT_REF.supabase.co/functions/v1/delete-account"
echo "  (expect HTTP 401 'Missing Authorization header' — that means it's live.)"
