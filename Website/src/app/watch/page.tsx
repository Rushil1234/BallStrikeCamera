"use client";

import { Suspense, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";
import { supabase } from "@/lib/supabase";

type LiveShot = {
  club?: string;
  ball_speed_mph?: number;
  launch_deg?: number;
  carry_yds?: number;
  total_yds?: number;
  spin_rpm?: number;
  side_deg?: number;
} | null;

type HoleScore = { hole?: number; par?: number; strokes?: number | null };

type LiveState = {
  code: string;
  sim_state?: string;
  hole?: number;
  stroke?: number;
  result?: string;
  last_shot?: LiveShot;
  round_summary?: {
    courseName?: string;
    holes?: HoleScore[];
    totalStrokes?: number;
    toPar?: number;
  } | null;
  updated_at?: string;
} | null;

function fmtToPar(n: number | undefined) {
  if (n === undefined || n === null) return "";
  return n === 0 ? "E" : n > 0 ? `+${n}` : `${n}`;
}

function WatchInner() {
  const params = useSearchParams();
  const [code, setCode] = useState(params.get("code") ?? "");
  const [input, setInput] = useState("");
  const [state, setState] = useState<LiveState>(null);
  const [stale, setStale] = useState(false);

  useEffect(() => {
    if (!/^[0-9]{6,10}$/.test(code)) return;
    let stop = false;
    const tick = async () => {
      const { data } = await supabase
        .from("live_sim_state")
        .select("*")
        .eq("code", code)
        .maybeSingle();
      if (stop) return;
      setState(data as LiveState);
      if (data?.updated_at) {
        setStale(Date.now() - new Date(data.updated_at).getTime() > 90_000);
      }
    };
    tick();
    const id = setInterval(tick, 2500);
    return () => { stop = true; clearInterval(id); };
  }, [code]);

  const shot = state?.last_shot ?? null;
  const summary = state?.round_summary ?? null;

  return (
    <div className="watch-page">
      <SiteNav />
      <main className="watch-main">
        {!/^[0-9]{6,10}$/.test(code) ? (
          <section className="watch-join">
            <p className="store-kicker">Spectate</p>
            <h1>Watch a live round.</h1>
            <p className="watch-deck">
              Enter the session code from the player&apos;s sim screen. You&apos;ll see every
              shot land as it happens — read-only, nothing to install.
            </p>
            <form
              onSubmit={(e) => { e.preventDefault(); setCode(input.trim()); }}
              className="watch-form"
            >
              <input
                inputMode="numeric"
                placeholder="Session code"
                value={input}
                onChange={(e) => setInput(e.target.value.replace(/\D/g, "").slice(0, 10))}
              />
              <button type="submit" className="watch-cta">Watch</button>
            </form>
          </section>
        ) : (
          <section className="watch-live">
            <div className="watch-head">
              <h1>Live round</h1>
              <span className={`watch-dot${state && !stale ? " on" : ""}`} />
              <span className="watch-status">
                {!state ? "Waiting for the session…" : stale ? "Signal lost — player may have finished" : (state.sim_state ?? "LIVE")}
              </span>
            </div>

            {state && (
              <div className="watch-grid">
                <div className="watch-card">
                  <p className="watch-label">Now playing</p>
                  <p className="watch-big">Hole {state.hole ?? "—"}</p>
                  <p className="watch-sub">Stroke {state.stroke ?? "—"}{state.result ? ` · ${state.result}` : ""}</p>
                </div>

                <div className="watch-card">
                  <p className="watch-label">Last shot</p>
                  {shot ? (
                    <>
                      <p className="watch-big">{shot.carry_yds ?? "—"}y <span className="watch-unit">carry</span></p>
                      <p className="watch-sub">
                        {[shot.club, shot.ball_speed_mph && `${shot.ball_speed_mph} mph`, shot.total_yds && `${shot.total_yds}y total`]
                          .filter(Boolean).join(" · ")}
                      </p>
                    </>
                  ) : (
                    <p className="watch-sub">No shots yet.</p>
                  )}
                </div>

                {summary && (
                  <div className="watch-card wide">
                    <p className="watch-label">Final — {summary.courseName ?? "round"}</p>
                    <p className="watch-big">
                      {summary.totalStrokes} <span className="watch-unit">strokes ({fmtToPar(summary.toPar)})</span>
                    </p>
                    <div className="watch-scoreline">
                      {(summary.holes ?? []).map((h) => (
                        <span
                          key={h.hole}
                          className={
                            h.strokes == null || h.par == null ? "" :
                            h.strokes < h.par ? "birdie" : h.strokes > h.par ? "bogey" : ""
                          }
                        >
                          {h.strokes ?? "·"}
                        </span>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            )}

            <p className="watch-note">
              Read-only view. Shares the room&apos;s session code — only send this link to
              people you&apos;d let in the room.
            </p>
          </section>
        )}
      </main>
      <SiteFooter />
    </div>
  );
}

export default function WatchPage() {
  return (
    <Suspense>
      <WatchInner />
    </Suspense>
  );
}
