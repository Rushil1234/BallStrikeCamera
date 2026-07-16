import { supabase } from "@/lib/supabase";

export type OAuthProvider = "google" | "apple";

export const oauthCopy: Record<OAuthProvider, { error: string }> = {
  google: { error: "Could not start Google sign-in." },
  apple: { error: "Could not start Apple sign-in." },
};

/**
 * Kick off a Supabase OAuth sign-in. On success the browser redirects to the
 * provider, so this never resolves with a value, it only throws on failure so
 * callers can surface the error and reset their own loading state.
 *
 * @param nextPath app-relative path to return to after the auth callback.
 */
export async function signInWithProvider(provider: OAuthProvider, nextPath: string) {
  const { error } = await supabase.auth.signInWithOAuth({
    provider,
    options: {
      redirectTo: `${window.location.origin}/auth/callback?next=${encodeURIComponent(nextPath)}`,
      queryParams: provider === "google" ? { prompt: "select_account" } : undefined,
    },
  });
  if (error) throw error;
}
