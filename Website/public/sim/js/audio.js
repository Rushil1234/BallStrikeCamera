// Layered synthesized sound design: club-specific strikes, surface-aware
// bounces, cup rattle, ambience that follows wind and course profile.
// WebAudio only — no asset files, works offline, zero load time.

let ctx = null;
let master = null;
let muted = false;
let breezeGain = null;
let whistleGain = null;
let surfGain = null;
let birdTimer = null;

function ensure() {
  if (!ctx) {
    ctx = new (window.AudioContext || window.webkitAudioContext)();
    master = ctx.createGain();
    master.gain.value = 0.55;
    master.connect(ctx.destination);
    ambienceInit();
  }
  if (ctx.state === 'suspended') ctx.resume();
  return ctx;
}

function noiseBuffer(len = 1) {
  const buf = ctx.createBuffer(1, ctx.sampleRate * len, ctx.sampleRate);
  const d = buf.getChannelData(0);
  for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
  return buf;
}

function envGain(t0, a, peak, dec) {
  const g = ctx.createGain();
  g.gain.setValueAtTime(0, t0);
  g.gain.linearRampToValueAtTime(peak, t0 + a);
  g.gain.exponentialRampToValueAtTime(0.0001, t0 + a + dec);
  g.connect(master);
  return g;
}

function noiseHit(t, { type = 'bandpass', freq = 2000, q = 1, peak = 0.4, attack = 0.001, decay = 0.08, sweepTo = null, len = 0.3 }) {
  const src = ctx.createBufferSource();
  src.buffer = noiseBuffer(len);
  const f = ctx.createBiquadFilter();
  f.type = type; f.frequency.setValueAtTime(freq, t); f.Q.value = q;
  if (sweepTo) f.frequency.exponentialRampToValueAtTime(sweepTo, t + decay);
  src.connect(f);
  f.connect(envGain(t, attack, peak, decay));
  src.start(t); src.stop(t + len);
}

function toneHit(t, { type = 'sine', freq = 300, sweepTo = null, peak = 0.3, attack = 0.001, decay = 0.1 }) {
  const o = ctx.createOscillator();
  o.type = type;
  o.frequency.setValueAtTime(freq, t);
  if (sweepTo) o.frequency.exponentialRampToValueAtTime(sweepTo, t + decay);
  o.connect(envGain(t, attack, peak, decay));
  o.start(t); o.stop(t + attack + decay + 0.05);
}

// ---------- ambience ----------

function ambienceInit() {
  // low breeze bed
  const src = ctx.createBufferSource();
  src.buffer = noiseBuffer(3); src.loop = true;
  const lp = ctx.createBiquadFilter();
  lp.type = 'lowpass'; lp.frequency.value = 420; lp.Q.value = 0.4;
  breezeGain = ctx.createGain(); breezeGain.gain.value = 0.024;
  src.connect(lp); lp.connect(breezeGain); breezeGain.connect(master);
  src.start();
  const lfo = ctx.createOscillator(); lfo.frequency.value = 0.07;
  const lg = ctx.createGain(); lg.gain.value = 0.011;
  lfo.connect(lg); lg.connect(breezeGain.gain); lfo.start();

  // high wind whistle — silent until the wind is up
  const w = ctx.createBufferSource();
  w.buffer = noiseBuffer(2.4); w.loop = true;
  const bp = ctx.createBiquadFilter();
  bp.type = 'bandpass'; bp.frequency.value = 1600; bp.Q.value = 2.2;
  whistleGain = ctx.createGain(); whistleGain.gain.value = 0;
  w.connect(bp); bp.connect(whistleGain); whistleGain.connect(master);
  w.start();

  // distant surf — enabled on coastal courses
  const s2 = ctx.createBufferSource();
  s2.buffer = noiseBuffer(4); s2.loop = true;
  const slp = ctx.createBiquadFilter();
  slp.type = 'lowpass'; slp.frequency.value = 240; slp.Q.value = 0.3;
  surfGain = ctx.createGain(); surfGain.gain.value = 0;
  s2.connect(slp); slp.connect(surfGain); surfGain.connect(master);
  s2.start();
  const swl = ctx.createOscillator(); swl.frequency.value = 0.085;
  const swg = ctx.createGain(); swg.gain.value = 0.016;
  swl.connect(swg); swg.connect(surfGain.gain); swl.start();
}

function birdChirp() {
  if (!ctx || muted) return;
  const t = ctx.currentTime;
  const base = 2900 + Math.random() * 900;
  for (let i = 0; i < 2 + Math.floor(Math.random() * 2); i++) {
    const tt = t + i * (0.09 + Math.random() * 0.05);
    toneHit(tt, { freq: base * (1 + Math.random() * 0.12), sweepTo: base * 0.72, peak: 0.028, attack: 0.004, decay: 0.05 });
  }
}

export const SFX = {
  unlock() { ensure(); },

  setMuted(m) {
    muted = m;
    if (master) master.gain.value = m ? 0 : 0.55;
  },
  isMuted() { return muted; },

  /// Ambience follows the course: wind mph modulates breeze + whistle;
  /// coastal adds surf; parkland adds occasional birdsong.
  setAmbience({ windMph = 5, surf = false, birds = false } = {}) {
    if (!ctx) return;
    const w = Math.min(windMph / 20, 1);
    breezeGain.gain.setTargetAtTime(0.018 + w * 0.05, ctx.currentTime, 0.8);
    whistleGain.gain.setTargetAtTime(w > 0.45 ? (w - 0.45) * 0.05 : 0, ctx.currentTime, 1.2);
    surfGain.gain.setTargetAtTime(surf ? 0.05 : 0, ctx.currentTime, 1.5);
    clearInterval(birdTimer);
    birdTimer = null;
    if (birds) birdTimer = setInterval(() => { if (Math.random() < 0.5) birdChirp(); }, 9000);
  },

  /// Layered strike: click transient + crack body + thump, voiced per club
  /// family and lie. kind: 'driver' | 'wood' | 'iron' | 'wedge'; lie 'sand'
  /// adds the gritty splash of a bunker blast.
  strike(power = 1, putter = false, kind = 'iron', lie = 'fairway') {
    const c = ensure(); const t = c.currentTime;
    if (putter) {
      toneHit(t, { freq: 950, sweepTo: 320, peak: 0.26, decay: 0.05 });
      noiseHit(t, { freq: 3200, q: 2, peak: 0.05, decay: 0.02, len: 0.05 });
      return;
    }
    if (lie === 'sand') {
      // bunker blast: mostly sand, little ball
      noiseHit(t, { type: 'lowpass', freq: 900, peak: 0.5, attack: 0.004, decay: 0.28, sweepTo: 220, len: 0.5 });
      noiseHit(t, { freq: 2400, q: 0.8, peak: 0.18, decay: 0.1 });
      toneHit(t, { freq: 120, sweepTo: 55, peak: 0.2, decay: 0.12 });
      return;
    }
    // 1. click transient — the ball leaving the face
    noiseHit(t, { type: 'highpass', freq: 5200, peak: 0.32 + power * 0.2, decay: 0.012, len: 0.05 });
    // 2. crack body — brighter for driver, duller for wedges
    const bright = kind === 'driver' ? 3400 : kind === 'wood' ? 3000 : kind === 'wedge' ? 1900 : 2600;
    noiseHit(t, { freq: bright + power * 900, q: 1.2, peak: 0.4 + power * 0.4, decay: 0.05 + power * 0.02 });
    // 3. hollow pock for the big sticks (titanium face resonance)
    if (kind === 'driver' || kind === 'wood') {
      toneHit(t, { freq: 760, sweepTo: 480, peak: 0.22 * power + 0.08, decay: 0.05, type: 'triangle' });
    }
    // 4. low thump — turf/body energy
    toneHit(t, { freq: 170 + power * 80, sweepTo: 55, peak: 0.4 * power + 0.12, decay: 0.11 });
    // 5. wedges take turf: soft earthy scuff just after contact
    if (kind === 'wedge') {
      noiseHit(t + 0.012, { type: 'lowpass', freq: 700, peak: 0.16, decay: 0.09, len: 0.2 });
    }
  },

  /// Surface-aware landings.
  bounce(speed = 1, surface = 'fairway') {
    const c = ensure(); const t = c.currentTime;
    const v = Math.min(speed / 12, 1);
    if (v < 0.06) return;
    if (surface === 'sand') {
      noiseHit(t, { type: 'lowpass', freq: 620, peak: 0.16 * v + 0.03, decay: 0.09, sweepTo: 200, len: 0.2 });
      return;
    }
    if (surface === 'green') {
      // firm dead thud with a hint of check
      toneHit(t, { freq: 210 + v * 90, sweepTo: 90, peak: 0.1 * v + 0.02, decay: 0.05, type: 'sine' });
      return;
    }
    toneHit(t, { freq: 300 + v * 170, sweepTo: 110, peak: 0.12 * v + 0.02, decay: 0.07, type: 'triangle' });
    noiseHit(t, { type: 'lowpass', freq: 900, peak: 0.05 * v, decay: 0.05, len: 0.12 });
  },

  splash() {
    const c = ensure(); const t = c.currentTime;
    noiseHit(t, { type: 'lowpass', freq: 2600, sweepTo: 300, peak: 0.5, attack: 0.012, decay: 0.6, len: 0.8 });
    // droplets
    for (let i = 0; i < 4; i++) {
      toneHit(t + 0.12 + i * 0.07, { freq: 900 + Math.random() * 700, sweepTo: 400, peak: 0.05, decay: 0.05 });
    }
  },

  /// The real cup sound: knock, rattle, settle.
  holed() {
    const c = ensure(); const t = c.currentTime;
    toneHit(t, { freq: 900, sweepTo: 500, peak: 0.28, decay: 0.03, type: 'triangle' });
    toneHit(t + 0.05, { freq: 700, sweepTo: 420, peak: 0.22, decay: 0.03, type: 'triangle' });
    toneHit(t + 0.11, { freq: 560, sweepTo: 360, peak: 0.16, decay: 0.04, type: 'triangle' });
    noiseHit(t + 0.16, { type: 'lowpass', freq: 800, peak: 0.12, decay: 0.12, len: 0.25 });
    toneHit(t + 0.3, { freq: 840, peak: 0.16, decay: 0.35 });   // celebratory chime
  },

  tick() {
    const c = ensure(); const t = c.currentTime;
    toneHit(t, { freq: 1500, peak: 0.05, decay: 0.02, type: 'square' });
  },
};
