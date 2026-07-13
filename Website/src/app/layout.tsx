import type { Metadata } from "next";
import { Manrope, Instrument_Serif, JetBrains_Mono } from "next/font/google";
import "./globals.css";
import WebAnalytics from "@/components/WebAnalytics";

// Brand type stack (Brand Guidelines v1):
// Instrument Serif = display, Manrope = body, JetBrains Mono = numerics.
const manrope = Manrope({
  subsets: ["latin"],
  variable: "--font-sans",
  display: "swap",
});

const instrumentSerif = Instrument_Serif({
  subsets: ["latin"],
  weight: "400",
  style: ["normal", "italic"],
  variable: "--font-serif",
  display: "swap",
});

const jetbrainsMono = JetBrains_Mono({
  subsets: ["latin"],
  variable: "--font-mono",
  display: "swap",
});

// Canonical domain is fixed to the real one so search engines index
// truecarry.golf (not a vercel.app deployment URL or a stray env var).
const SITE_URL = "https://truecarry.golf";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: "True Carry: The Camera Launch Monitor",
    template: "%s, True Carry",
  },
  description:
    "True Carry turns your iPhone into a tour-grade launch monitor. Measure ball speed, launch angle, and carry distance on the range, in a simulator, or on the course, no extra hardware.",
  keywords: ["golf launch monitor", "camera launch monitor", "ball speed", "carry distance", "golf app", "True Carry"],
  openGraph: {
    title: "True Carry: The Camera Launch Monitor",
    description: "Tour-grade ball data from the iPhone in your pocket. Track every shot, know every yard.",
    url: SITE_URL,
    siteName: "True Carry",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "True Carry: The Camera Launch Monitor",
    description: "Tour-grade ball data from the iPhone in your pocket.",
  },
  icons: {
    icon: [{ url: "/truecarry-header-logo.png", type: "image/png" }],
    shortcut: "/truecarry-header-logo.png",
    apple: "/truecarry-header-logo.png",
  },
  alternates: {
    canonical: "/",
  },
};

// Structured data: search engines use this for rich results and the
// knowledge panel. Organization + WebSite + the product (the app).
const jsonLd = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "Organization",
      "@id": `${SITE_URL}/#org`,
      name: "True Carry",
      url: SITE_URL,
      logo: `${SITE_URL}/favicon.svg`,
      email: "rushil@truecarrygolf.com",
      sameAs: [],
    },
    {
      "@type": "WebSite",
      "@id": `${SITE_URL}/#website`,
      url: SITE_URL,
      name: "True Carry",
      publisher: { "@id": `${SITE_URL}/#org` },
    },
    {
      "@type": "SoftwareApplication",
      name: "True Carry",
      operatingSystem: "iOS",
      applicationCategory: "SportsApplication",
      description:
        "Turn your iPhone into a tour-grade launch monitor, ball speed, launch angle, and carry distance on the range, in a simulator, or on the course, with no extra hardware.",
      offers: {
        "@type": "Offer",
        price: "0",
        priceCurrency: "USD",
        description: "Free to start; Pro subscription for advanced analytics and the simulator.",
      },
    },
  ],
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${manrope.variable} ${instrumentSerif.variable} ${jetbrainsMono.variable}`} suppressHydrationWarning>
      <body>
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
        />
        <a href="#main-content" className="skip-link">Skip to main content</a>
        <WebAnalytics />
        <div id="main-content">{children}</div>
      </body>
    </html>
  );
}
