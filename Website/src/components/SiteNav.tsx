"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState, type ReactNode } from "react";
import { useSession } from "@/lib/useSession";

/**
 * The one sticky brand navigation bar, shared by every page (including the
 * homepage), with the current section highlighted and session-aware actions.
 * Pass `actions` to fully override the right side, or `onGetApp` to make the
 * primary button open a flow (e.g. embedded checkout) instead of linking.
 */
export default function SiteNav({ actions, onGetApp }: { actions?: ReactNode; onGetApp?: () => void }) {
  const [scrolled, setScrolled] = useState(false);
  const pathname = usePathname() || "/";
  const router = useRouter();
  const { user, loading, signOut } = useSession();

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 12);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  const onSim = pathname.startsWith("/play") || pathname.startsWith("/sim");
  const onStore = pathname.startsWith("/store");
  const onSupport = pathname.startsWith("/support");
  const link = (active: boolean, hideSm = false) =>
    `l${active ? " active" : ""}${hideSm ? " hide-sm" : ""}`;

  return (
    <nav className={`site-nav${scrolled ? " scrolled" : ""}`}>
      <div className="nav-inner">
        <Link href="/" className="brand" aria-label="True Carry home">
          <img src="/truecarry-header-logo.png" alt="" aria-hidden />
          <span className="n">True <span className="it">Carry.</span></span>
        </Link>
        <div className="nav">
          {actions ?? (
            <>
              <Link className="l hide-sm" href="/#h03">What it does</Link>
              <Link className={link(onSim, true)} href="/play" aria-current={onSim ? "page" : undefined}>The Sim</Link>
              <Link className={link(onStore)} href="/store" aria-current={onStore ? "page" : undefined}>Store</Link>
              <Link className="l" href="/#h07">Pricing</Link>
              <Link className={link(onSupport, true)} href="/support" aria-current={onSupport ? "page" : undefined}>Support</Link>
              {user ? (
                <>
                  <Link className="l btn primary" href="/account">Account</Link>
                  <button
                    className="l btn nav-signout"
                    onClick={async () => { await signOut(); router.push("/"); }}
                  >
                    Sign out
                  </button>
                </>
              ) : (
                <>
                  <Link className="l btn" href="/login" style={{ visibility: loading ? "hidden" : undefined }}>Sign in</Link>
                  {onGetApp ? (
                    <a className="l btn primary" href="/#h07" onClick={(e) => { e.preventDefault(); onGetApp(); }}>
                      Get the app
                    </a>
                  ) : (
                    <Link className="l btn primary" href="/#h07">Get the app</Link>
                  )}
                </>
              )}
            </>
          )}
        </div>
      </div>
    </nav>
  );
}
