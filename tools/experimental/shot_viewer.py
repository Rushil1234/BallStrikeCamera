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
    return {'name': sid, 'replay': d, 'nframes': nframes,
            'toptracer': pr.get('toptracer'), 'garmin': pr.get('garmin')}


def index_rows():
    rows = []
    for sid in shot_ids():
        try:
            d = json.load(open(os.path.join(RESULTS, sid + '.json')))
        except Exception:
            continue
        m = d.get('metrics') or {}
        pr = pairs.get(sid, {})
        tt = (pr.get('toptracer') or {}).get('ball_mph')
        gm = (pr.get('garmin') or {}).get('ball_mph')
        bs = m.get('ballSpeedMph')
        err = None
        if bs and tt:
            err = abs(bs - tt) / tt * 100
        elif bs and gm:
            err = abs(bs - gm) / gm * 100
        rows.append({'name': sid, 'verdict': d.get('verdict', '?'),
                     'ball': bs, 'tt': tt, 'garmin': gm, 'err': err})
    return rows


PAGE = r"""<!doctype html><html><head><meta charset="utf-8"><title>TrueCarry Shot Viewer</title>
<style>
 body{margin:0;background:#101312;color:#ddd;font:13px Menlo,monospace;display:flex;height:100vh}
 #list{width:300px;overflow-y:auto;border-right:1px solid #2a2f2d;padding:6px}
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
<div id="list"></div>
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
fetch('/shots').then(r=>r.json()).then(d=>{
  shots=d;
  const el=document.getElementById('list');
  el.innerHTML = d.map((s,i)=>{
    const e = s.err==null?'':` <span class="${cls(s.err)}">${s.err.toFixed(1)}%</span>`;
    const v = s.verdict.startsWith('accepted')?'':' <span class="disc">&#10007;</span>';
    return `<div class="shot" id="sh${i}" onclick="load(${i})">${s.name.slice(14)}${v}${e}</div>`;
  }).join('');
  if(d.length) load(0);
});

function load(i){
  if(sel>=0) document.getElementById('sh'+sel).classList.remove('sel');
  sel=i; document.getElementById('sh'+i).classList.add('sel');
  document.getElementById('sh'+i).scrollIntoView({block:'nearest'});
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
  document.getElementById('metrics').innerHTML =
    '<tr><th>stat</th><th>TrueCarry</th><th>TopTracer</th><th>Garmin</th><th>vs TT</th><th>vs Garmin</th></tr>'+
    row('ball speed mph', m.ballSpeedMph, tt.ball_mph, gm.ball_mph)+
    row('VLA &deg;', m.vlaDegrees, tt.launch, gm.launch)+
    row('carry yd', m.carryYards, tt.carry, gm.carry)+
    row('total yd', m.totalYards, tt.total, gm.total)+
    row('club speed mph', m.clubSpeedMph, tt.club_mph, gm.club_mph)+
    row('backspin rpm', null, tt.backspin, gm.backspin)+
    row('smash', null, tt.smash, gm.smash);
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
