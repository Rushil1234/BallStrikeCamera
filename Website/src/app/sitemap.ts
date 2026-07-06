import type { MetadataRoute } from "next";

const BASE = "https://truecarry.golf";

export default function sitemap(): MetadataRoute.Sitemap {
  const pages = [
    ["", 1.0], ["/play", 0.9], ["/pricing", 0.9], ["/course", 0.8],
    ["/store", 0.7], ["/watch", 0.6], ["/support", 0.5],
    ["/privacy", 0.3], ["/terms", 0.3],
  ] as const;
  return pages.map(([path, priority]) => ({
    url: `${BASE}${path}`,
    lastModified: new Date(),
    changeFrequency: "weekly" as const,
    priority,
  }));
}
