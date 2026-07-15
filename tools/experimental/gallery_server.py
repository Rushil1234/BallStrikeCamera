#!/usr/bin/env python3
"""Read-only tracking gallery — all shots, ORIGINAL frames, detector overlays.

Shows predictions_v2.json (the shipping detector's picks) on untouched frames:
red circle = ball pick, cyan crosshair = club pick. No oracle/labels shown.

Run:  python3 tools/experimental/gallery_server.py [--port 8766]
Keys: ←/→ frames · [ / ] shots · space = play/pause
"""
import argparse, json, os, sys
from hsv_object_explorer import frame_path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ARCHIVE = os.path.expanduser('~/Documents/TrueCarryFramesArchive_20260712/AllFramesArchive')
PRED_PATH = os.path.expanduser('~/Documents/TrueCarryTraining/labels/predictions_v2.json')

HTML = """<!doctype html><html><head><meta charset="utf-8"><title>Tracking Gallery</title>
<style>
body { background:#101316; color:#e8ebee; font:14px/1.4 -apple-system,sans-serif; margin:0; }
#top { padding:10px 14px; background:#181d22; border-bottom:1px solid #2a3138; display:flex; gap:14px; align-items:center; }
#prog { font-family:Menlo,monospace; color:#e0c93f; }
button { background:#232a31; color:#e8ebee; border:1px solid #39424b; border-radius:6px; padding:6px 12px; cursor:pointer; }
#wrap { padding:12px; }
canvas { border:1px solid #2a3138; border-radius:6px; }
.fstrip { display:flex; flex-wrap:wrap; gap:4px; margin-top:8px; max-width:900px; }
.fchip { padding:2px 7px; border-radius:4px; background:#232a31; cursor:pointer; font:12px Menlo,monospace; border:1px solid transparent; }
.fchip.cur { border-color:#e0c93f; }
.fchip.ball { background:#3a2426; }
.fchip.ballclub { background:#24363a; }
</style></head><body>
<div id="top">
  <button onclick="stepShot(-1)">‹ shot</button>
  <button onclick="stepShot(1)">shot ›</button>
  <span id="prog"></span>
  <button id="play" onclick="togglePlay()">▶ play</button>
  <span style="color:#98a2ab">red = ball · cyan = club (to impact) · chip tint = has ball / ball+club</span>
</div>
<div id="wrap">
  <canvas id="cv"></canvas>
  <div class="fstrip" id="fstrip"></div>
</div>
<script>
const S = 2.4;
let shots = [], si = 0, cur = null, fi = 0, playing = false, img = new Image();
const cv = document.getElementById('cv'), ctx = cv.getContext('2d');
async function j(u) { return (await fetch(u)).json(); }
async function init() { shots = await j('/shots'); loadShot(0); }
async function loadShot(i) {
  si = Math.max(0, Math.min(shots.length - 1, i));
  cur = await j('/shot/' + shots[si]);
  fi = 0; strip(); frame();
}
function frame() {
  const f = cur.frames[fi];
  img = new Image();
  img.onload = () => { cv.width = img.width * S; cv.height = img.height * S; draw(); };
  img.src = '/img/' + cur.name + '/' + f;
  document.getElementById('prog').textContent = `shot ${si+1}/${shots.length} — ${cur.name}  f${f}` + (f === cur.impact ? ' IMPACT' : '');
  strip();
}
function draw() {
  ctx.drawImage(img, 0, 0, cv.width, cv.height);
  const e = cur.per_frame[String(cur.frames[fi])] || {};
  if (e.ball) {
    ctx.strokeStyle = '#ff4d42'; ctx.lineWidth = 2.5; ctx.beginPath();
    ctx.arc(e.ball.cx * S, e.ball.cy * S, Math.max(e.ball.r * S, 6), 0, 7); ctx.stroke();
  }
  if (e.club) {
    ctx.strokeStyle = ctx.fillStyle = '#31d3e8'; ctx.lineWidth = 2;
    const x = e.club.cx * S, y = e.club.cy * S;
    ctx.beginPath(); ctx.arc(x, y, 4, 0, 7); ctx.fill();
    ctx.beginPath(); ctx.moveTo(x - 12, y); ctx.lineTo(x + 12, y);
    ctx.moveTo(x, y - 12); ctx.lineTo(x, y + 12); ctx.stroke();
  }
}
function strip() {
  document.getElementById('fstrip').innerHTML = cur.frames.map((f, i) => {
    const e = cur.per_frame[String(f)] || {};
    const cls = e.ball && e.club ? 'ballclub' : (e.ball ? 'ball' : '');
    return `<span class="fchip ${i === fi ? 'cur' : ''} ${cls}" onclick="fi=${i};frame()">f${f}</span>`;
  }).join('');
}
function stepShot(d) { loadShot(si + d); }
function togglePlay() {
  playing = !playing;
  document.getElementById('play').textContent = playing ? '⏸ pause' : '▶ play';
  if (playing) tick();
}
function tick() {
  if (!playing) return;
  fi = (fi + 1) % cur.frames.length;
  frame();
  setTimeout(tick, 160);
}
document.addEventListener('keydown', e => {
  if (e.key === 'ArrowRight') { fi = Math.min(cur.frames.length - 1, fi + 1); frame(); }
  else if (e.key === 'ArrowLeft') { fi = Math.max(0, fi - 1); frame(); }
  else if (e.key === ']') stepShot(1);
  else if (e.key === '[') stepShot(-1);
  else if (e.key === ' ') { e.preventDefault(); togglePlay(); }
});
init();
</script></body></html>"""


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _json(self, obj):
        b = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        preds = json.load(open(PRED_PATH))
        if self.path == '/':
            b = HTML.encode()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(b)))
            self.end_headers()
            self.wfile.write(b)
        elif self.path == '/shots':
            self._json(sorted(preds))
        elif self.path.startswith('/shot/'):
            shot = self.path.split('/')[2]
            pf = preds.get(shot, {})
            frames = sorted(int(k) for k in pf)
            ball_moves = [f for f in frames if pf[str(f)].get('ball')]
            self._json({'name': shot, 'frames': frames, 'impact': None, 'per_frame': pf})
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', type=int, default=8766)
    a = ap.parse_args()
    print(f'Gallery → http://localhost:{a.port}')
    ThreadingHTTPServer(('127.0.0.1', a.port), H).serve_forever()


if __name__ == '__main__':
    main()
