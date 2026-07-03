/** Single source of truth for subscription plans (homepage + /pricing). */
export type Plan = {
  id: string;
  name: string;
  price: string;
  per: string;
  tag: string;
  features: string[];
  featured?: boolean;
  href?: string;
  cta?: string;
};

export const PLANS: Plan[] = [
  { id: "free", name: "Free", price: "$0", per: "forever", tag: "Get a feel for it.", cta: "Get the app", href: "/login",
    features: ["Range mode", "10 shots a day", "Ball speed & carry", "On-device storage"] },
  { id: "basic", name: "Basic", price: "$5", per: "/ month", tag: "For the regular range-goer.",
    features: ["All modes — range, sim, course", "Unlimited shots", "100 cloud-saved shots", "Basic analytics", "Cloud sync"] },
  { id: "pro", name: "Pro", price: "$10", per: "/ month", tag: "For the player chasing gains.", featured: true,
    features: ["Everything in Basic", "1,000 cloud shots", "Advanced analytics", "In-round suggestions", "Video export"] },
  { id: "atlas", name: "Atlas", price: "$25", per: "/ month", tag: "The whole bag.",
    features: ["Everything in Pro", "Unlimited cloud shots", "Full media storage", "Apple Watch companion", "Priority support"] },
];
