// Club bag. speed = ball speed off the face (m/s) at 100% power,
// launch in degrees, spin in rpm. Carries are computed at boot by
// simulating each club on flat ground (see main.js).

export const CLUBS = [
  { id: 'DR', name: 'DRIVER',  speed: 74, launch: 12.0, spin: 2500 },
  { id: 'W3', name: '3 WOOD',  speed: 69, launch: 13.5, spin: 3400 },
  { id: 'W5', name: '5 WOOD',  speed: 66, launch: 15.0, spin: 4100 },
  { id: 'HY', name: 'HYBRID',  speed: 63, launch: 16.0, spin: 4600 },
  { id: 'I4', name: '4 IRON',  speed: 60, launch: 16.5, spin: 5100 },
  { id: 'I5', name: '5 IRON',  speed: 58, launch: 17.5, spin: 5700 },
  { id: 'I6', name: '6 IRON',  speed: 55, launch: 18.5, spin: 6400 },
  { id: 'I7', name: '7 IRON',  speed: 53, launch: 20.0, spin: 7100 },
  { id: 'I8', name: '8 IRON',  speed: 50, launch: 22.0, spin: 7900 },
  { id: 'I9', name: '9 IRON',  speed: 47, launch: 24.5, spin: 8700 },
  { id: 'PW', name: 'P WEDGE', speed: 44, launch: 27.0, spin: 9400 },
  { id: 'GW', name: 'G WEDGE', speed: 40, launch: 30.0, spin: 9900 },
  { id: 'SW', name: 'S WEDGE', speed: 36, launch: 33.0, spin: 10300 },
  { id: 'PT', name: 'PUTTER',  speed: 7.2, launch: 0, spin: 0, putter: true },
];

// How the lie changes a swing: contact quality and spin generation.
export const LIE_EFFECT = {
  tee:     { speed: 1.00, spin: 1.00, jitter: 0.00 },
  fairway: { speed: 1.00, spin: 1.00, jitter: 0.01 },
  fringe:  { speed: 0.98, spin: 0.85, jitter: 0.01 },
  green:   { speed: 1.00, spin: 1.00, jitter: 0.00 },
  rough:   { speed: 0.85, spin: 0.45, jitter: 0.05 },
  sand:    { speed: 0.74, spin: 0.40, jitter: 0.07 },
};

export const YARDS = 1.09361;

export function fmtYards(meters) {
  return Math.round(meters * YARDS);
}
