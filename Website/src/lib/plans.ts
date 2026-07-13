/** Single source of truth for subscription plans (homepage + /pricing).
 *  Each paid plan carries both billing intervals: `yearly` is the annual
 *  commitment (shown as its per-month equivalent), `monthly` is month to month. */
export type Plan = {
  id: string;
  name: string;
  yearly: string;   // per-month price on the annual plan
  monthly: string;  // month-to-month price
  per: string;
  tag: string;
  features: string[];
  featured?: boolean;
  flat?: boolean;   // free tier: same price either way, no billing toggle
  href?: string;
  cta?: string;
};

export const PLANS: Plan[] = [
  {
    id: "free",
    name: "Free",
    yearly: "$0",
    monthly: "$0",
    per: "forever",
    flat: true,
    tag: "Get a feel for it.",
    cta: "Get the app",
    href: "/login",
    features: ["Range mode", "10 shots a day", "Ball speed and carry", "On-device storage"],
  },
  {
    id: "pro",
    name: "Pro",
    yearly: "$10",
    monthly: "$14.99",
    per: "/ month",
    featured: true,
    tag: "For the player chasing gains.",
    features: [
      "All modes: range, sim, course",
      "Unlimited shots",
      "1,000 cloud-saved shots",
      "Advanced analytics",
      "In-round suggestions",
      "Video export",
    ],
  },
  {
    id: "atlas",
    name: "Atlas",
    yearly: "$25",
    monthly: "$34.99",
    per: "/ month",
    tag: "The whole bag.",
    features: [
      "Everything in Pro",
      "Unlimited cloud shots",
      "Full media storage",
      "Apple Watch companion",
      "Priority support",
    ],
  },
];
