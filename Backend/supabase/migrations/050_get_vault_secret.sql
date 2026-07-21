-- ============================================================================
-- 050_get_vault_secret.sql
-- Lets edge functions (service role) read gift-card email creds the owner stored
-- in Supabase Vault (Integrations > Vault). Scoped to ZOHO_* / ZEPTOMAIL_* names
-- only so this SECURITY DEFINER fn can't leak other vault secrets. service_role
-- only. (Email now sends via ZeptoMail HTTP — raw SMTP exceeds the Free-plan
-- edge compute limit; see functions/send-gift-email.)
-- ============================================================================
create or replace function public.get_vault_secret(p_name text)
returns text
language sql
security definer
set search_path = ''
as $$
  select decrypted_secret
  from vault.decrypted_secrets
  where name = p_name
    and (name like 'ZOHO\_%' or name like 'ZEPTOMAIL\_%')
  limit 1;
$$;

revoke all on function public.get_vault_secret(text) from public, anon, authenticated;
grant execute on function public.get_vault_secret(text) to service_role;
