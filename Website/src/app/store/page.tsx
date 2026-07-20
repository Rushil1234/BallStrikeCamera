import type { Metadata } from "next";
import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";
import ProductArt from "@/components/ProductArt";
import NotifyForm from "@/components/NotifyForm";
import GiftCardBuy from "@/components/GiftCardBuy";

export const metadata: Metadata = {
  title: "Store",
  description:
    "NFC club tags, foam practice balls, the True Carry tripod, the polo, and gift cards. Gear for True Carry: the camera launch monitor.",
};

type Product = {
  id: string;
  name: string;
  price: string;
  tag: string;
  features: string[];
  status: string;
  href?: string;
  /** The signature product — rendered wide, art beside copy. */
  featured?: boolean;
};

// NOTE: prices on the physical goods are placeholders — set them before launch.
// The gift card is deliberately face-value: anything below the yearly sub price
// would make gifting yourself cheaper than subscribing.
const PRODUCTS: Product[] = [
  {
    id: "nfc-tag",
    name: "NFC Club Tags",
    price: "$29",
    tag: "Tap a club. The next shot knows which one it was.",
    features: [
      "14 passive NFC tags, one per club",
      "Under-grip or bag-tag fit",
      "No batteries, no pairing",
      "Waterproof, tour-thin",
    ],
    status: "Ships fall 2026",
    featured: true,
  },
  {
    id: "foam-balls",
    name: "Foam Practice Balls",
    price: "$19",
    tag: "Full swings. Living room ceiling intact.",
    features: [
      "12 high-density foam balls",
      "Tracks like a real ball at 240fps",
      "Indoor and net safe",
      "Won't mark walls",
    ],
    status: "Ships fall 2026",
  },
  {
    id: "tripod",
    name: "The True Carry Tripod",
    price: "$39",
    tag: "Puts the camera exactly where the math wants it.",
    features: [
      "Alignment guide for 240fps capture",
      "Folds to scorecard size",
      "Fits every iPhone",
      "Weighted base, grass or mat",
    ],
    status: "Ships fall 2026",
  },
  {
    id: "polo",
    name: "The True Carry Polo",
    price: "$65",
    tag: "Quietly says you know your carry numbers.",
    features: [
      "Performance pique, four-way stretch",
      "Embroidered mark, left chest",
      "Sizes XS–XXL",
      "Forest, bone, and clay",
    ],
    status: "Ships fall 2026",
  },
  {
    id: "gift-card",
    name: "True Carry Gift Card",
    price: "$25+",
    tag: "Every yard, on someone else's card.",
    features: [
      "Choose any amount from $25",
      "Redeemable against Pro, Atlas, or gear",
      "Delivered by email as a code",
      "Never expires",
    ],
    status: "Available now",
    href: "/#h07",
  },
];

function ProductCard({ p }: { p: Product }) {
  const live = p.status === "Available now";
  return (
    <article className={`product${p.featured ? " featured" : ""}${live ? " is-live" : ""}`}>
      <div className="product-art">
        <ProductArt kind={p.id} priority={p.featured} />
      </div>
      <div className="product-body">
        <div className="product-head">
          <h2>{p.name}</h2>
        </div>
        <p className="product-tag">{p.tag}</p>
        <ul>
          {p.features.map((f) => (
            <li key={f}>{f}</li>
          ))}
        </ul>
        <div className="product-foot">
          <span className={`product-status${live ? " live" : ""}`}>{p.status}</span>
          {p.id === "gift-card" ? (
            <GiftCardBuy />
          ) : live ? (
            <a className="product-cta" href={p.href ?? "/#h07"}>
              Get it
            </a>
          ) : (
            <NotifyForm productId={p.id} productName={p.name} />
          )}
        </div>
      </div>
    </article>
  );
}

export default async function StorePage({
  searchParams,
}: {
  searchParams: Promise<{ gift?: string }>;
}) {
  const gift = (await searchParams).gift;
  return (
    <div className="store-page">
      <SiteNav />

      {gift === "success" && (
        <div className="store-banner ok" role="status">
          Gift card on its way — we&apos;ve emailed the code to your recipient. 🎁
        </div>
      )}
      {gift === "cancel" && (
        <div className="store-banner" role="status">
          Checkout canceled — no charge. The gift card is still here when you&apos;re ready.
        </div>
      )}

      <header className="store-hero">
        <div className="store-hero-inner">
          <p className="store-kicker">The pro shop</p>
          <h1>
            Gear that knows <span className="it">your bag.</span>
          </h1>
          <p className="store-deck">
            Hardware is simple here: tags that tell the app which club you&apos;re swinging,
            balls you can hit indoors, and a tripod that holds the camera steady.
            Everything else is software.
          </p>
          <dl className="store-facts">
            <div>
              <dt>Ships</dt>
              <dd>Fall 2026</dd>
            </div>
            <div>
              <dt>Gift cards</dt>
              <dd>Available now</dd>
            </div>
            <div>
              <dt>Returns</dt>
              <dd>30 days</dd>
            </div>
          </dl>
        </div>
      </header>

      <main className="store-main">
        <div className="store-grid">
          {PRODUCTS.map((p) => (
            <ProductCard key={p.id} p={p} />
          ))}
        </div>

        <aside className="store-note">
          <div>
            <h3>How the tags work</h3>
            <p>
              Club tags pair with the True Carry app, free to start, no reader hardware
              needed. Tap a tag on your phone and the next shot is tagged to that club —
              so your carry numbers build themselves, club by club.
            </p>
          </div>
          <a href="/play" className="store-sim-link">
            While you wait, play a round in the sim →
          </a>
        </aside>
      </main>

      <SiteFooter />
    </div>
  );
}
