// HUD: telemetry panels, 3-click swing meter, toasts, scorecard,
// and the top-down minimap (drawn straight from the hole definition).

import { fmtYards } from './clubs.js';

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
      wind: $('wind'), windArrow: $('wind-arrow'), windSpeed: $('wind-speed'),
      toast: $('toast'),
      clubName: $('club-name'), clubCarry: $('club-carry'),
      clubPrev: $('club-prev'), clubNext: $('club-next'),
      pinNum: $('pin-num'), pinUnit: document.querySelector('.pin-unit'),
      pinLabel: $('pin-label'), lieChip: $('lie-chip'),
      shotData: $('shot-data'),
      sdSpeed: $('sd-speed'), sdLaunch: $('sd-launch'), sdSpin: $('sd-spin'),
      sdApex: $('sd-apex'), sdCarry: $('sd-carry'), sdTotal: $('sd-total'),
      meter: $('meter'), meterFill: $('meter-fill'), meterCursor: $('meter-cursor'),
      meterPowermark: $('meter-powermark'), meterReadout: $('meter-readout'),
      title: $('title-screen'), btnStart: $('btn-start'),
      intro: $('hole-intro'), introHole: $('intro-hole'),
      introName: $('intro-name'), introMeta: $('intro-meta'),
      scorecard: $('scorecard'), scoreTable: $('score-table'),
      summary: $('summary'), summaryScore: $('summary-score'),
      summaryTable: $('summary-table'), btnAgain: $('btn-again'),
      minimap: $('minimap'),
      btnPractice: $('btn-practice'),
      holeSelect: $('hole-select'), holeGrid: $('hole-grid'), btnHsBack: $('btn-hs-back'),
      gameMenu: $('game-menu'), btnResume: $('btn-resume'), btnHoles: $('btn-holes'),
      btnRestart: $('btn-restart'), btnMute: $('btn-mute'),
    };
    this.mapCtx = this.el.minimap.getContext('2d');
    this.toastTimer = null;
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

  setWind(mph, relAngleRad) {
    this.el.windSpeed.textContent = Math.round(mph);
    this.el.windArrow.style.transform = `rotate(${relAngleRad * 180 / Math.PI}deg)`;
    this.el.wind.classList.toggle('calm', mph < 1);
  }

  setClub(name, carryMeters, putter) {
    this.el.clubName.textContent = name;
    this.el.clubCarry.textContent = putter ? 'ON THE DANCE FLOOR' : `${fmtYards(carryMeters)}y CARRY`;
  }

  setPin(meters) {
    if (meters < 23) {
      this.el.pinNum.textContent = Math.round(meters * 3.28084);
      this.el.pinUnit.textContent = 'ft';
    } else {
      this.el.pinNum.textContent = fmtYards(meters);
      this.el.pinUnit.textContent = 'y';
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

  shotDataShow({ speedMph, launchDeg, spinRpm }) {
    this.el.sdSpeed.textContent = `${Math.round(speedMph)} mph`;
    this.el.sdLaunch.textContent = `${launchDeg.toFixed(1)}°`;
    this.el.sdSpin.textContent = `${Math.round(spinRpm / 10) * 10} rpm`;
    this.el.sdApex.textContent = '—';
    this.el.sdCarry.textContent = '—';
    this.el.sdTotal.textContent = '—';
    this.el.shotData.classList.remove('hidden');
  }

  shotDataApex(ft) {
    this.el.sdApex.textContent = `${Math.round(ft)} ft`;
  }

  shotDataResult(carryY, totalY) {
    if (carryY != null) this.el.sdCarry.textContent = `${carryY}y`;
    if (totalY != null) this.el.sdTotal.textContent = `${totalY}y`;
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

  // ---------- hole select / menu ----------

  holeSelectShow(holes, scores, onPick) {
    const grid = this.el.holeGrid;
    grid.innerHTML = '';
    const Y = 1.09361;
    holes.forEach((h, i) => {
      const yds = Math.round(h.path.reduce((acc, p, j) => j
        ? acc + Math.hypot(p.x - h.path[j - 1].x, p.z - h.path[j - 1].z) : 0, 0) * Y);
      const tile = document.createElement('button');
      tile.className = 'hole-tile' + (scores[i] != null ? ' played' : '');
      tile.innerHTML = `<div class="ht-num">${h.id}</div>` +
        `<div class="ht-meta">PAR ${h.par} · ${yds}y</div>` +
        `<div class="ht-name">${h.name}</div>`;
      tile.addEventListener('click', (e) => { e.stopPropagation(); onPick(i); });
      grid.appendChild(tile);
    });
    this.el.holeSelect.classList.remove('hidden');
  }
  holeSelectHide() { this.el.holeSelect.classList.add('hidden'); }

  menuShow(muted) {
    this.el.btnMute.textContent = muted ? 'UNMUTE' : 'MUTE';
    this.el.gameMenu.classList.remove('hidden');
  }
  menuHide() { this.el.gameMenu.classList.add('hidden'); }
  menuVisible() { return !this.el.gameMenu.classList.contains('hidden'); }

  // ---------- minimap ----------

  mapSetHole(hole) {
    this.mapHole = hole;
    const tee = hole.path[0];
    const green = hole.path[hole.path.length - 1];
    const dx = green.x - tee.x, dz = green.z - tee.z;
    const L = Math.hypot(dx, dz) || 1;
    this.mapDir = { x: dx / L, z: dz / L };           // map "up"
    this.mapRight = { x: this.mapDir.z, z: -this.mapDir.x };

    // gather extents in rotated frame
    const pts = [...hole.path];
    for (const b of hole.bunkers) pts.push({ x: b.cx, z: b.cz });
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

  mapDraw(ball, aimDir, pin) {
    if (!this.mapHole) return;
    const ctx = this.mapCtx;
    const hole = this.mapHole;
    const W = this.el.minimap.width, H = this.el.minimap.height;
    const sc = this.mapScale;
    ctx.clearRect(0, 0, W, H);

    // dark-glass backdrop, matching the HUD panels; everything clips to it
    ctx.save();
    ctx.beginPath();
    ctx.roundRect(0, 0, W, H, 9);
    ctx.clip();
    ctx.fillStyle = 'rgba(13, 19, 14, 0.86)';
    ctx.fillRect(0, 0, W, H);

    // rough halo around the corridor, then the fairway itself
    ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    const corridor = () => {
      ctx.beginPath();
      hole.path.forEach((p, i) => {
        const [mx, my] = this.mapPt(p.x, p.z);
        i ? ctx.lineTo(mx, my) : ctx.moveTo(mx, my);
      });
    };
    ctx.strokeStyle = 'rgba(58, 82, 48, 0.55)';
    ctx.lineWidth = hole.fairwayHalf * 3.1 * sc;
    corridor(); ctx.stroke();
    ctx.strokeStyle = '#456F36';
    ctx.lineWidth = hole.fairwayHalf * 2 * sc;
    corridor(); ctx.stroke();

    // water — deep petrol with a bone hairline shore
    ctx.fillStyle = '#1C3B47'; ctx.strokeStyle = '#1C3B47';
    for (const w of hole.water) {
      if (w.type === 'pond') {
        const [mx, my] = this.mapPt(w.cx, w.cz);
        ctx.beginPath();
        ctx.ellipse(mx, my, w.rx * sc, w.rz * sc, 0, 0, Math.PI * 2);
        ctx.fill();
        ctx.strokeStyle = 'rgba(236, 228, 210, 0.16)';
        ctx.lineWidth = 1;
        ctx.stroke();
        ctx.strokeStyle = '#1C3B47';
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

    // green with a fringe ring
    {
      const g = hole.green;
      const [mx, my] = this.mapPt(g.cx, g.cz);
      const r = ((g.rx + g.rz) / 2) * sc;
      ctx.fillStyle = '#5F9549';
      ctx.beginPath();
      ctx.ellipse(mx, my, r, r, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = 'rgba(236, 228, 210, 0.2)';
      ctx.lineWidth = 1;
      ctx.stroke();
    }

    // bunkers
    ctx.fillStyle = '#D5C28C';
    for (const b of hole.bunkers) {
      const [mx, my] = this.mapPt(b.cx, b.cz);
      ctx.beginPath();
      ctx.ellipse(mx, my, ((b.rx + b.rz) / 2) * sc, ((b.rx + b.rz) / 2) * sc, 0, 0, Math.PI * 2);
      ctx.fill();
    }

    // aim line — bone dashes from ball toward target
    if (ball && aimDir) {
      const [bx, by] = this.mapPt(ball.x, ball.z);
      const [ax, ay] = this.mapPt(ball.x + aimDir.x * 400, ball.z + aimDir.z * 400);
      ctx.strokeStyle = 'rgba(236, 228, 210, 0.55)';
      ctx.lineWidth = 1;
      ctx.setLineDash([4, 4]);
      ctx.beginPath(); ctx.moveTo(bx, by); ctx.lineTo(ax, ay); ctx.stroke();
      ctx.setLineDash([]);
    }

    // pin — Marker Gold
    if (pin) {
      const [px, py] = this.mapPt(pin.x, pin.z);
      ctx.fillStyle = '#CBB079';
      ctx.beginPath(); ctx.arc(px, py, 3, 0, Math.PI * 2); ctx.fill();
    }

    // ball — Range Bone
    if (ball) {
      const [bx, by] = this.mapPt(ball.x, ball.z);
      ctx.fillStyle = '#ECE4D2';
      ctx.strokeStyle = 'rgba(0,0,0,0.6)';
      ctx.lineWidth = 1;
      ctx.beginPath(); ctx.arc(bx, by, 3, 0, Math.PI * 2); ctx.fill(); ctx.stroke();
    }

    ctx.restore();
  }
}
