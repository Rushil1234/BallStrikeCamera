import type { Metadata } from "next";
import { Manrope, Instrument_Serif, JetBrains_Mono } from "next/font/google";
import "./globals.css";

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

const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL ?? "https://truecarry.app";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: "True Carry — The Camera Launch Monitor",
    template: "%s — True Carry",
  },
  description:
    "True Carry turns your iPhone into a tour-grade launch monitor. Measure ball speed, launch angle, and carry distance on the range, in a simulator, or on the course — no extra hardware.",
  keywords: ["golf launch monitor", "camera launch monitor", "ball speed", "carry distance", "golf app", "True Carry"],
  openGraph: {
    title: "True Carry — The Camera Launch Monitor",
    description: "Tour-grade ball data from the iPhone in your pocket. Track every shot, know every yard.",
    url: SITE_URL,
    siteName: "True Carry",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "True Carry — The Camera Launch Monitor",
    description: "Tour-grade ball data from the iPhone in your pocket.",
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${manrope.variable} ${instrumentSerif.variable} ${jetbrainsMono.variable}`} suppressHydrationWarning>
      <body>
        <script
          dangerouslySetInnerHTML={{
            __html: `
              (() => {
                try {
                  const saved = localStorage.getItem("truecarry-theme");
                  const theme = saved === "light" || saved === "dark"
                    ? saved
                    : (matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark");
                  document.documentElement.dataset.theme = theme;
                } catch {
                  document.documentElement.dataset.theme = "dark";
                }
              })();
            `,
          }}
        />
        {children}
      </body>
    </html>
  );
}
