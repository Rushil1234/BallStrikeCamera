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

ARCHIVE = os.environ.get('TC_ARCHIVE') or os.path.expanduser(
    '~/Documents/TrueCarryFramesArchive_20260717/AllFramesArchive')
RESULTS = os.environ.get('TC_RESULTS') or os.path.expanduser(
    '~/Documents/TrueCarryTraining/replays/20260717')
PAIRS = os.environ.get('TC_PAIRS') or os.path.expanduser(
    '~/Documents/TrueCarryTraining/session_2026-07-17/pairs.json')

pairs = {}
if os.path.exists(PAIRS):
    for p in json.load(open(PAIRS)):
        pairs[p['shot']] = p

# full TopTracer rows (spin, push/pull, peak height...) keyed by shot number
TT_CSV = os.environ.get('TC_TT_CSV') or os.path.expanduser(
    '~/Documents/TrueCarryTraining/session_2026-07-17/swingsync-2026-07-17.csv')
tt_full = {}
if os.path.exists(TT_CSV):
    import csv as _csv
    with open(TT_CSV) as _f:
        for _r in _csv.DictReader(_f):
            try:
                _n = int(_r['shotNumber'])
            except (ValueError, KeyError):
                continue
            def _fv(k):
                try:
                    v = float(_r.get(k, ''))
                    return None if v == -10000 else v
                except (TypeError, ValueError):
                    return None
            tt_full[_n] = dict(ball_mph=_fv('ballSpeed'), club_mph=_fv('clubSpeed'),
                               launch=_fv('launchAngle'), carry=_fv('carry'), total=_fv('total'),
                               backspin=_fv('backSpin'), sidespin=_fv('sideSpin'),
                               push_pull=_fv('pushPull'), peak=_fv('peakHeight'),
                               smash=_fv('smashFactor'), descent=_fv('decentAngle'),
                               club=(_r.get('type') or _r.get('clubName') or ''))


def frame_file(shot, fi):
    d = os.path.join(ARCHIVE, shot)
    for pat in (f'frame_{fi:03d}.jpg', f'frame_{fi:03d}.png'):
        p = os.path.join(d, pat)
        if os.path.exists(p):
            return p
    return None


def shot_ids():
    if not os.path.isdir(RESULTS):
        return []
    have_frames = set(os.listdir(ARCHIVE)) if os.path.isdir(ARCHIVE) else set()
    return sorted(f[:-5] for f in os.listdir(RESULTS)
                  if f.endswith('.json') and f[:-5] in have_frames)


def shot_payload(sid):
    d = json.load(open(os.path.join(RESULTS, sid + '.json')))
    nframes = len([f for f in os.listdir(os.path.join(ARCHIVE, sid))
                   if f.startswith('frame_')])
    pr = pairs.get(sid, {})
    tt = dict(pr.get('toptracer') or {})
    num = tt.get('num')
    if num in tt_full:
        merged = dict(tt_full[num]); merged.update({k: v for k, v in tt.items() if v is not None})
        tt = merged
    return {'name': sid, 'replay': d, 'nframes': nframes,
            'toptracer': tt or None, 'garmin': pr.get('garmin')}


def index_rows():
    rows = []
    for sid in shot_ids():
        try:
            d = json.load(open(os.path.join(RESULTS, sid + '.json')))
        except Exception:
            continue
        m = d.get('metrics') or {}
        pr = pairs.get(sid, {})
        ttp = pr.get('toptracer') or {}
        tt = ttp.get('ball_mph')
        gm = (pr.get('garmin') or {}).get('ball_mph')
        bs = m.get('ballSpeedMph')
        err = None
        if bs and tt:
            err = abs(bs - tt) / tt * 100
        elif bs and gm:
            err = abs(bs - gm) / gm * 100
        vla_err = None
        if m.get('vlaDegrees') is not None and ttp.get('launch') is not None:
            vla_err = abs(m['vlaDegrees'] - ttp['launch'])
        carry_err = None
        if m.get('carryYards') and ttp.get('carry'):
            carry_err = abs(m['carryYards'] - ttp['carry'])
        total_err = None
        if m.get('totalYards') and ttp.get('total'):
            total_err = abs(m['totalYards'] - ttp['total'])
        rows.append({'name': sid, 'verdict': d.get('verdict', '?'),
                     'ball': bs, 'tt': tt, 'garmin': gm, 'err': err,
                     'vla_err': vla_err, 'carry_err': carry_err, 'total_err': total_err,
                     'club': tt_full.get(ttp.get('num'), {}).get('club', '')})
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
 <option value="time">time</option><option value="err">speed err</option>
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
  const spd=shots.map(s=>s.err).filter(e=>e!=null);
  const vla=shots.map(s=>s.vla_err).filter(e=>e!=null);
  const cy=shots.map(s=>s.carry_err).filter(e=>e!=null);
  const tot=shots.map(s=>s.total_err).filter(e=>e!=null);
  const f=(v,d)=>v==null?'&mdash;':v.toFixed(d);
  document.getElementById('summary').innerHTML =
    `<b style="color:#ddd">fleet vs TopTracer (${shots.length} shots)</b><br>`+
    `speed <span class="${cls(median(spd))}">${f(median(spd),1)}%</span> <span class="k">(goal &plusmn;2mph)</span> &middot; `+
    `VLA <b>${f(median(vla),1)}&deg;</b> <span class="k">(goal 1&deg;)</span><br>`+
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
    const e = s.err==null?'':` <span class="${cls(s.err)}">${s.err.toFixed(1)}%</span>`;
    const v = s.verdict.startsWith('accepted')?'':' <span class="disc">&#10007;</span>';
    const c = s.club?` <span class="k" style="font-size:10px">${s.club.replace('_',' ').slice(0,10)}</span>`:'';
    return `<div class="shot ${s.name===selName?'sel':''}" id="sh${i}" onclick="load(${i})">${s.name.slice(14)}${v}${e}${c}</div>`;
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
  const smashOurs=(m.ballSpeedMph&&m.clubSpeedMph)?m.ballSpeedMph/m.clubSpeedMph:null;
  document.getElementById('metrics').innerHTML =
    '<tr><th>stat</th><th>TrueCarry</th><th>TopTracer</th><th>Garmin</th><th>vs TT</th><th>vs Garmin</th></tr>'+
    row('ball speed mph', m.ballSpeedMph, tt.ball_mph, gm.ball_mph)+
    (adv?row('&nbsp; v3 head (advisory)', +adv[1], tt.ball_mph, gm.ball_mph):'')+
    row('VLA &deg;', m.vlaDegrees, tt.launch, gm.launch)+
    row('HLA / push-pull &deg;', null, tt.push_pull, gm.launch_dir)+
    row('carry yd', m.carryYards, tt.carry, gm.carry)+
    row('total yd', m.totalYards, tt.total, gm.total)+
    row('club speed mph', m.clubSpeedMph, tt.club_mph, gm.club_mph)+
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
    print(f'archive: {ARCHIVE}\nresults: {RESULTS}\npairs:   {PAIRS} ({len(pairs)} paired)')
    print(f'http://localhost:{args.port}')
    ThreadingHTTPServer(('127.0.0.1', args.port), H).serve_forever()


if __name__ == '__main__':
    main()
