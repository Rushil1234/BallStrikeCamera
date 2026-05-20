# True Carry — Backend

## Architecture

```
iOS App (AppBackend protocol)
    ├── LocalBackendService   — JSON files on device (development / offline)
    └── SupabaseBackendService — Supabase REST + Auth (production)
                                 ↑ chosen by BackendFactory at launch
```

**BackendFactory** reads `Secrets.plist` (gitignored). If `SupabaseURL` + `SupabaseAnonKey` are present, it returns `SupabaseBackendService`; otherwise it falls back to `LocalBackendService`. The app compiles and runs without any Supabase credentials.

## Secrets.plist

Copy `Secrets.plist.example` and fill in values:

```xml
<dict>
    <key>GolfCourseAPIKey</key><string>...</string>
    <key>SupabaseURL</key><string>https://YOUR_PROJECT.supabase.co</string>
    <key>SupabaseAnonKey</key><string>eyJ...</string>
</dict>
```

Never commit `Secrets.plist`. It is in `.gitignore`.

## Supabase Setup

1. Create project at supabase.com
2. Run migrations in order:
   ```
   supabase/migrations/001_initial_schema.sql
   supabase/migrations/002_entitlements.sql
   supabase/migrations/003_rls_policies.sql
   supabase/migrations/004_storage_policies.sql
   supabase/migrations/005_course_geometries.sql
   supabase/migrations/006_geometry_backfill_pipeline.sql
   supabase/migrations/007_storage_buckets.sql
   supabase/migrations/008_geometry_backfill_upsert_policy.sql
   supabase/migrations/009_geometry_backfill_policy_hardening.sql
   ```
3. Create storage buckets: `profile-images`, `shot-videos`, `shot-frames`
4. Deploy Stripe webhook edge function (see `stripe/README.md`)

## Entitlement System

| Tier      | Daily shots | Course mode | Sim mode | Video export |
|-----------|-------------|-------------|----------|--------------|
| Free      | 5           | ✗           | ✗        | ✗            |
| Basic     | 30          | ✓           | ✗        | ✗            |
| Pro       | 150         | ✓           | ✓        | ✓            |
| Unlimited | ∞           | ✓           | ✓        | ✓            |

- `EntitlementService` — pure static Swift, no backend dependency
- `EntitlementViewModel` — `@MainActor ObservableObject`, loaded after sign-in
- Server enforces limits (Supabase RLS + `increment_usage` RPC)
- Client pre-checks for instant UI gating

## Key Files

| File | Purpose |
|------|---------|
| `Data/AppBackend.swift` | Protocol + default extension implementations |
| `Data/BackendFactory.swift` | Chooses backend from Secrets.plist |
| `Data/SupabaseConfig.swift` | Reads Supabase credentials |
| `Data/SupabaseBackendService.swift` | URLSession REST implementation |
| `Data/SupabaseDTOs.swift` | Codable DTO structs |
| `Data/LocalBackendService.swift` | JSON-file local implementation |
| `Data/AuthSessionStore.swift` | Session + entitlement state |
| `Models/SubscriptionModels.swift` | Tier, entitlement, usage, device models |
| `Models/SocialModels.swift` | Social graph models |
| `Services/EntitlementService.swift` | Pure static gating logic |
| `ViewModels/EntitlementViewModel.swift` | SwiftUI-ready entitlement state |
