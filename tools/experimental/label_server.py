#!/usr/bin/env python3
"""Ball/club labeling tool — local web app.

Serves every archived shot (past 2 weeks, same content as the Drive zips) with
the golf-context tracker's detections pre-drawn as overlays on the ORIGINAL
frames (no channel view, no brightening — pixels straight off disk). You
correct what's wrong; everything autosaves to labels.json.

Per-frame actions (buttons + keys):
  Ball gone   (G)  — tracker drew a ball where there isn't one
  No club     (X)  — tracker marked a club that isn't there
  Place ball  (B)  — then click the ball's center; scroll wheel resizes circle
  Place club  (C)  — then click the CLUBHEAD CENTER (stored as a point, no circle)
  Place hosel (H)  — then click the shaft-head junction (gold diamond)
  No hosel    (N)  — clear the hosel on this frame (kills a wrong prelabel)
  Approve     (A / Enter) — frame is correct as shown
  Approve shot (S) — every frame in the shot is correct as shown
  ←/→ frames · [ / ] shots

Run:  python3 tools/experimental/label_server.py [--port 8765]
Then open http://localhost:8765
"""
import argparse, json, os, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hsv_object_explorer import frame_path
from extract_tracks import track_shot, ARCHIVE  # noqa: E402

LABELS_DIR = os.path.expanduser('~/Documents/TrueCarryTraining/labels')
LABELS_PATH = os.path.join(LABELS_DIR, 'labels.json')
PRELABELS_PATH = os.path.join(LABELS_DIR, 'prelabels.json')

os.makedirs(LABELS_DIR, exist_ok=True)
_lock = threading.Lock()
labels = json.load(open(LABELS_PATH)) if os.path.exists(LABELS_PATH) else {}
prelabels = json.load(open(PRELABELS_PATH)) if os.path.exists(PRELABELS_PATH) else {}


def save_labels():
    with _lock:
        tmp = LABELS_PATH + '.tmp'
        json.dump(labels, open(tmp, 'w'))
        os.replace(tmp, LABELS_PATH)


def save_prelabels():
    with _lock:
        tmp = PRELABELS_PATH + '.tmp'
        json.dump(prelabels, open(tmp, 'w'))
        os.replace(tmp, PRELABELS_PATH)


def all_shots():
    return sorted(d for d in os.listdir(ARCHIVE)
                  if d.startswith('shot_') and os.path.isdir(os.path.join(ARCHIVE, d)))


def get_prelabel(shot):
    if shot in prelabels:
        return prelabels[shot]
    tr = track_shot(shot, 20)
    if tr is None:
        return None
    imp = tr['impact']
    ball_by_f = {p['fi']: {'cx': p['cx'], 'cy': p['cy'], 'r': p['r']} for p in tr['ball']}
    # Club prelabels only through the first ball-movement frame (impact+1): the
    # follow-through is irrelevant to club speed/path and was cluttering review.
    club_by_f = {p['fi']: {'cx': p['cx'], 'cy': p['cy']} for p in tr['club'] if p['fi'] <= imp + 1}
    frames = []
    for fi in range(max(0, imp - 5), imp + 11):
        if os.path.exists(frame_path(os.path.join(ARCHIVE, shot), fi)):
            frames.append(fi)
    # pre-impact rest-ball prelabel: ball sits at the lock in frames <= impact
    lock = tr['lock']
    rest = {'cx': lock[0], 'cy': lock[1], 'r': tr['ball_r_lock']}
    entry = {
        'impact': imp, 'frames': frames, 'W': tr['W'], 'H': tr['H'],
        'per_frame': {str(fi): {
            'ball': ball_by_f.get(fi, rest if fi <= imp else None),
            'club': club_by_f.get(fi)} for fi in frames},
    }
    prelabels[shot] = entry
    save_prelabels()
    return entry


HTML = """<!doctype html><html><head><meta charset="utf-8"><title>TrueCarry Labeler</title>
<style>
body { background:#101316; color:#e8ebee; font:14px/1.4 -apple-system,sans-serif; margin:0; }
#top { padding:8px 14px 10px; background:#181d22; border-bottom:1px solid #2a3138; }
#row1 { display:flex; gap:14px; align-items:baseline; height:24px; overflow:hidden; }
#row1 b { font-family:Menlo,monospace; white-space:nowrap; }
#row2 { display:flex; gap:10px; align-items:center; margin-top:8px; flex-wrap:nowrap; }
#shotprog { font-family:Menlo,monospace; color:#e0c93f; white-space:nowrap; }
button { background:#232a31; color:#e8ebee; border:1px solid #39424b; border-radius:6px; padding:7px 12px; cursor:pointer; font-size:13px; }
button:hover { background:#2d353d; }
button.mode { border-color:#e0c93f; color:#e0c93f; }
button.danger { border-color:#a04038; }
button.ok { border-color:#3f8f5f; color:#7fdF9f; }
#wrap { display:flex; gap:12px; padding:12px; }
#canvasbox { position:relative; }
canvas { display:block; border:1px solid #2a3138; border-radius:6px; cursor:crosshair; }
#side { min-width:230px; }
.fstrip { display:flex; flex-wrap:wrap; gap:4px; margin-top:8px; }
.fchip { padding:3px 8px; border-radius:4px; background:#232a31; cursor:pointer; font-family:Menlo,monospace; font-size:12px; border:1px solid transparent; }
.fchip.cur { border-color:#e0c93f; }
.fchip.rev { background:#1d3325; }
.fchip .hd { color:#e8c268; margin-left:3px; }
#status { color:#98a2ab; font-size:12px; margin-top:8px; max-width:230px; }
#shotsel { width:220px; }
kbd { background:#232a31; border:1px solid #39424b; border-radius:3px; padding:0 5px; font-size:11px; }
</style></head><body>
<div id="top">
  <div id="row1">
    <span id="shotprog"></span>
    <b id="fname"></b>
    <span id="prog"></span>
    <span id="hoselflag" style="font-family:Menlo,monospace"></span>
  </div>
  <div id="row2">
    <button id="prevShot">‹ shot</button>
    <button id="nextShot">shot ›</button>
    <button id="bgone" class="danger">Ball gone (G)</button>
    <button id="cgone" class="danger">No club (X)</button>
    <button id="bmode">Place ball (B)</button>
    <button id="cmode">Place club (C)</button>
    <button id="hmode" style="border-color:#e8c268">Place HOSEL (H)</button>
    <button id="hgone" class="danger">No hosel (N)</button>
    <button id="approve" class="ok">Approve frame (A)</button>
    <button id="approveShot" class="ok">Approve shot (S)</button>
  </div>
</div>
<div id="wrap">
  <div id="canvasbox"><canvas id="cv"></canvas></div>
  <div id="side">
    <div>Frames <span style="color:#98a2ab">(green = reviewed)</span>:</div>
    <div class="fstrip" id="fstrip"></div>
    <div id="status">Keys: <kbd>←</kbd><kbd>→</kbd> frames · <kbd>[</kbd><kbd>]</kbd> shots · <kbd>B</kbd> ball mode then click center, scroll = radius · <kbd>C</kbd> club mode then click clubhead center · <kbd>H</kbd> hosel mode then click shaft-head junction · <kbd>G</kbd> ball gone · <kbd>X</kbd> no club · <kbd>N</kbd> no hosel · <kbd>A</kbd>/<kbd>Enter</kbd> approve · <kbd>S</kbd> approve whole shot · gold ◆ on a frame chip = hosel placed there</div>
  </div>
</div>
<script>
const S = 2.4;                       // display scale
let shots = [], shotIdx = 0, cur = null, fIdx = 0, mode = null, img = new Image();
const cv = document.getElementById('cv'), ctx = cv.getContext('2d');

async function j(url, opts) { const r = await fetch(url, opts); return r.json(); }

async function init() {
  shots = await j('/shots');
  // resume at the first shot with unreviewed frames
  let start = shots.findIndex(s => s.reviewed < s.total);
  await loadShot(start < 0 ? 0 : start);
}
function shotProg() {
  const done = shots.filter(s => s.reviewed >= s.total).length;
  document.getElementById('shotprog').textContent =
    `shot ${shotIdx+1}/${shots.length} · ${done} fully labeled`;
}
async function loadShot(i) {
  shotIdx = Math.max(0, Math.min(shots.length - 1, i));
  cur = await j('/shot/' + shots[shotIdx].name);
  fIdx = Math.max(0, cur.frames.indexOf(cur.impact) - 1);
  shotProg(); renderStrip(); loadFrame();
}
function frame() { return cur.frames[fIdx]; }
function lab() { return cur.per_frame[String(frame())]; }
function loadFrame() {
  img = new Image();
  img.onload = () => { cv.width = img.width * S; cv.height = img.height * S; draw(); };
  img.src = '/img/' + cur.name + '/' + frame();
  document.getElementById('fname').textContent =
    cur.name + '  f' + frame() + (frame() === cur.impact ? '  IMPACT' : '');
  renderStrip();
}
function draw() {
  ctx.drawImage(img, 0, 0, cv.width, cv.height);   // ORIGINAL pixels, just scaled
  const L = lab();
  if (L.ball) {
    ctx.strokeStyle = '#ff4d42'; ctx.lineWidth = 2.5; ctx.beginPath();
    ctx.arc(L.ball.cx*S, L.ball.cy*S, Math.max(L.ball.r*S, 6), 0, 7); ctx.stroke();
  }
  if (L.club) {
    ctx.strokeStyle = ctx.fillStyle = '#31d3e8'; ctx.lineWidth = 2;
    const x = L.club.cx*S, y = L.club.cy*S;
    ctx.beginPath(); ctx.arc(x, y, 4, 0, 7); ctx.fill();
    ctx.beginPath(); ctx.moveTo(x-12,y); ctx.lineTo(x+12,y); ctx.moveTo(x,y-12); ctx.lineTo(x,y+12); ctx.stroke();
  }
  if (L.hosel) {
    // gold diamond — the shaft-head junction
    ctx.strokeStyle = ctx.fillStyle = '#e8c268'; ctx.lineWidth = 2.5;
    const hx = L.hosel.cx*S, hy = L.hosel.cy*S;
    ctx.beginPath();
    ctx.moveTo(hx, hy-9); ctx.lineTo(hx+9, hy); ctx.lineTo(hx, hy+9); ctx.lineTo(hx-9, hy);
    ctx.closePath(); ctx.stroke();
    ctx.beginPath(); ctx.arc(hx, hy, 2, 0, 7); ctx.fill();
  }
  document.getElementById('prog').textContent =
    (L.reviewed ? '✓ reviewed' : '· unreviewed') + (mode ? ('   MODE: place ' + mode) : '');
  const hf = document.getElementById('hoselflag');
  if (L.hosel) { hf.textContent = '◆ HOSEL PLACED'; hf.style.color = '#e8c268'; }
  else { hf.textContent = '◇ no hosel'; hf.style.color = '#5a646d'; }
}
function renderStrip() {
  const el = document.getElementById('fstrip');
  el.innerHTML = cur.frames.map((f,i)=>{
    const L = cur.per_frame[String(f)];
    return `<span class="fchip ${i===fIdx?'cur':''} ${L.reviewed?'rev':''}" onclick="fIdx=${i};loadFrame()">f${f}${L.hosel?'<span class="hd">◆</span>':''}</span>`;
  }).join('');
}
async function push(extra) {
  const L = lab();
  Object.assign(L, extra || {});
  L.reviewed = true;
  await j('/label', {method:'POST', headers:{'Content-Type':'application/json'},
    body: JSON.stringify({shot: cur.name, fi: frame(), ball: L.ball, club: L.club, hosel: L.hosel})});
  shots[shotIdx].reviewed = Object.values(cur.per_frame).filter(x=>x.reviewed).length;
  shotProg(); draw(); renderStrip();
}
cv.addEventListener('click', e => {
  if (!mode) return;
  const r = cv.getBoundingClientRect();
  const x = (e.clientX - r.left)/S, y = (e.clientY - r.top)/S;
  if (mode === 'ball') { const L = lab(); const rr = (L.ball && L.ball.r) || 8; push({ball:{cx:x, cy:y, r:rr}}); }
  else if (mode === 'hosel') { push({hosel:{cx:x, cy:y}}); }
  else if (mode === 'club') { push({club:{cx:x, cy:y}}); }
  // Mode stays STICKY across clicks and frames (Noah: click through back-to-back without
  // re-selecting the tool every frame). Escape clears it.
  draw();
});
cv.addEventListener('wheel', e => {
  const L = lab();
  if (!L.ball) return;
  e.preventDefault();
  L.ball.r = Math.max(2, Math.min(30, L.ball.r + (e.deltaY < 0 ? 0.7 : -0.7)));
  push({ball: L.ball});
}, {passive: false});
function setMode(m, btn) {
  mode = m; document.querySelectorAll('button').forEach(b=>b.classList.remove('mode'));
  if (m) document.getElementById(btn).classList.add('mode');
  draw();
}
document.getElementById('bmode').onclick = () => setMode('ball','bmode');
document.getElementById('cmode').onclick = () => setMode('club','cmode');
document.getElementById('hmode').onclick = () => setMode('hosel','hmode');
document.getElementById('bgone').onclick = () => push({ball:null});
document.getElementById('cgone').onclick = () => push({club:null});
document.getElementById('hgone').onclick = () => push({hosel:null});
document.getElementById('approve').onclick = () => { push({}); step(1); };
document.getElementById('approveShot').onclick = async () => {
  await j('/approve_shot', {method:'POST', headers:{'Content-Type':'application/json'},
    body: JSON.stringify({shot: cur.name})});
  shots[shotIdx].reviewed = shots[shotIdx].total;
  if (shotIdx < shots.length - 1) loadShot(shotIdx + 1);   // auto-advance
  else { shotProg(); draw(); renderStrip(); }
};
document.getElementById('prevShot').onclick = () => loadShot(shotIdx - 1);
document.getElementById('nextShot').onclick = () => loadShot(shotIdx + 1);
function step(d) { fIdx = Math.max(0, Math.min(cur.frames.length-1, fIdx+d)); loadFrame(); }
document.addEventListener('keydown', e => {
  if (e.key === 'ArrowRight') step(1);
  else if (e.key === 'ArrowLeft') step(-1);
  else if (e.key === ']') loadShot(Math.min(shots.length-1, shotIdx+1));
  else if (e.key === '[') loadShot(Math.max(0, shotIdx-1));
  else if (e.key === 'b' || e.key === 'B') setMode('ball','bmode');
  else if (e.key === 'c' || e.key === 'C') setMode('club','cmode');
  else if (e.key === 'h' || e.key === 'H') setMode('hosel','hmode');
  else if (e.key === 'g' || e.key === 'G') push({ball:null});
  else if (e.key === 'x' || e.key === 'X') push({club:null});
  else if (e.key === 'n' || e.key === 'N') push({hosel:null});
  else if (e.key === 'a' || e.key === 'A' || e.key === 'Enter') { push({}); step(1); }
  else if (e.key === 's' || e.key === 'S') document.getElementById('approveShot').click();
  else if (e.key === 'Escape') setMode(null, null);
});
init();
</script></body></html>"""


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == '/' or self.path == '/index.html':
            body = HTML.encode()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == '/shots':
            out = []
            for s in all_shots():
                pl = prelabels.get(s)
                total = len(pl['frames']) if pl else 13
                rev = 0
                if s in labels:
                    rev = sum(1 for v in labels[s].values() if v.get('reviewed'))
                out.append({'name': s, 'total': total, 'reviewed': rev})
            self._json(out)
        elif self.path.startswith('/shot/'):
            shot = self.path.split('/')[2]
            pl = get_prelabel(shot)
            if pl is None:
                self._json({'error': 'not found'}, 404)
                return
            merged = {}
            for fi in pl['frames']:
                k = str(fi)
                base = dict(pl['per_frame'][k])
                base['reviewed'] = False
                if shot in labels and k in labels[shot]:
                    u = labels[shot][k]
                    base['ball'] = u.get('ball')
                    base['club'] = u.get('club')
                    # 'hosel' key present = this label was saved during the hosel
                    # round; honor it even when null (explicit removal). Key absent
                    # = old club-round label; let the YOLO prelabel show through.
                    if 'hosel' in u: base['hosel'] = u['hosel']
                    base['reviewed'] = u.get('reviewed', False)
                merged[k] = base
            self._json({'name': shot, 'impact': pl['impact'], 'frames': pl['frames'],
                        'W': pl['W'], 'H': pl['H'], 'per_frame': merged})
        elif self.path.startswith('/img/'):
            _, _, shot, fi = self.path.split('/')
            p = frame_path(os.path.join(ARCHIVE, shot), int(fi))
            if not os.path.exists(p):
                self.send_response(404)
                self.end_headers()
                return
            data = open(p, 'rb').read()
            self.send_response(200)
            self.send_header('Content-Type', 'image/png')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0))
        req = json.loads(self.rfile.read(n)) if n else {}
        if self.path == '/label':
            shot, fi = req['shot'], str(req['fi'])
            labels.setdefault(shot, {})[fi] = {
                'ball': req.get('ball'), 'club': req.get('club'),
                'hosel': req.get('hosel'), 'reviewed': True}
            save_labels()
            self._json({'ok': True})
        elif self.path == '/approve_shot':
            shot = req['shot']
            pl = get_prelabel(shot)
            for fi in pl['frames']:
                k = str(fi)
                if shot in labels and k in labels[shot]:
                    labels[shot][k]['reviewed'] = True
                else:
                    base = pl['per_frame'][k]
                    labels.setdefault(shot, {})[k] = {
                        'ball': base['ball'], 'club': base['club'],
                        'hosel': base.get('hosel'), 'reviewed': True}
            save_labels()
            self._json({'ok': True})
        else:
            self.send_response(404)
            self.end_headers()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', type=int, default=8765)
    a = ap.parse_args()
    print(f'Labeler running → http://localhost:{a.port}   (labels: {LABELS_PATH})')
    ThreadingHTTPServer(('127.0.0.1', a.port), H).serve_forever()


if __name__ == '__main__':
    main()
