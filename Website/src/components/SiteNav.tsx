"use client";

import Link from "next/link";
import { useEffect, useState, type ReactNode } from "react";

/** Sticky, scroll-aware glass navigation used across marketing pages. */
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
        <Link href="/" className="brand-logo">
          <img src="/truecarry-logo.png" alt="" aria-hidden />
          True Carry
        </Link>
        <div className="nav-links">
          {actions ?? (
            <>
              <Link href="/#h03" className="hide-sm">What it does</Link>
              <Link href="/play" className="hide-sm">The Sim</Link>
              <Link href="/course" className="hide-sm">Courses</Link>
              <Link href="/store">Store</Link>
              <Link href="/#pricing">Pricing</Link>
              <Link href="/support" className="hide-sm">Support</Link>
              <Link href="/login" className="btn btn-gold" style={{ padding: "10px 22px", fontSize: 14 }}>
                Sign In
              </Link>
            </>
          )}
        </div>
      </div>
    </nav>
  );
}
