# Config — Secrets Setup

## First-time setup

1. Copy the example file:
   ```
   cp Config/Secrets.example.plist BallStrikeCamera/Secrets.plist
   ```

2. Open `BallStrikeCamera/Secrets.plist` and fill in:
   - `SupabaseURL` → `https://aoxturoezgecwceudeef.supabase.co`
   - `SupabaseAnonKey` → your Supabase **anon/publishable** key (from Supabase Dashboard → Settings → API)

3. Add `BallStrikeCamera/Secrets.plist` to your Xcode project target so it is bundled. (Right-click BallStrikeCamera folder in Xcode → Add Files. Make sure "Copy items if needed" and the app target are checked.)

4. Do **NOT** commit `Secrets.plist`. It is already in `.gitignore`.

## Key rules

| Key | Where to put it | Safe in app? |
|-----|----------------|--------------|
| Supabase anon key | `Secrets.plist` | ✅ Yes — public by design |
| Supabase service-role key | Supabase Edge Function env secrets **only** | ❌ Never in app |
| Stripe publishable key | Website frontend only | ✅ Yes |
| Stripe secret key | Supabase Edge Function env secrets **only** | ❌ Never in app or website |
| Stripe webhook signing secret | Supabase Edge Function env secrets **only** | ❌ Never in app |

## Without Secrets.plist

The app falls back to `LocalBackendService` (JSON files on device). You will see in Xcode console:

```
[TrueCarry] Supabase config missing — using LocalBackendService
```

All features work locally. No Supabase account needed for development.

## With Secrets.plist

```
[TrueCarry] Supabase config found — using SupabaseBackendService (aoxturoezgecwceudeef.supabase.co)
```

The app talks to Supabase for auth, data, and entitlement checks.
