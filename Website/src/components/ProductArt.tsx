// Studio product renders.
//
// WHY THESE ARE DRAWN AND NOT PHOTOGRAPHED: Unsplash and Pexels both block
// scraping (401/403) and their APIs need keys we don't have; the openly-licensed
// pools (Openverse/Flickr) mostly return other brands' gear — one "golf polo"
// result was a competitor's branded shirt. Putting a stock photo of somebody
// else's polo under the heading "The True Carry Polo" is both misleading to the
// customer and a trademark problem. So these are rendered as our own product, on
// a studio backdrop, with real material shading rather than flat line art.
//
// TO SWAP IN REAL PHOTOS: drop files at /public/store/<id>.jpg and this component
// uses them automatically — see PHOTO below. No other file needs to change.

import Image from "next/image";
import type { JSX } from "react";

type Props = { kind: string; priority?: boolean };

/** Product ids with a real, honest photo at /public/store/<id>.jpg; these bypass
 *  the render below. Objects are given a focal point so the cropped card frames
 *  the subject. foam-balls has NO entry on purpose — every stock "practice ball"
 *  photo was branded hard range balls, which misrepresent a foam product, so it
 *  keeps the clean render. Alt text describes the honest scene, not the product. */
const PHOTO: Record<string, { src: string; alt: string; pos?: string }> = {
  "nfc-tag": {
    src: "/store/nfc-tag.jpg",
    alt: "A golfer's gloved hands gripping a club on the course",
    pos: "center 40%",
  },
  tripod: {
    src: "/store/tripod.jpg",
    alt: "An iPhone mounted on a tripod, filming outdoors",
    pos: "center center",
  },
  polo: {
    src: "/store/polo.jpg",
    alt: "A golfer in a plain white polo at sunset, club over the shoulder",
    pos: "center 25%",
  },
  "gift-card": {
    src: "/store/gift-card.jpg",
    alt: "A golf green at dusk",
    pos: "center 55%",
  },
};

const F = {
  forest: "#1E2A22",
  deep: "#16201A",
  raise: "#2A3A2E",
  gold: "#B89A5E",
  goldBright: "#CBB079",
  goldDeep: "#8C7240",
  bone: "#ECE4D2",
  paper: "#F4EFE2",
};

/** Soft contact shadow — every product sits on the same studio floor. */
function Floor({ cx = 100, cy = 132, rx = 54, ry = 7 }) {
  return <ellipse cx={cx} cy={cy} rx={rx} ry={ry} fill="url(#floorShadow)" />;
}

function Defs({ id }: { id: string }) {
  return (
    <defs>
      <radialGradient id="floorShadow">
        <stop offset="0%" stopColor={F.deep} stopOpacity="0.28" />
        <stop offset="70%" stopColor={F.deep} stopOpacity="0.08" />
        <stop offset="100%" stopColor={F.deep} stopOpacity="0" />
      </radialGradient>
      {/* Body: lit from upper-left, like a softbox */}
      <linearGradient id={`${id}-body`} x1="0" y1="0" x2="0.7" y2="1">
        <stop offset="0%" stopColor={F.raise} />
        <stop offset="55%" stopColor={F.forest} />
        <stop offset="100%" stopColor={F.deep} />
      </linearGradient>
      <linearGradient id={`${id}-metal`} x1="0" y1="0" x2="1" y2="1">
        <stop offset="0%" stopColor={F.goldBright} />
        <stop offset="45%" stopColor={F.gold} />
        <stop offset="100%" stopColor={F.goldDeep} />
      </linearGradient>
      <linearGradient id={`${id}-gloss`} x1="0" y1="0" x2="0.4" y2="1">
        <stop offset="0%" stopColor="#fff" stopOpacity="0.22" />
        <stop offset="60%" stopColor="#fff" stopOpacity="0.04" />
        <stop offset="100%" stopColor="#fff" stopOpacity="0" />
      </linearGradient>
    </defs>
  );
}

function NfcTag() {
  return (
    <svg viewBox="0 0 200 150" role="img" aria-label="A True Carry NFC club tag">
      <Defs id="tag" />
      {/* The tag is a tall, narrow object — scale it up inside the shared 4:3
          viewBox so it reads at the same visual weight as the wider products. */}
      <g transform="translate(100 77) scale(1.34) translate(-100 -77)">
      <Floor rx={40} />
      {/* tag body */}
      <rect x="62" y="30" width="76" height="94" rx="14" fill="url(#tag-body)" />
      <rect x="62" y="30" width="76" height="94" rx="14" fill="url(#tag-gloss)" />
      <rect x="62.8" y="30.8" width="74.4" height="92.4" rx="13.2" fill="none" stroke={F.gold} strokeOpacity="0.5" strokeWidth="1.2" />
      {/* lanyard hole */}
      <circle cx="100" cy="44" r="4.6" fill={F.deep} />
      <circle cx="100" cy="44" r="4.6" fill="none" stroke={F.gold} strokeOpacity="0.55" strokeWidth="0.9" />
      {/* embossed NFC waves */}
      <g fill="none" stroke="url(#tag-metal)" strokeLinecap="round" strokeWidth="2.4">
        <path d="M89 88a14 14 0 0 1 0-18" opacity="0.95" />
        <path d="M97 95a24 24 0 0 1 0-32" opacity="0.7" />
        <path d="M105 102a34 34 0 0 1 0-46" opacity="0.45" />
      </g>
      <circle cx="85" cy="79" r="3" fill="url(#tag-metal)" />
      {/* club label plate */}
      <rect x="76" y="108" width="48" height="9" rx="4.5" fill={F.deep} fillOpacity="0.7" />
      <rect x="82" y="111.6" width="36" height="1.8" rx="0.9" fill={F.gold} fillOpacity="0.55" />
      </g>
    </svg>
  );
}

function FoamBalls() {
  const ball = (cx: number, cy: number, r: number, o = 1) => {
    const dimples: [number, number][] = [];
    for (let ring = 1; ring <= 3; ring++) {
      const rr = (r * ring) / 4;
      const n = ring * 5;
      for (let i = 0; i < n; i++) {
        const a = (i / n) * Math.PI * 2 + ring;
        dimples.push([cx + rr * Math.cos(a) - r * 0.1, cy + rr * Math.sin(a) - r * 0.1]);
      }
    }
    return (
      <g opacity={o}>
        <circle cx={cx} cy={cy} r={r} fill={F.paper} />
        <circle cx={cx} cy={cy} r={r} fill="url(#ball-shade)" />
        {dimples.map(([x, y], i) => {
          const d = Math.hypot(x - cx, y - cy);
          if (d > r * 0.82) return null;
          return <circle key={i} cx={x} cy={y} r={r * 0.062} fill={F.forest} fillOpacity="0.13" />;
        })}
        <ellipse cx={cx - r * 0.34} cy={cy - r * 0.4} rx={r * 0.3} ry={r * 0.2}
          fill="#fff" fillOpacity="0.55" transform={`rotate(-32 ${cx - r * 0.34} ${cy - r * 0.4})`} />
        <circle cx={cx} cy={cy} r={r} fill="none" stroke={F.forest} strokeOpacity="0.16" strokeWidth="0.9" />
      </g>
    );
  };
  return (
    <svg viewBox="0 0 200 150" role="img" aria-label="True Carry foam practice balls">
      <Defs id="ball" />
      <defs>
        <radialGradient id="ball-shade" cx="0.34" cy="0.3" r="0.85">
          <stop offset="0%" stopColor="#fff" stopOpacity="0.9" />
          <stop offset="55%" stopColor={F.paper} stopOpacity="0" />
          <stop offset="100%" stopColor={F.forest} stopOpacity="0.3" />
        </radialGradient>
      </defs>
      <ellipse cx="76" cy="130" rx="30" ry="5" fill="url(#floorShadow)" />
      <ellipse cx="132" cy="126" rx="22" ry="4" fill="url(#floorShadow)" />
      {ball(134, 92, 25, 0.92)}
      {ball(76, 82, 38)}
    </svg>
  );
}

function Tripod() {
  return (
    <svg viewBox="0 0 200 150" role="img" aria-label="The True Carry tripod holding a phone">
      <Defs id="tri" />
      <Floor cy={136} rx={50} ry={6} />
      {/* legs (back leg first for depth) */}
      <g stroke="url(#tri-metal)" strokeLinecap="round" fill="none">
        <path d="M100 74v58" strokeWidth="4" opacity="0.55" />
        <path d="M100 74 62 132" strokeWidth="5" />
        <path d="M100 74l38 58" strokeWidth="5" />
      </g>
      {/* leg brace */}
      <path d="M78 104h44" stroke={F.gold} strokeOpacity="0.35" strokeWidth="2" strokeLinecap="round" />
      {/* head */}
      <rect x="88" y="64" width="24" height="12" rx="4" fill="url(#tri-body)" />
      <rect x="88" y="64" width="24" height="12" rx="4" fill="url(#tri-gloss)" />
      {/* phone, landscape */}
      <rect x="52" y="22" width="96" height="44" rx="7" fill="url(#tri-body)" />
      <rect x="56" y="26" width="88" height="36" rx="4" fill={F.deep} />
      <rect x="56" y="26" width="88" height="36" rx="4" fill="url(#tri-gloss)" />
      {/* on-screen: the shot trace */}
      <path d="M64 54c14-16 30-22 46-20 8 1 14 4 20 9" fill="none" stroke="url(#tri-metal)" strokeWidth="2" strokeLinecap="round" />
      <circle cx="64" cy="54" r="2.6" fill={F.goldBright} />
      <rect x="112" y="32" width="26" height="7" rx="3.5" fill={F.gold} fillOpacity="0.22" />
      {/* lens */}
      <circle cx="150" cy="30" r="3.2" fill={F.raise} stroke={F.gold} strokeOpacity="0.5" strokeWidth="0.9" />
    </svg>
  );
}

function Polo() {
  return (
    <svg viewBox="0 0 200 150" role="img" aria-label="The True Carry polo shirt">
      <Defs id="polo" />
      <Floor cy={134} rx={46} ry={6} />
      {/* body + sleeves */}
      <path d="M78 26 46 40l10 26 14-6v58h60V60l14 6 10-26-32-14z"
        fill="url(#polo-body)" strokeLinejoin="round" />
      <path d="M78 26 46 40l10 26 14-6v58h60V60l14 6 10-26-32-14z" fill="url(#polo-gloss)" />
      {/* fabric folds */}
      <g stroke={F.deep} strokeOpacity="0.35" strokeLinecap="round" fill="none">
        <path d="M74 82c3 14 2 24 0 32" strokeWidth="1.6" />
        <path d="M126 82c-3 14-2 24 0 32" strokeWidth="1.6" />
        <path d="M60 62l8-4" strokeWidth="1.4" />
      </g>
      {/* collar */}
      <path d="M78 26 100 44l22-18-10-4-12 8-12-8z" fill={F.raise} />
      <path d="M78 26 100 44l22-18" fill="none" stroke={F.gold} strokeOpacity="0.5" strokeWidth="1.3" strokeLinejoin="round" />
      {/* placket + buttons */}
      <path d="M100 44v22" stroke={F.deep} strokeOpacity="0.55" strokeWidth="2.4" strokeLinecap="round" />
      <circle cx="100" cy="52" r="1.5" fill={F.gold} fillOpacity="0.8" />
      <circle cx="100" cy="62" r="1.5" fill={F.gold} fillOpacity="0.8" />
      {/* embroidered mark, left chest */}
      <circle cx="126" cy="60" r="5.4" fill="none" stroke="url(#polo-metal)" strokeWidth="1.6" />
      <path d="M123.4 60.6l2 2 3.4-4" fill="none" stroke="url(#polo-metal)" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function GiftCard() {
  return (
    <svg viewBox="0 0 200 150" role="img" aria-label="A True Carry gift card">
      <Defs id="gc" />
      <Floor cy={128} rx={48} ry={6} />
      {/* back card, offset for depth */}
      <rect x="52" y="34" width="104" height="64" rx="9" fill={F.raise} opacity="0.5"
        transform="rotate(-7 100 66)" />
      {/* front card */}
      <g transform="rotate(-3 100 70)">
        <rect x="44" y="42" width="112" height="68" rx="10" fill="url(#gc-body)" />
        <rect x="44" y="42" width="112" height="68" rx="10" fill="url(#gc-gloss)" />
        <rect x="45" y="43" width="110" height="66" rx="9" fill="none" stroke="url(#gc-metal)" strokeWidth="1.4" />
        {/* foil wordmark */}
        <path d="M62 66h26M62 66v-4M75 66v14" stroke="url(#gc-metal)" strokeWidth="2.2" strokeLinecap="round" fill="none" />
        <text x="62" y="94" fill={F.bone} fillOpacity="0.5"
          style={{ font: "italic 11px ui-serif, Georgia, serif" }}>gift card</text>
        {/* value chip */}
        <rect x="112" y="76" width="30" height="18" rx="5" fill={F.deep} fillOpacity="0.6" />
        <text x="127" y="89" textAnchor="middle" fill={F.goldBright}
          style={{ font: "600 11px ui-monospace, SFMono-Regular, monospace" }}>$50</text>
        {/* magstripe hint */}
        <rect x="56" y="52" width="16" height="10" rx="2.5" fill="url(#gc-metal)" fillOpacity="0.85" />
        <path d="M60 52v10M64 52v10M68 52v10" stroke={F.deep} strokeOpacity="0.35" strokeWidth="0.8" />
      </g>
    </svg>
  );
}

const MARKS: Record<string, () => JSX.Element> = {
  "nfc-tag": NfcTag,
  "foam-balls": FoamBalls,
  tripod: Tripod,
  polo: Polo,
  "gift-card": GiftCard,
};

export default function ProductArt({ kind, priority }: Props) {
  const photo = PHOTO[kind];
  if (photo) {
    return (
      <div className="product-photo">
        <Image src={photo.src} alt={photo.alt} fill priority={priority}
          sizes="(max-width: 900px) 100vw, 560px"
          style={{ objectFit: "cover", objectPosition: photo.pos ?? "center" }} />
      </div>
    );
  }
  const Mark = MARKS[kind];
  if (!Mark) return null;
  return (
    <div className="product-mark">
      <Mark />
    </div>
  );
}
