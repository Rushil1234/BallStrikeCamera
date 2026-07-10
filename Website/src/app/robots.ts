import type { MetadataRoute } from "next";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: "*",
      allow: "/",
      // Private, transactional, or session pages — no SEO value, keep them out
      // of the index (they're also excluded from the sitemap).
      disallow: [
        "/account", "/login", "/reset-password", "/auth/",
        "/billing/", "/attest/", "/sim", "/connect",
      ],
    },
    sitemap: "https://truecarry.golf/sitemap.xml",
  };
}
