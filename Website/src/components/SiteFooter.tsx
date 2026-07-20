import Link from "next/link";

/**
 * The one canonical footer, used on every page except the homepage — which has
 * an inline copy (it lives inside the scorecard-rail layout). Both are kept
 * identical in content and look; edit them together.
 */
export default function SiteFooter() {
  return (
    <footer className="footer">
      <div className="footer-inner">
        <div className="footer-cols">
          <div className="footer-brand">
            <div className="footer-wm">True <span className="it">Carry.</span></div>
            <p>Tour-grade ball data from the iPhone in your pocket. Built for golfers who want to know every yard.</p>
            <div className="footer-meta">Pacifica · CA · Est. 2026</div>
          </div>

          <div className="footer-links">
            <h4>Product</h4>
            <Link href="/#h03">What it does</Link>
            <Link href="/mission">Our mission</Link>
            <Link href="/play">Play the sim</Link>
            <Link href="/store">Store</Link>
            <Link href="/#pricing">Pricing</Link>
          </div>

          <div className="footer-links">
            <h4>Setup</h4>
            <Link href="/bridge">Connect to GSPro / OGS</Link>
            <Link href="/connect">Check connection</Link>
            <Link href="/support">Support</Link>
          </div>

          <div className="footer-links">
            <h4>Account</h4>
            <Link href="/login">Sign in</Link>
            <Link href="/account">Your account</Link>
            <Link href="/#pricing">Manage plan</Link>
          </div>

          <div className="footer-links">
            <h4>Legal</h4>
            <Link href="/privacy">Privacy</Link>
            <Link href="/terms">Terms</Link>
          </div>
        </div>

        <div className="footer-bottom">
          <span>© {new Date().getFullYear()} True Carry</span>
          <span>Subscriptions securely managed by Stripe.</span>
        </div>
      </div>
    </footer>
  );
}
