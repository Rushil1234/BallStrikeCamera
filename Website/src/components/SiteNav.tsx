"use client";

import Link from "next/link";
import { useEffect, useState, type ReactNode } from "react";
import ThemeToggle from "@/components/ThemeToggle";

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
              <Link href="/#features" className="hide-sm">Features</Link>
              <Link href="/#pricing">Pricing</Link>
              <Link href="/login" className="btn btn-gold" style={{ padding: "10px 22px", fontSize: 14 }}>
                Sign In
              </Link>
            </>
          )}
          <ThemeToggle />
        </div>
      </div>
    </nav>
  );
}
