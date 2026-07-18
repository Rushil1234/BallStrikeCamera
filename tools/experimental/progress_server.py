#!/usr/bin/env python3
"""Live pipeline progress monitor — one page, auto-refreshing.

Reads pipeline.json (stage list Claude updates at each transition) and, for the
stage currently running a simulator replay, counts result files live so the bar
moves in real time between updates.

Run:  python3 tools/experimental/progress_server.py [--port 8767]
Env:  TC_PIPELINE  path to pipeline.json
      TC_CONT      file containing the sim app container path (for live counts)
"""
import argparse, glob, json, os, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PIPELINE = os.environ.get('TC_PIPELINE') or os.path.expanduser(
    '~/Documents/TrueCarryTraining/pipeline.json')
CONT_FILE = os.environ.get('TC_CONT')


def live_count(stage):
    """For a running replay stage, count result jsons in the sim container."""
    if stage.get('kind') != 'replay' or stage.get('status') != 'running':
        return None
    try:
        cont = open(CONT_FILE).read().strip() if CONT_FILE else None
        if not cont:
            return None
        pat = stage.get('glob', 'shot_*.json')
        return len(glob.glob(os.path.join(cont, 'Documents', 'ReplayResults', pat)))
    except Exception:
        return None


def status():
    try:
        p = json.load(open(PIPELINE))
    except Exception as e:
        return {'error': str(e), 'stages': []}
    for s in p.get('stages', []):
        n = live_count(s)
        if n is not None:
            s['done_units'] = s.get('base_units', 0) + n
    p['now'] = time.strftime('%H:%M:%S')
    try:
        p['updated_ago_sec'] = int(time.time() - os.path.getmtime(PIPELINE))
    except Exception:
        pass
    return p


PAGE = r"""<!doctype html><html><head><meta charset="utf-8"><title>TrueCarry Pipeline</title>
<style>
 body{margin:0;background:#101312;color:#ddd;font:14px Menlo,monospace;padding:28px;max-width:860px}
 h1{font-size:18px;color:#9ab} .sub{color:#678;font-size:12px;margin-bottom:22px}
 .stage{margin:10px 0;padding:12px 14px;background:#171b19;border:1px solid #242a27;border-radius:9px}
 .head{display:flex;justify-content:space-between;margin-bottom:6px}
 .name{font-weight:bold} .eta{color:#789;font-size:12px}
 .bar{height:10px;background:#242a27;border-radius:5px;overflow:hidden}
 .fill{height:100%;border-radius:5px;transition:width .6s}
 .running .fill{background:#e8c268}.done .fill{background:#6fdd8b}
 .failed .fill{background:#e87a68}.pending .fill{background:#345}
 .done .name{color:#6fdd8b}.running .name{color:#e8c268}
 .failed .name{color:#e87a68}.pending{opacity:.55}
 .note{color:#8a9;font-size:12px;margin-top:5px}
 #overall{margin:18px 0 8px}
 #overall .bar{height:16px}
</style></head><body>
<h1>TrueCarry — tonight's pipeline</h1>
<div class="sub" id="sub"></div>
<div id="overall" class="stage running"><div class="head"><span class="name" id="oname">overall</span>
<span class="eta" id="oeta"></span></div><div class="bar"><div class="fill" id="ofill" style="width:0%"></div></div></div>
<div id="stages"></div>
<script>
async function refresh(){
  const p = await (await fetch('/status')).json();
  document.getElementById('sub').textContent =
    `now ${p.now} · status file updated ${p.updated_ago_sec}s ago · auto-refreshes every 5s`;
  let done=0,total=0;
  document.getElementById('stages').innerHTML = (p.stages||[]).map(s=>{
    const t=s.total_units||1, d=s.status==='done'?t:(s.done_units||0);
    total+=t; done+=d;
    const pct=Math.round(100*d/t);
    const eta=s.status==='done'?(s.finished||'done'):(s.status==='running'?`${d}/${t} · eta ~${s.eta||'?'}`:(s.eta?`eta ~${s.eta}`:''));
    return `<div class="stage ${s.status}"><div class="head"><span class="name">${s.label}</span>
      <span class="eta">${eta}</span></div>
      <div class="bar"><div class="fill" style="width:${s.status==='done'?100:pct}%"></div></div>
      ${s.note?`<div class="note">${s.note}</div>`:''}</div>`;
  }).join('');
  document.getElementById('ofill').style.width = Math.round(100*done/Math.max(total,1))+'%';
  document.getElementById('oeta').textContent = `${Math.round(100*done/Math.max(total,1))}% · finish ~${p.finish_eta||'?'}`;
}
refresh(); setInterval(refresh, 5000);
</script></body></html>"""


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path == '/status':
            data = json.dumps(status()).encode()
            ct = 'application/json'
        else:
            data = PAGE.encode()
            ct = 'text/html; charset=utf-8'
        self.send_response(200)
        self.send_header('Content-Type', ct)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', type=int, default=8767)
    args = ap.parse_args()
    print(f'pipeline: {PIPELINE}\nhttp://localhost:{args.port}')
    ThreadingHTTPServer(('127.0.0.1', args.port), H).serve_forever()


if __name__ == '__main__':
    main()
