"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { supabase } from "@/lib/supabase";

interface AttestationDetails {
  course_name: string;
  round_date: string | null;
  score: number | null;
  to_par: number | null;
  requester_name: string;
  status: string; // pending | attested | declined
}

function formatDate(iso: string | null): string {
  if (!iso) return "";
  return new Date(iso).toLocaleDateString(undefined, { month: "long", day: "numeric", year: "numeric" });
}

function toParLabel(toPar: number | null): string | null {
  if (toPar == null) return null;
  if (toPar === 0) return "E";
  return toPar > 0 ? `+${toPar}` : `${toPar}`;
}

export default function AttestPage() {
  const params = useParams<{ token: string }>();
  const token = params?.token;

  const [loading, setLoading] = useState(true);
  const [details, setDetails] = useState<AttestationDetails | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [submitting, setSubmitting] = useState<"attest" | "decline" | null>(null);
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [finalStatus, setFinalStatus] = useState<"attested" | "declined" | null>(null);

  useEffect(() => {
    let mounted = true;
    async function load() {
      if (!token) return;
      const { data, error } = await supabase.rpc("get_attestation_by_token", { p_token: token });
      if (!mounted) return;
      if (error || !data || (Array.isArray(data) && data.length === 0)) {
        setLoadError("This link is invalid or has expired.");
        setLoading(false);
        return;
      }
      const row = (Array.isArray(data) ? data[0] : data) as AttestationDetails;
      setDetails(row);
      setLoading(false);
    }
    void load();
    return () => { mounted = false; };
  }, [token]);

  async function respond(accept: boolean) {
    if (!token) return;
    setSubmitError(null);
    setSubmitting(accept ? "attest" : "decline");
    try {
      const { error } = await supabase.rpc("respond_to_attestation_by_token", {
        p_token: token,
        p_accept: accept,
        p_attester_name: name.trim(),
      });
      if (error) throw error;
      setFinalStatus(accept ? "attested" : "declined");
    } catch (err: unknown) {
      setSubmitError(err instanceof Error ? err.message : "Couldn't send your response. Try again.");
    } finally {
      setSubmitting(null);
    }
  }

  const alreadyAnswered = details && details.status !== "pending" && !finalStatus;

  return (
    <div className="auth-page">
      <header className="auth-nav">
        <Link href="/" className="auth-brand" aria-label="True Carry home">
          <img src="/truecarry-logo.png" alt="" aria-hidden />
          <span>True <em>Carry.</em></span>
        </Link>
      </header>

      <main className="auth-main">
        <section className="auth-panel">
          <div className="auth-copy">
            <span className="auth-kicker">Round attestation</span>
            <h1>Confirm a round.</h1>
            <p>A True Carry golfer is asking you to verify one of their rounds. No account needed.</p>
          </div>

          <div className="auth-card">
            <div className="auth-card-head">
              <span className="auth-card-label">Attestation request</span>
              <h2>{loading ? "Loading…" : details ? details.course_name : "Round"}</h2>
            </div>

            {loading && <p className="auth-switch" style={{ marginTop: 0 }}>Loading round details…</p>}

            {!loading && loadError && (
              <p className="error-msg auth-message">{loadError}</p>
            )}

            {!loading && details && finalStatus && (
              <p className="success-msg auth-message">
                {finalStatus === "attested"
                  ? "Thanks! Your attestation has been sent."
                  : "Got it, you've declined this request."}
              </p>
            )}

            {!loading && details && !finalStatus && alreadyAnswered && (
              <p className="auth-switch" style={{ marginTop: 0 }}>
                This request has already been {details.status}. No further action needed.
              </p>
            )}

            {!loading && details && !finalStatus && !alreadyAnswered && (
              <>
                <div style={{ marginBottom: 18, color: "var(--muted)", lineHeight: 1.7 }}>
                  <p style={{ margin: 0 }}>
                    <strong style={{ color: "var(--cream)" }}>{details.requester_name || "A friend"}</strong> is asking
                    you to confirm they played this round:
                  </p>
                  <p style={{ margin: "10px 0 0" }}>
                    {details.course_name}
                    {details.round_date ? ` · ${formatDate(details.round_date)}` : ""}
                  </p>
                  {details.score != null && (
                    <p style={{ margin: "4px 0 0" }}>
                      Score: {details.score}
                      {toParLabel(details.to_par) ? ` (${toParLabel(details.to_par)})` : ""}
                    </p>
                  )}
                </div>

                {submitError && <p className="error-msg auth-message">{submitError}</p>}

                <form onSubmit={(e) => { e.preventDefault(); void respond(true); }} className="auth-form">
                  <div>
                    <label htmlFor="name">Your name</label>
                    <input
                      id="name"
                      type="text"
                      value={name}
                      onChange={(e) => setName(e.target.value)}
                      placeholder="So they know who verified it"
                      autoComplete="name"
                      required
                    />
                  </div>
                  <button type="submit" className="auth-submit" disabled={submitting !== null}>
                    {submitting === "attest" ? "Confirming…" : "Yes, I confirm this round"}
                  </button>
                  <button
                    type="button"
                    className="auth-submit"
                    style={{ background: "transparent", border: "1px solid var(--muted)", color: "var(--muted)" }}
                    disabled={submitting !== null}
                    onClick={() => respond(false)}
                  >
                    {submitting === "decline" ? "Declining…" : "This didn't happen"}
                  </button>
                </form>
              </>
            )}
          </div>
        </section>
      </main>
    </div>
  );
}
