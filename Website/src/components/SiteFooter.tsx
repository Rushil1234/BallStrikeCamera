import Link from "next/link";

export default function SiteFooter() {
  return (
    <footer className="footer">
      <div className="footer-inner">
        <div className="footer-cols">
          <div style={{ maxWidth: 320 }}>
            <Link href="/" className="brand-logo" style={{ marginBottom: 14 }}>
              <img src="/truecarry-logo.png" alt="" aria-hidden />
              True Carry
            </Link>
            <p style={{ color: "var(--muted)", fontSize: 14, marginTop: 14, lineHeight: 1.7 }}>
              Tour-grade ball data from the iPhone in your pocket. Built for golfers who want to
              know every yard.
            </p>
          </div>

          <div className="footer-links">
            <span style={{ color: "var(--faint)", fontSize: 12, letterSpacing: "0.12em", textTransform: "uppercase", marginBottom: 4 }}>Product</span>
            <Link href="/#h03">What it does</Link>
            <Link href="/play">Play the sim</Link>
            <Link href="/store">Store</Link>
            <Link href="/#pricing">Pricing</Link>
          </div>

          <div className="footer-links">
            <span style={{ color: "var(--faint)", fontSize: 12, letterSpacing: "0.12em", textTransform: "uppercase", marginBottom: 4 }}>Account</span>
            <Link href="/login">Sign in</Link>
            <Link href="/account">Your account</Link>
            <Link href="/#pricing">Manage plan</Link>
          </div>

          <div className="footer-links">
            <span style={{ color: "var(--faint)", fontSize: 12, letterSpacing: "0.12em", textTransform: "uppercase", marginBottom: 4 }}>Help</span>
            <Link href="/support">Support</Link>
            <Link href="/bridge">Bridge setup</Link>
            <Link href="/connect">Connection</Link>
          </div>

          <div className="footer-links">
            <span style={{ color: "var(--faint)", fontSize: 12, letterSpacing: "0.12em", textTransform: "uppercase", marginBottom: 4 }}>Legal</span>
            <Link href="/privacy">Privacy</Link>
            <Link href="/terms">Terms</Link>
          </div>
        </div>

        <div className="footer-bottom">
          <span>© {new Date().getFullYear()} True Carry. All rights reserved.</span>
          <span>Subscriptions securely managed by Stripe.</span>
        </div>
      </div>
    </footer>
  );
}
