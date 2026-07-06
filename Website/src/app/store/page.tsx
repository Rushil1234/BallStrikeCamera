import type { Metadata } from "next";
import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";
import ClubCards from "@/components/ClubCards";

export const metadata: Metadata = {
  title: "Store",
  description:
    "NFC club cards, stands, and gear for True Carry — the camera launch monitor. Tag every club in your bag and let your gapping build itself.",
};

type Product = {
  id: string;
  name: string;
  price: string;
  tag: string;
  art: string;
  features: string[];
  status: string;
};

const PRODUCTS: Product[] = [
  {
    id: "full-bag",
    name: "Club Cards — Full Bag",
    price: "$29",
    tag: "Fourteen NFC cards. One for every club you carry.",
    art: "14",
    features: ["14 passive NFC cards", "Under-grip or bag-tag fit", "No batteries, no pairing", "Waterproof, tour-thin"],
    status: "Ships fall 2026",
  },
  {
    id: "short-game",
    name: "Club Cards — Short Game",
    price: "$15",
    tag: "Wedges and putter. Where the scoring happens.",
    art: "6",
    features: ["6 passive NFC cards", "Pre-labeled 48°–64° + putter", "Same tap-to-tag flow"],
    status: "Ships fall 2026",
  },
  {
    id: "stand",
    name: "The Stand",
    price: "$39",
    tag: "Puts the camera where the math wants it.",
    art: "△",
    features: ["Alignment guide for 240fps capture", "Folds to scorecard size", "Fits every iPhone"],
    status: "Ships fall 2026",
  },
  {
    id: "gift-pro",
    name: "Gift a year of Pro",
    price: "$99",
    tag: "Every yard, on someone else's card.",
    art: "Pro",
    features: ["12 months of True Carry Pro", "Advanced analytics + video export", "Delivered as a code"],
    status: "Available now",
  },
];

export default function StorePage() {
  return (
    <div className="store-page">
      <SiteNav />
      <header className="store-hero">
        <div className="store-hero-inner">
          <div className="store-hero-copy">
            <p className="store-kicker">The pro shop</p>
            <h1>Gear that knows<br /><span className="it">your bag.</span></h1>
            <p className="store-deck">
              Hardware is simple here: passive NFC cards that tell the app which club you&apos;re
              swinging, and a stand that holds the camera steady. Everything else is software.
            </p>
          </div>
          <div className="store-hero-cards">
            <ClubCards />
          </div>
        </div>
      </header>

      <main className="store-main">
        <div className="store-grid">
          {PRODUCTS.map((p) => (
            <article className="product" key={p.id}>
              <div className="product-art" aria-hidden><span>{p.art}</span></div>
              <div className="product-body">
                <div className="product-head">
                  <h2>{p.name}</h2>
                  <span className="product-price">{p.price}</span>
                </div>
                <p className="product-tag">{p.tag}</p>
                <ul>
                  {p.features.map((f) => <li key={f}>{f}</li>)}
                </ul>
                <div className="product-foot">
                  <span className={`product-status${p.status === "Available now" ? " live" : ""}`}>{p.status}</span>
                  {p.status === "Available now" ? (
                    <a className="product-cta" href="/#h07">Get it</a>
                  ) : (
                    <a
                      className="product-cta ghost"
                      href={`mailto:rushil@truecarrygolf.com?subject=Notify%20me%20—%20${encodeURIComponent(p.name)}`}
                    >
                      Notify me
                    </a>
                  )}
                </div>
              </div>
            </article>
          ))}
        </div>

        <div className="store-note">
          <p>
            Club cards pair with the True Carry app — free to start, no reader hardware needed.
            Tap a card on your phone and the next shot is tagged to that club.
          </p>
          <a href="/play" className="store-sim-link">While you wait, play a round in the sim →</a>
        </div>
      </main>
      <SiteFooter />
    </div>
  );
}
