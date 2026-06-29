"use client";

import Link from "next/link";
import { useEffect, useState, type ReactNode } from "react";

/**
 * Sticky brand navigation, visually identical to the homepage header so every
 * page shares one consistent bar. Pass `actions` to override the default
 * right-side links (e.g. on the signed-in account page).
 */
export default function SiteNav({ actions }: { actions?: ReactNode }) {
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 12);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

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
              <Link className="l hide-sm" href="/play">The Sim</Link>
              <Link className="l hide-sm" href="/course">Courses</Link>
              <Link className="l" href="/store">Store</Link>
              <Link className="l" href="/#h07">Pricing</Link>
              <Link className="l hide-sm" href="/support">Support</Link>
              <Link className="l btn" href="/login">Sign in</Link>
              <Link className="l btn primary" href="/#h07">Get the app</Link>
            </>
          )}
        </div>
      </div>
    </nav>
  );
}
