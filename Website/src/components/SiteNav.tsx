"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState, type ReactNode } from "react";

/**
 * Sticky brand navigation, visually + tab-for-tab identical to the homepage
 * header so every page shares one consistent bar, with the current section
 * highlighted. Pass `actions` to override the default right-side links.
 */
export default function SiteNav({ actions }: { actions?: ReactNode }) {
  const [scrolled, setScrolled] = useState(false);
  const pathname = usePathname() || "/";

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
              <Link className="l btn" href="/login">Sign in</Link>
              <Link className="l btn primary" href="/#h07">Get the app</Link>
            </>
          )}
        </div>
      </div>
    </nav>
  );
}
