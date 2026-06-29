import Link from "next/link";
import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";

export const metadata = {
  title: "Support",
  description:
    "Get help with True Carry — setup, pairing, billing, and account questions. Email our team and we'll get back to you.",
};

const SUPPORT_EMAIL = "Rushil@truecarrygolf.com";

const QUICK_LINKS = [
  { href: "/bridge", title: "Set up the Bridge", detail: "Connect your iPhone to GSPro or OpenGolfSim." },
  { href: "/connect", title: "Check your connection", detail: "Live status for the bridge, simulator, and phone." },
  { href: "/account", title: "Your account & billing", detail: "Manage your plan, devices, and shot history." },
  { href: "/#pricing", title: "Plans & pricing", detail: "Compare Free, Basic, Pro, and Unlimited." },
];

export default function SupportPage() {
  return (
    <>
      <SiteNav />
      <main className="narrow" style={{ paddingTop: 70, paddingBottom: 90 }}>
        <span className="eyebrow">Help</span>
        <h1 style={{ fontSize: "clamp(32px,5vw,46px)", margin: "14px 0 28px" }}>Support</h1>

        <div className="prose">
          <p>
            Need a hand with True Carry? Whether it&rsquo;s setup, pairing your phone to a
            simulator, billing, or anything else — we&rsquo;re happy to help.
          </p>
          <p>
            Email us at{" "}
            <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a> and we&rsquo;ll get back to
            you, usually within one business day. To help us help you faster, include your
            account email, your device and app version, and a short description of what you
            were doing when the issue happened.
          </p>
        </div>

        <a
          href={`mailto:${SUPPORT_EMAIL}?subject=${encodeURIComponent("True Carry Support")}`}
          className="btn btn-gold btn-lg"
          style={{ marginTop: 28 }}
        >
          Email support
        </a>

        <h2 style={{ fontSize: "clamp(22px,3.5vw,30px)", margin: "56px 0 18px" }}>
          Common questions
        </h2>
        <div className="card-grid">
          {QUICK_LINKS.map((q) => (
            <Link key={q.href} href={q.href} className="card support-card">
              <span className="support-card-title">{q.title}</span>
              <span className="support-card-detail">{q.detail}</span>
            </Link>
          ))}
        </div>
      </main>
      <SiteFooter />
    </>
  );
}
