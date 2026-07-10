// HUD: telemetry panels, 3-click swing meter, toasts, scorecard,
// and the top-down minimap (drawn straight from the hole definition).

import { fmtYards } from './clubs.js?v=gspro-11';

const $ = (id) => document.getElementById(id);

export function toParStr(n) {
  if (n === 0) return 'E';
  return n > 0 ? `+${n}` : `${n}`;
}

export class HUD {
  constructor() {
    this.el = {
      hud: $('hud'),
      hcHole: $('hc-hole'), hcPar: $('hc-par'), hcYds: $('hc-yds'),
      hcStroke: $('hc-stroke'), hcTotal: $('hc-total'), hcName: $('hc-name'),
      hcPlayer: $('hc-player'),
      wind: $('wind'), windArrow: $('wind-arrow'), windSpeed: $('wind-speed'),
      toast: $('toast'),
      clubName: $('club-name'), clubCarry: $('club-carry'),
      clubPrev: $('club-prev'), clubNext: $('club-next'),
      pinNum: $('pin-num'), pinUnit: document.querySelector('.pin-unit'),
      pinLabel: $('pin-label'), lieChip: $('lie-chip'), pinPlays: $('pin-plays'),
      shotData: $('shot-data'),
      sdSpeed: $('sd-speed'), sdClub: $('sd-club'), sdLaunch: $('sd-launch'),
      sdSide: $('sd-side'), sdSpin: $('sd-spin'),
      sdApex: $('sd-apex'), sdDesc: $('sd-desc'), sdOffline: $('sd-offline'),
      sdCarry: $('sd-carry'), sdTotal: $('sd-total'),
      meter: $('meter'), meterFill: $('meter-fill'), meterCursor: $('meter-cursor'),
      meterPowermark: $('meter-powermark'), meterReadout: $('meter-readout'),
      title: $('title-screen'), btnStart: $('btn-start'),
      intro: $('hole-intro'), introHole: $('intro-hole'),
      introName: $('intro-name'), introMeta: $('intro-meta'),
      scorecard: $('scorecard'), scoreTable: $('score-table'),
      summary: $('summary'), summaryScore: $('summary-score'),
      summaryTable: $('summary-table'), btnAgain: $('btn-again'),
      minimap: $('minimap'), mapWrap: $('map-wrap'),
      mapToggle: $('map-toggle'), mapCaption: $('map-caption'),
    };
    this.mapCtx = this.el.minimap.getContext('2d');
    this.toastTimer = null;
    this.mapMode = 'hole';
    this.mapHoles = [];
    this.mapWorld = null;
    this.mapCurrentIdx = 0;
    this.lastMapDraw = { ball: null, aimDir: null, pin: null };
  }

  show() { this.el.hud.classList.remove('hidden'); }
  hide() { this.el.hud.classList.add('hidden'); }

  setHole(num, par, yds, name) {
    this.el.hcHole.textContent = `HOLE ${num}`;
    this.el.hcPar.textContent = `PAR ${par}`;
    this.el.hcYds.textContent = `${yds} YDS`;
    this.el.hcName.textContent = name;
  }

  setStroke(stroke, totalToPar) {
    this.el.hcStroke.textContent = `STROKE ${stroke}`;
    this.el.hcTotal.textContent = `${toParStr(totalToPar)} TOTAL`;
  }

  /** Multi-player only — shows whose turn it is. Hidden entirely for single-player sessions. */
  setPlayer(name) {
    if (!this.el.hcPlayer) return;
    this.el.hcPlayer.textContent = `UP: ${(name || 'YOU').toUpperCase()}`;
    this.el.hcPlayer.classList.remove('hidden');
  }

  setWind(mph, relAngleRad) {
    this.el.windSpeed.textContent = Math.round(mph);
    this.el.windArrow.style.transform = `rotate(${relAngleRad * 180 / Math.PI}deg)`;
    this.el.wind.classList.toggle('calm', mph < 1);
  }

  setClub(name, carryMeters, putter) {
    this.el.clubName.textContent = name;
    this.el.clubCarry.textContent = putter ? 'ON THE DANCE FLOOR' : `${fmtYards(carryMeters)}y CARRY`;
  }

  setPin(meters, elevM = null) {
    if (meters < 23) {
      this.el.pinNum.textContent = Math.round(meters * 3.28084);
      this.el.pinUnit.textContent = 'ft';
    } else {
      this.el.pinNum.textContent = fmtYards(meters);
      this.el.pinUnit.textContent = 'y';
    }
    // elevation-adjusted "plays like" distance (GSPro-style)
    const plays = this.el.pinPlays;
    if (!plays) return;
    if (elevM == null || meters < 23 || Math.abs(elevM) < 0.9) {
      plays.classList.add('hidden');
    } else {
      const elevFt = Math.round(elevM * 3.28084);
      const playsY = fmtYards(meters + elevM);
      plays.innerHTML = `${elevFt > 0 ? '▲' : '▼'} ${Math.abs(elevFt)}ft · PLAYS <b>${playsY}y</b>`;
      plays.classList.remove('hidden');
    }
  }

  setLie(surface) {
    const label = {
      tee: 'TEE', fairway: 'FAIRWAY', fringe: 'FRINGE', rough: 'ROUGH',
      sand: 'BUNKER', green: 'GREEN', water: 'WATER',
    }[surface] || surface.toUpperCase();
    const chip = this.el.lieChip;
    chip.textContent = label;
    chip.classList.toggle('bad', surface === 'rough' || surface === 'sand');
    chip.classList.toggle('hazard', surface === 'water');
  }

  // ---------- launch monitor ----------

  shotDataShow({ speedMph, clubMph = null, launchDeg, sideDeg = null, spinRpm }) {
    this.el.sdSpeed.textContent = `${Math.round(speedMph)} mph`;
    if (this.el.sdClub) {
      this.el.sdClub.textContent = clubMph ? `${Math.round(clubMph)} mph` : '—';
    }
    this.el.sdLaunch.textContent = `${launchDeg.toFixed(1)}°`;
    if (this.el.sdSide) {
      this.el.sdSide.textContent = sideDeg == null || Math.abs(sideDeg) < 0.05
        ? '0.0°'
        : `${Math.abs(sideDeg).toFixed(1)}° ${sideDeg > 0 ? 'R' : 'L'}`;
    }
    this.el.sdSpin.textContent = `${Math.round(spinRpm / 10) * 10} rpm`;
    this.el.sdApex.textContent = '—';
    if (this.el.sdDesc) this.el.sdDesc.textContent = '—';
    if (this.el.sdOffline) this.el.sdOffline.textContent = '—';
    this.el.sdCarry.textContent = '—';
    this.el.sdTotal.textContent = '—';
    this.el.shotData.classList.remove('hidden');
  }

  shotDataApex(ft) {
    this.el.sdApex.textContent = `${Math.round(ft)} ft`;
  }

  shotDataResult(carryY, totalY, extra = null) {
    if (carryY != null) this.el.sdCarry.textContent = `${carryY}y`;
    if (totalY != null) this.el.sdTotal.textContent = `${totalY}y`;
    if (!extra) return;
    if (this.el.sdDesc && extra.descentDeg != null) {
      this.el.sdDesc.textContent = `${extra.descentDeg.toFixed(0)}°`;
    }
    if (this.el.sdOffline && extra.offlineM != null) {
      const y = Math.round(Math.abs(extra.offlineM) * 1.09361);
      this.el.sdOffline.textContent = y === 0 ? '0y' : `${y}y ${extra.offlineM < 0 ? 'L' : 'R'}`;
    }
  }

  shotDataHide() { this.el.shotData.classList.add('hidden'); }

  // ---------- swing meter ----------

  meterShow() { this.el.meter.classList.remove('hidden'); }
  meterHide() { this.el.meter.classList.add('hidden'); }

  meterUpdate({ cursor = 0, fill = 0, powerMark = null, text = '' }) {
    this.el.meterCursor.style.bottom = `${cursor * 100}%`;
    this.el.meterFill.style.height = `${fill * 100}%`;
    if (powerMark == null) {
      this.el.meterPowermark.classList.add('hidden');
    } else {
      this.el.meterPowermark.classList.remove('hidden');
      this.el.meterPowermark.style.bottom = `${powerMark * 100}%`;
    }
    this.el.meterReadout.textContent = text;
  }

  // ---------- toast ----------

  toast(html, ms = 2600) {
    clearTimeout(this.toastTimer);
    this.el.toast.innerHTML = html;
    this.el.toast.classList.remove('hidden');
    if (ms > 0) {
      this.toastTimer = setTimeout(() => this.el.toast.classList.add('hidden'), ms);
    }
  }
  toastHide() {
    clearTimeout(this.toastTimer);
    this.el.toast.classList.add('hidden');
  }

  // ---------- overlays ----------

  titleHide() { this.el.title.classList.add('hidden'); }

  introShow(num, name, par, yds) {
    this.el.introHole.textContent = `HOLE ${num}`;
    this.el.introName.textContent = name;
    this.el.introMeta.textContent = `PAR ${par} · ${yds} YDS`;
    this.el.intro.classList.remove('hidden');
  }
  introHide() { this.el.intro.classList.add('hidden'); }

  buildScoreRows(table, holes, scores) {
    const groups = holes.length > 9 ? [holes.slice(0, 9), holes.slice(9)] : [holes];
    let html = '';
    let runPar = 0, runScore = 0, runPlayedPar = 0;
    groups.forEach((g, gi) => {
      const offset = gi * 9;
      let head = '<tr><th></th>';
      let parRow = '<tr><td>PAR</td>';
      let scoreRow = '<tr><td>SCORE</td>';
      let gPar = 0, gScore = 0, gPlayedPar = 0;
      g.forEach((h, i) => {
        head += `<th>${h.id}</th>`;
        parRow += `<td>${h.par}</td>`;
        gPar += h.par;
        const s = scores[offset + i];
        if (s != null) {
          gPlayedPar += h.par; gScore += s;
          const cls = s < h.par ? 'under' : (s > h.par ? 'over' : '');
          scoreRow += `<td class="${cls}">${s}</td>`;
        } else {
          scoreRow += '<td>—</td>';
        }
      });
      const label = groups.length > 1 ? (gi ? 'IN' : 'OUT') : 'TOT';
      head += `<th>${label}</th>`;
      parRow += `<td>${gPar}</td>`;
      scoreRow += `<td>${gScore || '—'}</td>`;
      runPar += gPar; runScore += gScore; runPlayedPar += gPlayedPar;
      if (gi === groups.length - 1 && groups.length > 1) {
        const diff = runScore - runPlayedPar;
        head += '<th>TOT</th>';
        parRow += `<td>${runPar}</td>`;
        scoreRow += `<td>${runScore ? `${runScore} (${toParStr(diff)})` : '—'}</td>`;
      }
      html += `${head}</tr>${parRow}</tr>${scoreRow}</tr>`;
      if (gi === 0 && groups.length > 1) {
        html += '<tr class="card-gap"><td colspan="12"></td></tr>';
      }
    });
    table.innerHTML = html;
  }

  scorecardToggle(holes, scores) {
    const sc = this.el.scorecard;
    if (sc.classList.contains('hidden')) {
      this.buildScoreRows(this.el.scoreTable, holes, scores);
      sc.classList.remove('hidden');
    } else {
      sc.classList.add('hidden');
    }
  }
  scorecardHide() { this.el.scorecard.classList.add('hidden'); }

  summaryShow(holes, scores) {
    const totPar = holes.reduce((a, h) => a + h.par, 0);
    const tot = scores.reduce((a, s) => a + (s || 0), 0);
    this.el.summaryScore.textContent = toParStr(tot - totPar);
    this.buildScoreRows(this.el.summaryTable, holes, scores);
    this.el.summary.classList.remove('hidden');
  }
  summaryHide() { this.el.summary.classList.add('hidden'); }

  // ---------- minimap ----------

  mapSetCourse(holes, world) {
    this.mapHoles = holes || [];
    this.mapWorld = world || null;
    if (this.mapMode === 'all' && this.mapHoles.length <= 1) this.mapSetMode('hole');
  }

  mapSetMode(mode) {
    this.mapMode = mode === 'all' && this.mapHoles.length > 1 ? 'all' : 'hole';
    if (this.el.mapToggle) {
      this.el.mapToggle.textContent = this.mapMode === 'all' ? 'HOLE' : 'ALL';
      this.el.mapToggle.title = this.mapMode === 'all' ? 'View current hole (V)' : 'View all holes (V)';
    }
    if (this.el.mapWrap) {
      this.el.mapWrap.classList.toggle('map-mode-all', this.mapMode === 'all');
      this.el.mapWrap.classList.toggle('map-mode-hole', this.mapMode !== 'all');
    }
    if (this.el.mapCaption) {
      // A sea is only real when the course ships a coastline; inland
      // real-data courses (e.g. parkland) are 'coastal' profile but landlocked.
      const hasSea = !!(this.mapWorld?.coastline?.land?.length) || (this.mapWorld?.water?.length || 0) > 2;
      const allMapLabel = hasSea
        ? 'COASTAL MAP'
        : (this.mapWorld?.profile === 'coastal' ? 'COURSE MAP' : 'ISLAND MAP');
      this.el.mapCaption.textContent = this.mapMode === 'all'
        ? allMapLabel
        : (this.mapHole?.id != null ? `HOLE ${this.mapHole.id} MAP` : 'HOLE MAP');
    }
    this.mapDraw(this.lastMapDraw.ball, this.lastMapDraw.aimDir, this.lastMapDraw.pin);
  }

  mapToggleMode() {
    this.mapSetMode(this.mapMode === 'all' ? 'hole' : 'all');
    return this.mapMode;
  }

  mapSetHole(hole, idx = 0) {
    this.mapHole = hole;
    this.mapCurrentIdx = idx;
    if (this.el.mapCaption && this.mapMode !== 'all') this.el.mapCaption.textContent = `HOLE ${hole.id ?? idx + 1} MAP`;
    const tee = hole.path[0];
    const green = hole.path[hole.path.length - 1];
    const dx = green.x - tee.x, dz = green.z - tee.z;
    const L = Math.hypot(dx, dz) || 1;
    this.mapDir = { x: dx / L, z: dz / L };           // map "up"
    this.mapRight = { x: this.mapDir.z, z: -this.mapDir.x };

    // gather extents in rotated frame
    const pts = [...hole.path];
    for (const b of hole.bunkers || []) pts.push({ x: b.cx, z: b.cz });
    if (hole.green) pts.push({ x: hole.green.cx, z: hole.green.cz });
    let minF = Infinity, maxF = -Infinity, minS = Infinity, maxS = -Infinity;
    for (const p of pts) {
      const f = p.x * this.mapDir.x + p.z * this.mapDir.z;
      const s = p.x * this.mapRight.x + p.z * this.mapRight.z;
      minF = Math.min(minF, f); maxF = Math.max(maxF, f);
      minS = Math.min(minS, s); maxS = Math.max(maxS, s);
    }
    minF -= 30; maxF += 30; minS -= 38; maxS += 38;
    const W = this.el.minimap.width, H = this.el.minimap.height;
    this.mapScale = Math.min(W / (maxS - minS), H / (maxF - minF));
    this.mapMid = { f: (minF + maxF) / 2, s: (minS + maxS) / 2 };
  }

  mapPt(x, z) {
    const W = this.el.minimap.width, H = this.el.minimap.height;
    const f = x * this.mapDir.x + z * this.mapDir.z;
    const s = x * this.mapRight.x + z * this.mapRight.z;
    return [
      W / 2 + (s - this.mapMid.s) * this.mapScale,
      H / 2 - (f - this.mapMid.f) * this.mapScale,
    ];
  }

  mapWorldPt(x, z) {
    const W = this.el.minimap.width, H = this.el.minimap.height;
    const b = this.mapWorld?.bounds || this.mapHole?.island?.bounds;
    if (!b) return [W / 2, H / 2];
    const pad = 12;
    const sc = Math.min((W - pad * 2) / (b.maxX - b.minX), (H - pad * 2) / (b.maxZ - b.minZ));
    const cx = (b.minX + b.maxX) / 2;
    const cz = (b.minZ + b.maxZ) / 2;
    return [
      W / 2 + (x - cx) * sc,
      H / 2 - (z - cz) * sc,
    ];
  }

  drawCoastalBase() {
    const ctx = this.mapCtx;
    const W = this.el.minimap.width, H = this.el.minimap.height;
    const b = this.mapWorld?.bounds || this.mapHole?.island?.bounds;
    ctx.clearRect(0, 0, W, H);
    ctx.fillStyle = 'rgba(25, 65, 77, 0.95)';
    ctx.beginPath();
    ctx.roundRect(0, 0, W, H, 8);
    ctx.fill();
    if (!b) return;
    const landPts = (this.mapWorld?.coastline?.land || [
      [b.minX + 95, b.minZ + 90],
      [b.maxX - 95, b.minZ + 135],
      [b.maxX - 35, b.minZ + 365],
      [b.maxX - 120, b.maxZ - 325],
      [b.maxX - 335, b.maxZ - 95],
      [b.maxX - 590, b.maxZ - 260],
      [b.maxX - 840, b.maxZ - 230],
      [b.minX + 650, b.maxZ - 365],
      [b.minX + 440, b.maxZ - 245],
      [b.minX + 225, b.maxZ - 155],
      [b.minX + 80, b.maxZ - 370],
    ]).map((p) => Array.isArray(p) ? p : [p.x, p.z]);
    ctx.fillStyle = 'rgba(38, 76, 34, 0.96)';
    ctx.strokeStyle = 'rgba(236, 217, 173, 0.25)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    landPts.forEach(([px, pz], i) => {
      const [x, y] = this.mapWorldPt(px, pz);
      i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
    });
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    ctx.fillStyle = 'rgba(224, 180, 200, 0.65)';
    ctx.strokeStyle = 'rgba(236, 217, 173, 0.18)';
    ctx.lineWidth = 1;
    const beachPts = (this.mapWorld?.coastline?.beach || [
      [b.minX + 205, b.maxZ - 205],
      [b.minX + 430, b.maxZ - 300],
      [b.minX + 680, b.maxZ - 430],
      [b.maxX - 720, b.maxZ - 315],
      [b.maxX - 500, b.maxZ - 345],
      [b.maxX - 338, b.maxZ - 145],
      [b.maxX - 410, b.maxZ - 100],
      [b.maxX - 605, b.maxZ - 260],
      [b.maxX - 870, b.maxZ - 250],
      [b.minX + 640, b.maxZ - 380],
      [b.minX + 445, b.maxZ - 270],
      [b.minX + 240, b.maxZ - 170],
    ]).map((p) => Array.isArray(p) ? p : [p.x, p.z]);
    ctx.beginPath();
    beachPts.forEach(([px, pz], i) => {
      const [x, y] = this.mapWorldPt(px, pz);
      i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
    });
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    for (const line of this.mapWorld?.osmCoastline || []) {
      const pts = line.points || [];
      if (pts.length < 2) continue;
      ctx.strokeStyle = 'rgba(238, 204, 166, 0.82)';
      ctx.lineWidth = 2.2;
      ctx.beginPath();
      pts.forEach((p, i) => {
        const [x, y] = this.mapWorldPt(p.x, p.z);
        i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
      });
      ctx.stroke();
    }

    ctx.fillStyle = 'rgba(44, 120, 148, 0.88)';
    ctx.strokeStyle = 'rgba(146, 206, 224, 0.26)';
    ctx.lineWidth = 1;
    for (const w of this.mapWorld?.water || []) {
      if (w.type !== 'pond') continue;
      const [wx, wy] = this.mapWorldPt(w.cx, w.cz);
      const edge = this.mapWorldPt(w.cx + w.rx, w.cz);
      const sc = Math.abs(edge[0] - wx) / Math.max(w.rx, 1);
      ctx.beginPath();
      ctx.ellipse(wx, wy, Math.max(3, w.rx * sc), Math.max(3, w.rz * sc), -(w.rot || 0), 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
    }
  }

  drawIslandBase() {
    const ctx = this.mapCtx;
    const W = this.el.minimap.width, H = this.el.minimap.height;
    const b = this.mapWorld?.bounds || this.mapHole?.island?.bounds;
    const hasSea = !!(this.mapWorld?.coastline?.land?.length) || (this.mapWorld?.water?.length || 0) > 2;
    if (hasSea) {
      this.drawCoastalBase();
      return;
    }
    if (this.mapWorld?.profile === 'coastal') {
      // Landlocked real-data course: the whole frame is forested land.
      ctx.clearRect(0, 0, W, H);
      ctx.fillStyle = 'rgba(33, 62, 28, 0.96)';
      ctx.beginPath();
      ctx.roundRect(0, 0, W, H, 8);
      ctx.fill();
      return;
    }
    ctx.clearRect(0, 0, W, H);
    ctx.fillStyle = 'rgba(25, 65, 77, 0.95)';
    ctx.beginPath();
    ctx.roundRect(0, 0, W, H, 8);
    ctx.fill();
    if (!b) return;
    const cx = (b.minX + b.maxX) / 2;
    const cz = (b.minZ + b.maxZ) / 2;
    const rx = (b.maxX - b.minX) * 0.52;
    const rz = (b.maxZ - b.minZ) * 0.52;
    ctx.fillStyle = 'rgba(38, 76, 34, 0.94)';
    ctx.strokeStyle = 'rgba(236, 217, 173, 0.28)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (let i = 0; i <= 96; i++) {
      const a = (i / 96) * Math.PI * 2;
      const wobble = 1 + Math.sin(a * 3.1) * 0.035 + Math.sin(a * 7.0 + 0.7) * 0.025;
      const [x, y] = this.mapWorldPt(cx + Math.cos(a) * rx * wobble, cz + Math.sin(a) * rz * wobble);
      i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
    }
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    ctx.fillStyle = 'rgba(44, 120, 148, 0.9)';
    ctx.strokeStyle = 'rgba(146, 206, 224, 0.26)';
    ctx.lineWidth = 1;
    for (const w of this.mapWorld?.water || []) {
      if (w.type !== 'pond') continue;
      const [wx, wy] = this.mapWorldPt(w.cx, w.cz);
      const edge = this.mapWorldPt(w.cx + w.rx, w.cz);
      const sc = Math.abs(edge[0] - wx) / Math.max(w.rx, 1);
      ctx.beginPath();
      ctx.ellipse(wx, wy, Math.max(3, w.rx * sc), Math.max(3, w.rz * sc), -(w.rot || 0), 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
    }
  }

  drawHoleOnWorld(hole, idx, current) {
    const ctx = this.mapCtx;
    const b = this.mapWorld?.bounds || hole.island?.bounds;
    if (!b) return;
    const W = this.el.minimap.width, H = this.el.minimap.height;
    const sc = Math.min((W - 24) / (b.maxX - b.minX), (H - 24) / (b.maxZ - b.minZ));
    const drawWorldPoly = (feature, fill, stroke = null, alpha = 1) => {
      const pts = feature.points || [];
      if (pts.length < 3) return;
      ctx.save();
      ctx.globalAlpha = alpha;
      ctx.fillStyle = fill;
      if (stroke) ctx.strokeStyle = stroke;
      ctx.beginPath();
      pts.forEach((p, i) => {
        const [mx, my] = this.mapWorldPt(p.x, p.z);
        i ? ctx.lineTo(mx, my) : ctx.moveTo(mx, my);
      });
      ctx.closePath();
      ctx.fill();
      if (stroke) {
        ctx.lineWidth = current ? 1.2 : 0.7;
        ctx.stroke();
      }
      ctx.restore();
    };

    ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    for (const f of hole.osm?.rough || []) drawWorldPoly(f, '#315c2a', null, current ? 0.7 : 0.45);
    for (const f of hole.osm?.fairways || []) drawWorldPoly(f, current ? '#5f9e45' : '#4e8638', null, current ? 0.95 : 0.72);
    ctx.strokeStyle = current ? 'rgba(236, 217, 173, 0.95)' : 'rgba(81, 143, 60, 0.78)';
    ctx.lineWidth = Math.max(current ? 4 : 2.2, Math.min(7, (hole.fairwayHalf || 12) * 2 * sc));
    ctx.beginPath();
    (hole.path || []).forEach((p, i) => {
      const [mx, my] = this.mapWorldPt(p.x, p.z);
      i ? ctx.lineTo(mx, my) : ctx.moveTo(mx, my);
    });
    ctx.stroke();

    for (const f of hole.osm?.greens || []) drawWorldPoly(f, current ? '#94d66f' : '#6cae55', null, 1);

    ctx.fillStyle = current ? '#94d66f' : '#6cae55';
    if (hole.green) {
      const [gx, gy] = this.mapWorldPt(hole.green.cx, hole.green.cz);
      const r = Math.max(2.2, ((hole.green.rx + hole.green.rz) / 2) * sc);
      ctx.beginPath(); ctx.arc(gx, gy, r, 0, Math.PI * 2); ctx.fill();
    }

    ctx.fillStyle = '#dcc995';
    for (const f of hole.osm?.bunkers || []) drawWorldPoly(f, '#dcc995', null, 0.98);
    for (const s of hole.bunkers || []) {
      const [sx, sy] = this.mapWorldPt(s.cx, s.cz);
      const r = Math.max(1.3, ((s.rx + s.rz) / 2) * sc);
      ctx.beginPath(); ctx.arc(sx, sy, r, 0, Math.PI * 2); ctx.fill();
    }

    ctx.fillStyle = '#2f7790'; ctx.strokeStyle = '#2f7790';
    for (const w of hole.water || []) {
      if (w.type === 'pond') {
        const [wx, wy] = this.mapWorldPt(w.cx, w.cz);
        ctx.beginPath(); ctx.ellipse(wx, wy, Math.max(2, w.rx * sc), Math.max(2, w.rz * sc), 0, 0, Math.PI * 2); ctx.fill();
      } else {
        ctx.lineWidth = Math.max(1.5, (w.width || 8) * sc);
        ctx.beginPath();
        (w.pts || []).forEach((p, i) => {
          const [mx, my] = this.mapWorldPt(p.x, p.z);
          i ? ctx.lineTo(mx, my) : ctx.moveTo(mx, my);
        });
        ctx.stroke();
      }
    }

    const tee = hole.path?.[0];
    if (tee) {
      const [tx, ty] = this.mapWorldPt(tee.x, tee.z);
      ctx.fillStyle = current ? '#0a110c' : 'rgba(10,17,12,0.72)';
      ctx.strokeStyle = current ? '#ecd9ad' : 'rgba(236,217,173,0.45)';
      ctx.lineWidth = 1;
      ctx.beginPath(); ctx.arc(tx, ty, current ? 5 : 4, 0, Math.PI * 2); ctx.fill(); ctx.stroke();
      ctx.fillStyle = current ? '#ecd9ad' : 'rgba(242,238,225,0.72)';
      ctx.font = '700 8px Rajdhani, sans-serif';
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText(String(hole.id ?? idx + 1), tx, ty + 0.2);
    }
  }

  mapDrawAll(ball, aimDir, pin) {
    this.drawIslandBase();
    const ctx = this.mapCtx;
    ctx.setLineDash([3, 5]);
    ctx.strokeStyle = 'rgba(236, 217, 173, 0.25)';
    ctx.lineWidth = 1;
    for (const c of this.mapWorld?.connectors || []) {
      const [x1, y1] = this.mapWorldPt(c.from.x, c.from.z);
      const [x2, y2] = this.mapWorldPt(c.to.x, c.to.z);
      ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke();
    }
    ctx.setLineDash([]);

    this.mapHoles.forEach((h, i) => this.drawHoleOnWorld(h, i, i === this.mapCurrentIdx));

    if (pin) {
      const [px, py] = this.mapWorldPt(pin.x, pin.z);
      ctx.fillStyle = '#e2654f';
      ctx.beginPath(); ctx.arc(px, py, 3.2, 0, Math.PI * 2); ctx.fill();
    }
    if (ball) {
      const [bx, by] = this.mapWorldPt(ball.x, ball.z);
      ctx.fillStyle = '#f7f5ec';
      ctx.strokeStyle = 'rgba(0,0,0,0.7)';
      ctx.lineWidth = 1;
      ctx.beginPath(); ctx.arc(bx, by, 3.8, 0, Math.PI * 2); ctx.fill(); ctx.stroke();
      if (aimDir) {
        const [ax, ay] = this.mapWorldPt(ball.x + aimDir.x * 80, ball.z + aimDir.z * 80);
        ctx.strokeStyle = 'rgba(236, 217, 173, 0.8)';
        ctx.lineWidth = 1;
        ctx.beginPath(); ctx.moveTo(bx, by); ctx.lineTo(ax, ay); ctx.stroke();
      }
    }
  }

  mapDraw(ball, aimDir, pin) {
    if (!this.mapHole) return;
    this.lastMapDraw = { ball, aimDir, pin };
    if (this.mapMode === 'all' && this.mapHoles.length > 1) {
      this.mapDrawAll(ball, aimDir, pin);
      return;
    }
    const ctx = this.mapCtx;
    const hole = this.mapHole;
    const W = this.el.minimap.width, H = this.el.minimap.height;
    const sc = this.mapScale;
    ctx.clearRect(0, 0, W, H);

    // rough backdrop
    ctx.fillStyle = 'rgba(34, 58, 28, 0.85)';
    ctx.beginPath();
    ctx.roundRect(0, 0, W, H, 9);
    ctx.fill();

    // fairway corridor
    const drawHolePoly = (feature, fill, stroke = null, alpha = 1) => {
      const pts = feature.points || [];
      if (pts.length < 3) return;
      ctx.save();
      ctx.globalAlpha = alpha;
      ctx.fillStyle = fill;
      if (stroke) ctx.strokeStyle = stroke;
      ctx.beginPath();
      pts.forEach((p, i) => {
        const [mx, my] = this.mapPt(p.x, p.z);
        i ? ctx.lineTo(mx, my) : ctx.moveTo(mx, my);
      });
      ctx.closePath();
      ctx.fill();
      if (stroke) {
        ctx.lineWidth = 1;
        ctx.stroke();
      }
      ctx.restore();
    };
    for (const f of hole.osm?.rough || []) drawHolePoly(f, '#315c2a', null, 0.55);
    for (const f of hole.osm?.fairways || []) drawHolePoly(f, '#4f8a3c', null, 0.95);

    ctx.strokeStyle = '#4f8a3c';
    ctx.lineWidth = hole.fairwayHalf * 2 * sc;
    ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    ctx.beginPath();
    hole.path.forEach((p, i) => {
      const [mx, my] = this.mapPt(p.x, p.z);
      i ? ctx.lineTo(mx, my) : ctx.moveTo(mx, my);
    });
    ctx.stroke();

    // water
    ctx.fillStyle = '#2a5d74'; ctx.strokeStyle = '#2a5d74';
    for (const w of hole.water || []) {
      if (w.type === 'pond') {
        const [mx, my] = this.mapPt(w.cx, w.cz);
        ctx.beginPath();
        ctx.ellipse(mx, my, w.rx * sc, w.rz * sc, 0, 0, Math.PI * 2);
        ctx.fill();
      } else {
        ctx.lineWidth = w.width * sc;
        ctx.beginPath();
        w.pts.forEach((p, i) => {
          const [mx, my] = this.mapPt(p.x, p.z);
          i ? ctx.lineTo(mx, my) : ctx.moveTo(mx, my);
        });
        ctx.stroke();
      }
    }

    // green
    for (const f of hole.osm?.greens || []) drawHolePoly(f, '#79bb60', null, 1);
    {
      const g = hole.green;
      const [mx, my] = this.mapPt(g.cx, g.cz);
      ctx.fillStyle = '#79bb60';
      ctx.beginPath();
      ctx.ellipse(mx, my, ((g.rx + g.rz) / 2) * sc, ((g.rx + g.rz) / 2) * sc, 0, 0, Math.PI * 2);
      ctx.fill();
    }

    // bunkers
    ctx.fillStyle = '#dcc995';
    for (const f of hole.osm?.bunkers || []) drawHolePoly(f, '#dcc995', null, 0.98);
    for (const b of hole.bunkers || []) {
      const [mx, my] = this.mapPt(b.cx, b.cz);
      ctx.beginPath();
      ctx.ellipse(mx, my, ((b.rx + b.rz) / 2) * sc, ((b.rx + b.rz) / 2) * sc, 0, 0, Math.PI * 2);
      ctx.fill();
    }

    // aim line
    if (ball && aimDir) {
      const [bx, by] = this.mapPt(ball.x, ball.z);
      const [ax, ay] = this.mapPt(ball.x + aimDir.x * 400, ball.z + aimDir.z * 400);
      ctx.strokeStyle = 'rgba(236, 217, 173, 0.55)';
      ctx.lineWidth = 1;
      ctx.setLineDash([4, 4]);
      ctx.beginPath(); ctx.moveTo(bx, by); ctx.lineTo(ax, ay); ctx.stroke();
      ctx.setLineDash([]);
    }

    // pin
    if (pin) {
      const [px, py] = this.mapPt(pin.x, pin.z);
      ctx.fillStyle = '#e2654f';
      ctx.beginPath(); ctx.arc(px, py, 3, 0, Math.PI * 2); ctx.fill();
    }

    // ball
    if (ball) {
      const [bx, by] = this.mapPt(ball.x, ball.z);
      ctx.fillStyle = '#f7f5ec';
      ctx.strokeStyle = 'rgba(0,0,0,0.6)';
      ctx.lineWidth = 1;
      ctx.beginPath(); ctx.arc(bx, by, 3, 0, Math.PI * 2); ctx.fill(); ctx.stroke();
    }
  }
}
