// Synthesized sound: club strikes, bounces, cup drop, splash, UI ticks,
// plus a gentle breeze ambience. WebAudio only — no asset files.

let ctx = null;
let master = null;
let muted = false;

function ensure() {
  if (!ctx) {
    ctx = new (window.AudioContext || window.webkitAudioContext)();
    master = ctx.createGain();
    master.gain.value = 0.55;
    master.connect(ctx.destination);
    breeze();
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

function breeze() {
  const src = ctx.createBufferSource();
  src.buffer = noiseBuffer(3);
  src.loop = true;
  const lp = ctx.createBiquadFilter();
  lp.type = 'lowpass'; lp.frequency.value = 420; lp.Q.value = 0.4;
  const g = ctx.createGain(); g.gain.value = 0.028;
  src.connect(lp); lp.connect(g); g.connect(master);
  src.start();
  // slow swell
  const lfo = ctx.createOscillator(); lfo.frequency.value = 0.07;
  const lg = ctx.createGain(); lg.gain.value = 0.012;
  lfo.connect(lg); lg.connect(g.gain);
  lfo.start();
}

export const SFX = {
  unlock() { ensure(); },

  setMuted(m) {
    muted = m;
    if (master) master.gain.value = m ? 0 : 0.55;
  },
  isMuted() { return muted; },

  // power 0..1, sharp = irons/driver, soft = putter
  strike(power = 1, putter = false) {
    const c = ensure(); const t = c.currentTime;
    if (putter) {
      const o = c.createOscillator();
      o.type = 'sine'; o.frequency.setValueAtTime(900, t);
      o.frequency.exponentialRampToValueAtTime(300, t + 0.04);
      o.connect(envGain(t, 0.002, 0.3, 0.06));
      o.start(t); o.stop(t + 0.1);
      return;
    }
    const src = c.createBufferSource();
    src.buffer = noiseBuffer(0.2);
    const bp = c.createBiquadFilter();
    bp.type = 'bandpass'; bp.frequency.value = 2400 + power * 1800; bp.Q.value = 1.1;
    src.connect(bp);
    bp.connect(envGain(t, 0.001, 0.5 + power * 0.45, 0.07));
    src.start(t); src.stop(t + 0.2);
    const o = c.createOscillator();
    o.type = 'sine';
    o.frequency.setValueAtTime(180 + power * 90, t);
    o.frequency.exponentialRampToValueAtTime(60, t + 0.09);
    o.connect(envGain(t, 0.001, 0.5 * power + 0.15, 0.12));
    o.start(t); o.stop(t + 0.16);
  },

  bounce(speed = 1) {
    const c = ensure(); const t = c.currentTime;
    const v = Math.min(speed / 12, 1);
    if (v < 0.06) return;
    const o = c.createOscillator();
    o.type = 'triangle';
    o.frequency.setValueAtTime(330 + v * 180, t);
    o.frequency.exponentialRampToValueAtTime(120, t + 0.07);
    o.connect(envGain(t, 0.001, 0.12 * v + 0.02, 0.08));
    o.start(t); o.stop(t + 0.12);
  },

  splash() {
    const c = ensure(); const t = c.currentTime;
    const src = c.createBufferSource();
    src.buffer = noiseBuffer(0.8);
    const lp = c.createBiquadFilter();
    lp.type = 'lowpass';
    lp.frequency.setValueAtTime(2600, t);
    lp.frequency.exponentialRampToValueAtTime(300, t + 0.6);
    src.connect(lp);
    lp.connect(envGain(t, 0.012, 0.5, 0.65));
    src.start(t); src.stop(t + 0.8);
  },

  holed() {
    const c = ensure(); const t = c.currentTime;
    // rattle + two-tone chime
    const o1 = c.createOscillator();
    o1.type = 'sine'; o1.frequency.setValueAtTime(620, t);
    o1.connect(envGain(t, 0.002, 0.22, 0.1));
    o1.start(t); o1.stop(t + 0.12);
    const o2 = c.createOscillator();
    o2.type = 'sine'; o2.frequency.setValueAtTime(840, t + 0.13);
    o2.connect(envGain(t + 0.13, 0.002, 0.3, 0.4));
    o2.start(t + 0.13); o2.stop(t + 0.6);
  },

  tick() {
    const c = ensure(); const t = c.currentTime;
    const o = c.createOscillator();
    o.type = 'square'; o.frequency.value = 1500;
    o.connect(envGain(t, 0.001, 0.06, 0.025));
    o.start(t); o.stop(t + 0.04);
  },
};
