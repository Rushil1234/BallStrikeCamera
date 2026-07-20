#!/usr/bin/env python3
"""Shot viewer — browser review of tracked shots vs TopTracer/Garmin truth.

Read-only sibling of label_server.py: serves archived frames with the live
pipeline's replay overlays (ball track, club points, lock, impact) and a
side-by-side metrics table — TrueCarry vs TopTracer vs Garmin with error %.
TopTracer is the primary truth column for ball stats (Noah, July 17).

Run:  python3 tools/experimental/shot_viewer.py [--port 8766]
Env:  TC_ARCHIVE   frames archive (default July-17 keepers)
      TC_RESULTS   dir of ReplayResults <shot>.json copies
      TC_PAIRS     pairs.json with garmin/toptracer blocks
Then open http://localhost:8766
"""
import argparse, json, os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TRAIN = os.path.expanduser('~/Documents/TrueCarryTraining')
ARCHIVES = [os.environ['TC_ARCHIVE']] if os.environ.get('TC_ARCHIVE') else [
    os.path.expanduser(a) for a in (
        '~/Documents/TrueCarryFramesArchive_20260717/AllFramesArchive',
        '~/Documents/TrueCarryFramesArchive_20260716/AllFramesArchive',
        '~/Documents/TrueCarryFramesArchive_20260712/AllFramesArchive')]
RESULTS = os.environ.get('TC_RESULTS') or os.path.join(TRAIN, 'replays/latest')


def _fnum(v):
    try:
        f = float(v)
        return None if f == -10000 else f
    except (TypeError, ValueError):
        return None


def _load_truth():
    """shot -> {'toptracer': {...}|None, 'garmin': {...}|None} across all sessions."""
    import csv as _csv
    out = {}
    # jul17: nested pairs, enriched from its swingsync CSV
    p17 = os.path.join(TRAIN, 'session_2026-07-17/pairs.json')
    ss17 = {}
    c17 = os.path.join(TRAIN, 'session_2026-07-17/swingsync-2026-07-17.csv')
    if not os.path.exists(c17):
        c17 = os.path.expanduser('~/Downloads/swingsync-2026-07-17.csv')
    if os.path.exists(c17):
        with open(c17) as f:
            for r in _csv.DictReader(f):
                try:
                    n = int(r['shotNumber'])
                except (ValueError, KeyError):
                    continue
                ss17[n] = dict(ball_mph=_fnum(r.get('ballSpeed')), club_mph=_fnum(r.get('clubSpeed')),
                               launch=_fnum(r.get('launchAngle')), carry=_fnum(r.get('carry')),
                               total=_fnum(r.get('total')), backspin=_fnum(r.get('backSpin')),
                               sidespin=_fnum(r.get('sideSpin')), push_pull=_fnum(r.get('pushPull')),
                               peak=_fnum(r.get('peakHeight')), smash=_fnum(r.get('smashFactor')),
                               descent=_fnum(r.get('decentAngle')),
                               club=(r.get('type') or r.get('clubName') or ''))
    if os.path.exists(p17):
        for p in json.load(open(p17)):
            tt = dict(p.get('toptracer') or {})
            num = tt.get('num')
            if num in ss17:
                merged = dict(ss17[num])
                merged.update({k: v for k, v in tt.items() if v is not None})
                tt = merged
            out[p['shot']] = {'toptracer': tt or None, 'garmin': p.get('garmin')}
    # jul16: flat pairs -> nested via its swingsync CSV (tt_shot == shotNumber)
    p16 = os.path.join(TRAIN, 'session_2026-07-16/pairs.json')
    ss16 = {}
    c16 = os.path.expanduser('~/Downloads/swingsync-2026-07-16.csv')
    if os.path.exists(c16):
        with open(c16) as f:
            for r in _csv.DictReader(f):
                try:
                    n = int(r['shotNumber'])
                except (ValueError, KeyError):
                    continue
                ss16[n] = dict(ball_mph=_fnum(r.get('ballSpeed')), club_mph=_fnum(r.get('clubSpeed')),
                               launch=_fnum(r.get('launchAngle')), carry=_fnum(r.get('carry')),
                               total=_fnum(r.get('total')), backspin=_fnum(r.get('backSpin')),
                               sidespin=_fnum(r.get('sideSpin')), push_pull=_fnum(r.get('pushPull')),
                               peak=_fnum(r.get('peakHeight')), smash=_fnum(r.get('smashFactor')),
                               descent=_fnum(r.get('decentAngle')),
                               club=(r.get('type') or r.get('clubName') or ''))
    if os.path.exists(p16):
        for p in json.load(open(p16)):
            tt = dict(ss16.get(p.get('tt_shot')) or {})
            if not tt:
                tt = dict(ball_mph=p.get('tt_ball_mph'), launch=p.get('launch_deg'),
                          carry=p.get('carry_yd'), total=p.get('total_yd'),
                          backspin=p.get('backspin'), club=p.get('club') or '')
            tt['num'] = p.get('tt_shot')
            out[p['shot']] = {'toptracer': tt, 'garmin': None}
    # jul12 whites: Garmin only. garmin_idx indexes the DATE-FILTERED rows of
    # garmin_small.csv THEN garmin_main.csv concatenated (verified 103/103 on
    # ball speed; the CSVs carry a units row that must be skipped, and indexing
    # main-only silently shifts every row by 9 — that bug shipped in
    # train_white_heads.py's launch truth).
    p12 = os.path.join(TRAIN, 'session_2026-07-12/pairs.json')
    g12 = []
    for name in ('garmin_small.csv', 'garmin_main.csv'):
        c12 = os.path.join(TRAIN, 'session_2026-07-12', name)
        if not os.path.exists(c12):
            continue
        with open(c12) as f:
            for r in _csv.DictReader(f):
                date = r.get('﻿Date') or r.get('Date')
                if not date or '/' not in date:
                    continue          # units row / junk
                g12.append(dict(ball_mph=_fnum(r.get('Ball Speed')), club_mph=_fnum(r.get('Club Speed')),
                                launch=_fnum(r.get('Launch Angle')), launch_dir=_fnum(r.get('Launch Direction')),
                                backspin=_fnum(r.get('Backspin')), spin=_fnum(r.get('Spin Rate')),
                                carry=_fnum(r.get('Carry Distance')), total=_fnum(r.get('Total Distance')),
                                smash=_fnum(r.get('Smash Factor')), club=(r.get('Club Type') or '')))
    if os.path.exists(p12):
        for p in json.load(open(p12)):
            gi = p.get('garmin_idx')
            gm = g12[gi] if gi is not None and gi < len(g12) else {'ball_mph': p.get('garmin_ball_mph')}
            out[p['shot']] = {'toptracer': None, 'garmin': gm}
    return out


truth = _load_truth()


def frame_file(shot, fi):
    for a in ARCHIVES:
        for pat in (f'frame_{fi:03d}.jpg', f'frame_{fi:03d}.png'):
            p = os.path.join(a, shot, pat)
            if os.path.exists(p):
                return p
    return None


def shot_dir(shot):
    for a in ARCHIVES:
        d = os.path.join(a, shot)
        if os.path.isdir(d):
            return d
    return None


def shot_ids():
    if not os.path.isdir(RESULTS):
        return []
    return sorted(f[:-5] for f in os.listdir(RESULTS)
                  if f.endswith('.json') and shot_dir(f[:-5]))


# Garmin -> TT cross-calibration (fit on 54 dual-paired swings, July 18):
# projects TT-scale metrics for Garmin-only shots. View-only — error columns
# and avg-err keep judging Garmin shots against real Garmin numbers.
G2TT_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'garmin_to_tt.json')
g2tt = json.load(open(G2TT_PATH)) if os.path.exists(G2TT_PATH) else {}


def project_tt(gm):
    def m(name, v):
        c = g2tt.get(name)
        return c['a'] * v + c['b'] if c and v is not None else None
    out = {'ball_mph': m('speed', gm.get('ball_mph')),
           'launch': m('launch', gm.get('launch')),
           'club_mph': m('club_speed', gm.get('club_mph')),
           'backspin': m('backspin', gm.get('backspin')),
           'projected': True}
    return out if any(v is not None for k, v in out.items() if k != 'projected') else None


def shot_payload(sid):
    d = json.load(open(os.path.join(RESULTS, sid + '.json')))
    sd = shot_dir(sid)
    nframes = len([f for f in os.listdir(sd) if f.startswith('frame_')]) if sd else 0
    t = truth.get(sid) or {}
    tt = t.get('toptracer')
    if not tt and t.get('garmin'):
        tt = project_tt(t['garmin'])
    return {'name': sid, 'replay': d, 'nframes': nframes,
            'toptracer': tt, 'garmin': t.get('garmin')}


def shot_errors(m, t):
    """Per-metric errors vs the primary truth (TT if present, else Garmin) plus a
    per-shot average of the percent metrics — Noah's 'how far off is this shot on
    average'. VLA stays in degrees (percent of a small angle explodes)."""
    tt = t.get('toptracer') or {}
    gm = t.get('garmin') or {}
    ref = tt if tt.get('ball_mph') else gm
    def pct(ours, th):
        if ours is None or not th:
            return None
        return abs(ours - th) / abs(th) * 100
    errs = {
        'err': pct(m.get('ballSpeedMph'), ref.get('ball_mph')),
        'club_err': pct(m.get('clubSpeedMph'), ref.get('club_mph')),
        'carry_err_pct': pct(m.get('carryYards'), ref.get('carry')),
        'total_err_pct': pct(m.get('totalYards'), ref.get('total')),
    }
    errs['vla_err'] = (abs(m['vlaDegrees'] - ref['launch'])
                       if m.get('vlaDegrees') is not None and ref.get('launch') is not None
                       else None)
    errs['carry_err'] = (abs(m['carryYards'] - ref['carry'])
                         if m.get('carryYards') and ref.get('carry') else None)
    errs['total_err'] = (abs(m['totalYards'] - ref['total'])
                         if m.get('totalYards') and ref.get('total') else None)
    pcts = [v for k, v in errs.items()
            if k in ('err', 'club_err', 'carry_err_pct', 'total_err_pct') and v is not None]
    errs['avg_err'] = sum(pcts) / len(pcts) if pcts else None
    errs['n_metrics'] = len(pcts)
    return errs


def index_rows():
    rows = []
    for sid in shot_ids():
        try:
            d = json.load(open(os.path.join(RESULTS, sid + '.json')))
        except Exception:
            continue
        m = d.get('metrics') or {}
        t = truth.get(sid) or {}
        tt = t.get('toptracer') or {}
        gm = t.get('garmin') or {}
        e = shot_errors(m, t)
        rows.append({'name': sid, 'verdict': d.get('verdict', '?'),
                     'ball': m.get('ballSpeedMph'),
                     'tt': tt.get('ball_mph'), 'garmin': gm.get('ball_mph'),
                     'truth': 'TT' if tt.get('ball_mph') else ('G' if gm.get('ball_mph') else ''),
                     'club': (tt.get('club') or gm.get('club') or ''), **e})
    return rows


PAGE = r"""<!doctype html><html><head><meta charset="utf-8"><title>TrueCarry Shot Viewer</title>
<style>
 body{margin:0;background:#101312;color:#ddd;font:13px Menlo,monospace;display:flex;height:100vh}
 #list{}
 .shot{padding:5px 7px;border-radius:6px;cursor:pointer;white-space:nowrap}
 .shot:hover{background:#1c211f}.shot.sel{background:#24302a}
 .err-good{color:#6fdd8b}.err-mid{color:#e8c268}.err-bad{color:#e87a68}.disc{color:#777}
 #main{flex:1;display:flex;flex-direction:column;padding:10px;overflow:auto}
 #cv{background:#000;border-radius:8px;align-self:flex-start}
 #bar{margin:8px 0;display:flex;gap:10px;align-items:center}
 button{background:#232826;color:#ddd;border:1px solid #333;border-radius:6px;padding:4px 10px;cursor:pointer}
 #metrics{border-collapse:collapse;margin-top:8px}
 #metrics td,#metrics th{border:1px solid #2a2f2d;padding:4px 10px;text-align:right}
 #metrics th{color:#9ab;text-align:center}
 #status{color:#9ab;margin-top:6px;min-height:16px}
 .k{color:#789}
</style></head><body>
<div id="side" style="display:flex;flex-direction:column;width:320px;border-right:1px solid #2a2f2d">
<div id="summary" style="padding:8px;border-bottom:1px solid #2a2f2d;font-size:12px;color:#9ab"></div>
<div style="padding:4px 8px;border-bottom:1px solid #2a2f2d">
 sort: <select id="sortsel" onchange="renderList()" style="background:#232826;color:#ddd;border:1px solid #333">
 <option value="time">time</option><option value="avg_err">avg err</option>
 <option value="err">speed err</option><option value="club_err">club err</option>
 <option value="vla_err">VLA err</option><option value="carry_err">carry err</option></select>
</div>
<div id="list" style="flex:1;overflow-y:auto;padding:6px"></div>
</div>
<div id="main">
  <canvas id="cv" width="1080" height="609"></canvas>
  <div id="bar">
    <button onclick="step(-1)">&#9664;</button>
    <button id="play" onclick="togglePlay()">&#9654; play</button>
    <button onclick="step(1)">&#9654;</button>
    <input type="range" id="slider" min="0" max="40" value="0" style="flex:1"
      oninput="fi=+this.value;render()">
    <span id="fl"></span>
  </div>
  <div id="status"></div>
  <table id="metrics"></table>
  <div style="margin-top:8px;color:#678">keys: &#8592;/&#8594; frame &middot; [ / ] shot &middot; space play &middot; overlays always on &middot; TT = primary ball truth</div>
</div>
<script>
let shots=[], sel=-1, cur=null, fi=0, playing=false, imgs={};
const cv=document.getElementById('cv'), ctx=cv.getContext('2d');
const S=3;   // 360x203 -> 1080x609

function cls(e){ if(e==null) return ''; return e<=2?'err-good':(e<=5?'err-mid':'err-bad'); }
function median(a){ if(!a.length) return null; const b=[...a].sort((x,y)=>x-y); return b[Math.floor(b.length/2)]; }
function summary(){
  const pick=k=>shots.map(s=>s[k]).filter(e=>e!=null);
  const spd=pick('err'), club=pick('club_err'), vla=pick('vla_err');
  const cy=pick('carry_err'), tot=pick('total_err'), avg=pick('avg_err');
  const f=(v,d)=>v==null?'&mdash;':v.toFixed(d);
  const nTT=shots.filter(s=>s.truth==='TT').length, nG=shots.filter(s=>s.truth==='G').length;
  document.getElementById('summary').innerHTML =
    `<b style="color:#ddd">fleet (${shots.length} shots: ${nTT} vs TT, ${nG} vs Garmin)</b><br>`+
    `<b>avg-of-metrics <span class="${cls(median(avg))}">${f(median(avg),1)}%</span></b> <span class="k">median shot</span><br>`+
    `speed <span class="${cls(median(spd))}">${f(median(spd),1)}%</span> <span class="k">(goal &plusmn;2mph)</span> &middot; `+
    `club <span class="${cls(median(club))}">${f(median(club),1)}%</span> <span class="k">(hosel)</span><br>`+
    `VLA <b>${f(median(vla),1)}&deg;</b> <span class="k">(goal 1&deg;)</span> &middot; `+
    `carry <b>${f(median(cy),1)}yd</b> <span class="k">(goal 3)</span> &middot; `+
    `total <b>${f(median(tot),1)}yd</b> <span class="k">(goal 5)</span>`;
}
function renderList(){
  const mode=document.getElementById('sortsel').value;
  const order=shots.map((s,i)=>i);
  if(mode!=='time') order.sort((a,b)=>(shots[b][mode]??-1)-(shots[a][mode]??-1));
  const selName = sel>=0? shots[sel].name : null;
  document.getElementById('list').innerHTML = order.map(i=>{
    const s=shots[i];
    const a = s.avg_err==null?'':` <span class="${cls(s.avg_err)}">avg ${s.avg_err.toFixed(1)}%</span>`;
    const v = s.verdict.startsWith('accepted')?'':' <span class="disc">&#10007;</span>';
    const t = s.truth==='G'?' <span class="k" style="font-size:10px">G</span>':'';
    const c = s.club?` <span class="k" style="font-size:10px">${s.club.replace('_',' ').slice(0,10)}</span>`:'';
    return `<div class="shot ${s.name===selName?'sel':''}" id="sh${i}" onclick="load(${i})">${s.name.slice(5,13)}·${s.name.slice(14)}${v}${a}${t}${c}</div>`;
  }).join('');
}
fetch('/shots').then(r=>r.json()).then(d=>{
  shots=d; summary(); renderList();
  if(d.length) load(0);
});

function load(i){
  sel=i; renderList();
  const el=document.getElementById('sh'+i);
  if(el) el.scrollIntoView({block:'nearest'});
  fetch('/shot/'+shots[i].name).then(r=>r.json()).then(d=>{
    cur=d; imgs={};
    fi=Math.max(0, d.replay.impactDetected||0);
    document.getElementById('slider').max=d.nframes-1;
    metricsTable();
    render();
  });
}
function img(k){
  if(!imgs[k]){ imgs[k]=new Image(); imgs[k].onload=()=>{ if(k===fi) render(); };
    imgs[k].src='/img/'+cur.name+'/'+k; }
  return imgs[k];
}
function render(){
  if(!cur) return;
  document.getElementById('slider').value=fi;
  const d=cur.replay, im=img(fi);
  ctx.fillStyle='#000'; ctx.fillRect(0,0,cv.width,cv.height);
  if(im.complete) ctx.drawImage(im,0,0,cv.width,cv.height);
  const W=cv.width,H=cv.height, impact=d.impactDetected||0;
  const px=(nx,ny)=>[nx*W,ny*H];
  function rect(r,color,label){ if(!r||r.x==null) return;
    ctx.strokeStyle=color; ctx.setLineDash([6,4]); ctx.lineWidth=2;
    ctx.strokeRect(r.x*W,r.y*H,r.w*W,r.h*H); ctx.setLineDash([]);
    if(label){ctx.fillStyle=color;ctx.font='12px Menlo';ctx.fillText(label,r.x*W+3,r.y*H-4);} }
  rect(d.lockedBallRect,'#ffffff','lock');
  const fr={}; (d.frames||[]).forEach(f=>fr[f.i]=f);
  const cl={}; (d.club||[]).forEach(c=>cl[c.i]=c);
  // ball trajectory
  const pts=Object.values(fr).filter(f=>f.cx!=null).sort((a,b)=>a.i-b.i);
  ctx.lineWidth=2;
  for(let k=1;k<pts.length;k++){
    if(pts[k].i<=impact) continue;
    const[x0,y0]=px(pts[k-1].cx,pts[k-1].cy),[x1,y1]=px(pts[k].cx,pts[k].cy);
    ctx.strokeStyle='#00ddff'; ctx.beginPath();ctx.moveTo(x0,y0);ctx.lineTo(x1,y1);ctx.stroke();
  }
  pts.forEach(f=>{
    const[x,y]=px(f.cx,f.cy); const r=Math.max(4,(f.d||0.02)*W/2);
    if(f.i===fi){ ctx.strokeStyle='#33ff66';ctx.lineWidth=3;
      ctx.beginPath();ctx.arc(x,y,r,0,7);ctx.stroke();
      ctx.fillStyle='#33ff66';ctx.font='bold 13px Menlo';
      ctx.fillText('f'+f.i+' conf='+(f.conf||0).toFixed(2),x+r+4,y-r-4);
    } else if(f.i<=impact){ ctx.strokeStyle='#888';ctx.lineWidth=1;
      ctx.beginPath();ctx.arc(x,y,4,0,7);ctx.stroke();
    } else { ctx.fillStyle=f.i<fi?'#00ddff':'#005566';
      ctx.beginPath();ctx.arc(x,y,5,0,7);ctx.fill(); }
  });
  // club: past points dim, current bright
  Object.values(cl).forEach(c=>{
    if(c.cx==null) return;
    const[x,y]=px(c.cx,c.cy);
    ctx.strokeStyle=c.i===fi?'#ff8800':'#7a4400'; ctx.lineWidth=c.i===fi?3:1;
    ctx.beginPath();ctx.moveTo(x-8,y);ctx.lineTo(x+8,y);ctx.moveTo(x,y-8);ctx.lineTo(x,y+8);ctx.stroke();
  });
  const f=fr[fi]||{};
  const phase=fi<impact?'PRE':(fi===impact?'IMPACT':'POST');
  document.getElementById('fl').textContent='f'+fi+'/'+(cur.nframes-1);
  document.getElementById('status').innerHTML =
    `<b>${cur.name}</b> &middot; ${phase} &middot; impact f${impact} `+
    `<span class="k">(${d.impactReason||'?'})</span> &middot; ball: ${f.reason||'&mdash;'}`+
    (cl[fi]?` &middot; club: ${cl[fi].mode||'?'} conf=${(cl[fi].conf||0).toFixed(2)}`:'')+
    ` &middot; <span class="k">${d.verdict||''}</span>`;
}
function row(label,ours,tt,gm,fmt){
  const F=v=>v==null?'&mdash;':(typeof v==='number'?v.toFixed(1):v)+(fmt||'');
  let e1=null,e2=null;
  if(typeof ours==='number'&&typeof tt==='number'&&tt) e1=Math.abs(ours-tt)/Math.abs(tt)*100;
  if(typeof ours==='number'&&typeof gm==='number'&&gm) e2=Math.abs(ours-gm)/Math.abs(gm)*100;
  const E=e=>e==null?'&mdash;':`<span class="${cls(e)}">${e.toFixed(1)}%</span>`;
  return `<tr><td style="text-align:left;color:#9ab">${label}</td><td><b>${F(ours)}</b></td><td>${F(tt)}</td><td>${F(gm)}</td><td>${E(e1)}</td><td>${E(e2)}</td></tr>`;
}
function metricsTable(){
  const m=cur.replay.metrics||{}, tt=cur.toptracer||{}, gm=cur.garmin||{};
  const notes=(cur.replay.v2Notes||[]).join(' | ');
  const adv=notes.match(/v3heads: speed ([\d.]+)/);
  const hosel=notes.match(/hosel: club ([\d.]+) mph \((\d+) ivals/);
  const smashOurs=(m.ballSpeedMph&&m.clubSpeedMph)?m.ballSpeedMph/m.clubSpeedMph:null;
  // per-shot avg of % errors vs the primary truth (TT, else Garmin) — same math
  // as the server's list rows: ball, club, carry, total
  // projected TT is a viewing tool — real Garmin stays the error reference
  const ref = (tt.ball_mph!=null && !tt.projected)?tt:gm;
  const refName = (tt.ball_mph!=null && !tt.projected)?'TT':'Garmin';
  const pcts=[['ball spd',m.ballSpeedMph,ref.ball_mph],['club spd',m.clubSpeedMph,ref.club_mph],
              ['carry',m.carryYards,ref.carry],['total',m.totalYards,ref.total]]
    .map(([n,o,t])=>(o!=null&&t)?[n,Math.abs(o-t)/Math.abs(t)*100]:null).filter(x=>x);
  const avg=pcts.length?pcts.reduce((a,x)=>a+x[1],0)/pcts.length:null;
  const vlaD=(m.vlaDegrees!=null&&ref.launch!=null)?Math.abs(m.vlaDegrees-ref.launch):null;
  const avgLine = avg==null?'':
    `<tr><td style="text-align:left;color:#ddd"><b>SHOT AVG ERROR</b></td>`+
    `<td colspan=5 style="text-align:left"><b><span class="${cls(avg)}">${avg.toFixed(1)}%</span></b>`+
    ` <span class="k">vs ${refName} &middot; mean of ${pcts.map(x=>x[0]+' '+x[1].toFixed(1)+'%').join(', ')}`+
    `${vlaD!=null?' &middot; VLA off '+vlaD.toFixed(1)+'&deg;':''}</span></td></tr>`;
  const ttHdr = tt.projected?'TopTracer <span style="color:#e8c268">(proj)</span>':'TopTracer';
  const ttEHdr = tt.projected?'vs TT(proj)':'vs TT';
  document.getElementById('metrics').innerHTML =
    `<tr><th>stat</th><th>TrueCarry</th><th>${ttHdr}</th><th>Garmin</th><th>${ttEHdr}</th><th>vs Garmin</th></tr>`+
    avgLine+
    row('ball speed mph', m.ballSpeedMph, tt.ball_mph, gm.ball_mph)+
    (adv?row('&nbsp; v3 head (advisory)', +adv[1], tt.ball_mph, gm.ball_mph):'')+
    row('VLA &deg;', m.vlaDegrees, tt.launch, gm.launch)+
    row('HLA / push-pull &deg;', m.hlaDisplay, tt.push_pull, gm.launch_dir)+
    row('carry yd', m.carryYards, tt.carry, gm.carry)+
    row('total yd', m.totalYards, tt.total, gm.total)+
    row('club speed mph', m.clubSpeedMph, tt.club_mph, gm.club_mph)+
    (hosel?`<tr><td style="text-align:left;color:#9ab">&nbsp; hosel detail</td><td colspan=5 style="text-align:left;color:#8a9;font-size:11px">${hosel[1]} mph from ${hosel[2]} interval(s) &middot; primary source when present</td></tr>`:'')+
    row('smash', smashOurs, tt.smash, gm.smash)+
    row('backspin rpm', null, tt.backspin, gm.backspin)+
    row('sidespin rpm', null, tt.sidespin, gm.spin&&gm.backspin?null:null)+
    row('peak height yd', null, tt.peak, null)+
    row('descent &deg;', null, tt.descent, null)+
    `<tr><td style="text-align:left;color:#9ab">meta</td><td colspan=5 style="text-align:left;color:#8a9;font-size:11px">`+
    `impact f${cur.replay.impactDetected} &middot; ball pts ${m.ballPoints??'?'} &middot; `+
    `${(cur.replay.impactReason||'').slice(0,44)} &middot; TT club: ${tt.club||'?'} #${tt.num??'?'}</td></tr>`;
}
function step(dz){ if(!cur) return; fi=Math.max(0,Math.min(cur.nframes-1,fi+dz)); render(); }
function togglePlay(){ playing=!playing;
  document.getElementById('play').textContent=playing?'⏸ pause':'▶ play';
  if(playing) tick(); }
function tick(){ if(!playing) return; fi=(fi+1)%cur.nframes; render(); setTimeout(tick,100); }
document.addEventListener('keydown',e=>{
  if(e.key==='ArrowLeft'){step(-1);e.preventDefault();}
  else if(e.key==='ArrowRight'){step(1);e.preventDefault();}
  else if(e.key===' '){togglePlay();e.preventDefault();}
  else if(e.key==='['){load((sel-1+shots.length)%shots.length);}
  else if(e.key===']'){load((sel+1)%shots.length);}
});
</script></body></html>"""


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _json(self, obj):
        data = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path in ('/', '/index.html'):
            data = PAGE.encode()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        elif self.path == '/shots':
            self._json(index_rows())
        elif self.path.startswith('/shot/'):
            self._json(shot_payload(self.path.split('/')[2]))
        elif self.path.startswith('/img/'):
            _, _, shot, fi = self.path.split('/')
            p = frame_file(shot, int(fi))
            if not p:
                self.send_response(404)
                self.end_headers()
                return
            data = open(p, 'rb').read()
            self.send_response(200)
            self.send_header('Content-Type', 'image/jpeg')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        else:
            self.send_response(404)
            self.end_headers()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', type=int, default=8766)
    args = ap.parse_args()
    print(f'archives: {len(ARCHIVES)}\nresults: {RESULTS}\ntruth: {len(truth)} shots paired')
    print(f'http://localhost:{args.port}')
    ThreadingHTTPServer(('127.0.0.1', args.port), H).serve_forever()


if __name__ == '__main__':
    main()
