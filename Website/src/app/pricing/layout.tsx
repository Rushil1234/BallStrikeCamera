import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Pricing, Free to start, Pro for every yard",
  description:
    "True Carry is free to start. Go Pro for the browser simulator, course mode, and advanced shot analytics. Cancel anytime, plans renew automatically until you do.",
  alternates: { canonical: "/pricing" },
  openGraph: {
    title: "True Carry Pricing, Free to start, Pro for every yard",
    description: "Free launch-monitor basics. Pro unlocks the simulator, course mode, and deeper analytics.",
    url: "/pricing",
  },
};

export default function PricingLayout({ children }: { children: React.ReactNode }) {
  return children;
}
