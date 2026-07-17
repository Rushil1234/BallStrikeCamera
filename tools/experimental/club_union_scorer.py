#!/usr/bin/env python3.11
"""Union-candidate club scorer + kinematic chain, end-to-end.

1) Dataset: for every labeled club frame, extract union candidates (5 masks) with full
   appearance features; positive = within 15px of the label.
2) Train logistic scorer (day-holdout validated).
3) Chain: DP with node = scorer prob, edges = Noah's priors (closing, plausible step),
   terminal at ball. Report window coverage vs labels.
"""
import json, math, os, sys
import cv2
import numpy as np

sys.path.insert(0, '/Users/noahtobias/Downloads/BallStrikeCamera/tools/experimental')
from hsv_object_explorer import frame_path
from hue_dist_gallery import hue_dist

A1 = os.path.expanduser('~/Documents/TrueCarryTraining/../TrueCarryFramesArchive_20260712/AllFramesArchive')
A1 = os.path.expanduser('~/Documents/TrueCarryFramesArchive_20260712/AllFramesArchive')
A2 = os.path.expanduser('~/Documents/TrueCarryFramesArchive_20260716/AllFramesArchive')
LABELS = json.load(open(os.path.expanduser('~/Documents/TrueCarryTraining/labels/labels.json')))
CACHE = os.path.expanduser('~/Documents/TrueCarryTraining/labels/club_union_cache_v2.json')

def shot_dir(s):
    d = os.path.join(A1, s)
    return d if os.path.isdir(d) else os.path.join(A2, s)

K3 = np.ones((3,3), np.uint8); K5 = np.ones((5,5), np.uint8)
def mo(m):
    m = cv2.morphologyEx(m.astype(np.uint8), cv2.MORPH_OPEN, K3)
    return cv2.morphologyEx(m, cv2.MORPH_CLOSE, K5)

SRC = ['O','G','T','M','B']

def union_cands(bgr, base):
    luma = bgr.mean(axis=2)
    mot = np.abs(luma - base) if base is not None else np.zeros_like(luma)
    dh, _ = hue_dist(bgr)
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    V = hsv[...,2].astype(int)
    gx = cv2.Sobel(luma, cv2.CV_64F, 1, 0, ksize=3); gy = cv2.Sobel(luma, cv2.CV_64F, 0, 1, ksize=3)
    grad = np.hypot(gx, gy)
    g = np.clip(bgr.astype(int) * 2.2, 0, 255).astype(np.uint8)
    dh_g, _ = hue_dist(g)
    th = cv2.morphologyEx(luma.astype(np.uint8), cv2.MORPH_TOPHAT, np.ones((9,9), np.uint8))
    masks = {
        'O': mo((grad >= 60) & (mot >= 10)),
        'G': mo(mot >= 35),
        'T': mo((th >= 25) & (mot >= 10)),
        'M': mo(dh_g >= 160),
        'B': mo(dh >= 120),
    }
    HUE = hsv[...,0].astype(int); SAT = hsv[...,1].astype(int)
    # shaft lines: long straightish edges — the head hangs off one end
    edges8 = ((grad >= 60) & (mot >= 8)).astype(np.uint8) * 255
    lines = cv2.HoughLinesP(edges8, 1, np.pi/180, threshold=28, minLineLength=32, maxLineGap=6)
    line_ends = []
    if lines is not None:
        for l in lines[:40]:
            x1,y1,x2,y2 = l[0]
            if math.hypot(x2-x1, y2-y1) >= 32:
                line_ends.append((x1,y1)); line_ends.append((x2,y2))
    pts = []
    for name, m in masks.items():
        n, lab, stats, cents = cv2.connectedComponentsWithStats(m, 8)
        for i in range(1, n):
            x, y, w, h, a = stats[i]
            if not (30 <= a <= 9000): continue
            cx, cy = cents[i]
            comp = (lab[y:y+h, x:x+w] == i)
            ys, xs = np.nonzero(comp)
            mu20 = ((xs-xs.mean())**2).mean(); mu02 = ((ys-ys.mean())**2).mean()
            mu11 = ((xs-xs.mean())*(ys-ys.mean())).mean()
            elong = math.hypot(mu20-mu02, 2*mu11) / (mu20+mu02+1e-9)
            dline = min((math.hypot(cx-ex, cy-ey) for ex,ey in line_ends), default=200.0)
            pts.append(dict(cx=float(cx), cy=float(cy), a=float(a), w=int(w), h=int(h), src=name,
                            elong=float(elong),
                            mot=float(mot[y:y+h, x:x+w].mean()),
                            dh=float(dh[y:y+h, x:x+w].mean()),
                            v=float(V[y:y+h, x:x+w].mean()),
                            hue=float(HUE[y:y+h, x:x+w].mean()),
                            sat=float(SAT[y:y+h, x:x+w].mean()),
                            grad=float(grad[y:y+h, x:x+w].mean()),
                            dline=float(min(dline, 200.0)),
                            border=bool(x <= 1 or y <= 1 or x+w >= m.shape[1]-2 or y+h >= m.shape[0]-2)))
    pts.sort(key=lambda p: -p['a'])
    kept = []
    for p in pts:
        agree = 1
        for q in list(kept):
            if math.hypot(p['cx']-q['cx'], p['cy']-q['cy']) <= 6:
                q['agree'] = q.get('agree', 1) + 1
                agree = 0
                break
        if agree:
            p['agree'] = 1
            kept.append(p)
    return kept[:40]

def feats(c, lock):
    dball = math.hypot(c['cx']-lock[0], c['cy']-lock[1])
    behind = 1.0 if c['cx'] >= lock[0] - 10 else 0.0
    return [math.log(max(c['a'],1)), max(c['w'],c['h'])/max(1,min(c['w'],c['h'])),
            min(c['mot'],80)/80.0, c['dh']/255.0, c['v']/255.0,
            min(dball/120.0, 2.0), behind, 1.0 if c['border'] else 0.0,
            c.get('elong',0.5), c.get('hue',0)/180.0, c.get('sat',0)/255.0,
            min(c.get('grad',0),150)/150.0, min(c.get('dline',200),200)/200.0,
            min(c.get('agree',1),5)/5.0,
            *[1.0 if c['src']==s else 0.0 for s in SRC]]

def label_impact_and_lock(v):
    pts = sorted(((int(f), e['ball']) for f, e in v.items() if e.get('reviewed') and e.get('ball')), key=lambda t: t[0])
    if not pts: return None, None
    b0 = pts[0][1]
    for fi, b in pts:
        if math.hypot(b['cx']-b0['cx'], b['cy']-b0['cy']) >= 1.5*max(b0['r'],4):
            return fi-1, (b0['cx'], b0['cy'])
    return None, (b0['cx'], b0['cy'])

def base_for(d):
    pres = []
    for i in range(0, 14, 3):
        p = frame_path(d, i)
        if os.path.exists(p): pres.append(cv2.imread(p).mean(axis=2))
    return np.median(np.stack(pres), axis=0) if len(pres) >= 3 else None

# ---------- dataset ----------
if os.path.exists(CACHE):
    j = json.load(open(CACHE))
    X, y, days = np.array(j['X']), np.array(j['y']), j['days']
else:
    X, y, days = [], [], []
    done = 0
    for shot, v in sorted(LABELS.items()):
        club_lab = {int(f): e['club'] for f, e in v.items() if e.get('reviewed') and e.get('club')}
        if not club_lab: continue
        d = shot_dir(shot)
        if not os.path.isdir(d): continue
        imp, lock = label_impact_and_lock(v)
        if lock is None: continue
        base = base_for(d)
        for fi, cl in club_lab.items():
            p = frame_path(d, fi)
            if not os.path.exists(p): continue
            bgr = cv2.imread(p)
            if bgr is None: continue
            negs = 0
            for c in union_cands(bgr, base):
                pos = math.hypot(c['cx']-cl['cx'], c['cy']-cl['cy']) <= 15
                if not pos:
                    negs += 1
                    if negs > 12: continue
                X.append(feats(c, lock)); y.append(1 if pos else 0); days.append(shot[5:13])
        done += 1
        if done % 40 == 0: print(f"  dataset: {done} shots")
    json.dump({'X': [list(map(float,r)) for r in X], 'y': list(map(int,y)), 'days': days}, open(CACHE,'w'))
    X, y = np.array(X), np.array(y)
print(f"dataset: {len(y)} candidates, {int(np.sum(y))} positives")

def train_lr(X, y, l2=1e-3, iters=3000, lr=0.5):
    Xb = np.hstack([X, np.ones((len(X),1))])
    w = np.zeros(Xb.shape[1])
    pw = (len(y)-y.sum())/max(1,y.sum())
    sw = np.where(y==1, pw, 1.0)
    for _ in range(iters):
        z = np.clip(Xb@w, -30, 30); p = 1/(1+np.exp(-z))
        g = Xb.T@(sw*(p-y))/len(y) + l2*np.r_[w[:-1],0]
        w -= lr*g
    return w[:-1], w[-1]

for held in sorted(set(days)):
    tr = np.array([d != held for d in days])
    te = ~tr
    w, b = train_lr(X[tr], y[tr])
    z = np.clip(X[te]@w+b, -30, 30); p = 1/(1+np.exp(-z))
    pred = (p >= 0.5).astype(int)
    tp = int(((pred==1)&(y[te]==1)).sum()); fp = int(((pred==1)&(y[te]==0)).sum())
    fn = int(((pred==0)&(y[te]==1)).sum())
    print(f"held-out {held}: precision {tp/max(tp+fp,1):.2f} recall {tp/max(tp+fn,1):.2f}")
sys.path.insert(0, '/Users/noahtobias/Downloads/BallStrikeCamera/tools/experimental')
from train_club_gbt import train_gbt
gbase, stumps = train_gbt(X, y, rounds=160)
def gbt_z(x):
    z = gbase
    for f, thr, vl, vr in stumps:
        z += vl if x[int(f)] <= thr else vr
    return z
# held-out check for GBT
for held in sorted(set(days)):
    te = np.array([d == held for d in days])
    gb, st = train_gbt(X[~te], y[~te], rounds=160)
    def z2(x):
        z = gb
        for f, thr, vl, vr in st: z += vl if x[int(f)] <= thr else vr
        return z
    ps = np.array([1/(1+math.exp(-max(-30,min(30,z2(x))))) for x in X[te]])
    pred = (ps >= 0.5).astype(int)
    tp = int(((pred==1)&(y[te]==1)).sum()); fp = int(((pred==1)&(y[te]==0)).sum()); fn = int(((pred==0)&(y[te]==1)).sum())
    print(f"GBT held-out {held}: precision {tp/max(tp+fp,1):.2f} recall {tp/max(tp+fn,1):.2f}")
w, b = train_lr(X, y)
json.dump({'w': list(map(float,w)), 'b': float(b), 'features': 'club_union_v2'},
          open(os.path.expanduser('~/Documents/TrueCarryTraining/labels/club_union_scorer.json'), 'w'))
json.dump({'stumps': [[int(f), float(t), float(l), float(h)] for f,t,l,h in stumps], 'base': float(gbase)},
          open(os.path.expanduser('~/Documents/TrueCarryTraining/labels/club_union_gbt.json'), 'w'))

# ---------- chain with scorer ----------
def chain_eval():
    tot = hit = off = 0; shots_eval = 0
    for shot, v in sorted(LABELS.items()):
        club_lab = {int(f): e['club'] for f, e in v.items() if e.get('reviewed') and e.get('club')}
        if not club_lab: continue
        d = shot_dir(shot)
        if not os.path.isdir(d): continue
        imp, lock = label_impact_and_lock(v)
        if imp is None or lock is None: continue
        base = base_for(d)
        fis = list(range(max(0, imp-6), imp+2))
        per = []
        for fi in fis:
            p = frame_path(d, fi)
            bgr = cv2.imread(p) if os.path.exists(p) else None
            cands = union_cands(bgr, base) if bgr is not None else []
            scored = []
            for c in cands:
                z = gbt_z(feats(c, lock))
                c['p'] = 1/(1+math.exp(-max(-30,min(30,z))))
                scored.append(c)
            per.append(scored)
        SKIP = -1.2
        best = {}
        for j, c in enumerate(per[0]): best[(0,j)] = (2*c['p']-1, None)
        best[(0,-1)] = (SKIP, None)
        for i in range(1, len(fis)):
            row = {}
            for j, c in enumerate(per[i] + [None]):
                jj = j if c is not None else -1
                ns = (2*c['p']-1) if c is not None else SKIP
                top = None
                for (pi,pj),(ps,_) in best.items():
                    if pi != i-1: continue
                    if c is None or pj == -1:
                        cs = ps + ns
                    else:
                        pc = per[i-1][pj]
                        step = math.hypot(c['cx']-pc['cx'], c['cy']-pc['cy'])
                        if step > 75: continue
                        d1 = math.hypot(pc['cx']-lock[0], pc['cy']-lock[1])
                        d2 = math.hypot(c['cx']-lock[0], c['cy']-lock[1])
                        if d2 > d1 + 12: continue
                        cs = ps + ns + 0.6*(1-step/75.0) + (0.4 if d2 < d1-3 else 0)
                    if top is None or cs > top[0]: top = (cs, (pi,pj))
                if top: row[(i,jj)] = top
            best.update(row)
        finals = [k for k in best if k[0] == len(fis)-1]
        if not finals: continue
        def fs(k):
            s = best[k][0]
            if k[1] >= 0:
                c = per[k[0]][k[1]]
                db = math.hypot(c['cx']-lock[0], c['cy']-lock[1])
                s += 1.5 if db < 35 else (-1.0 if db > 90 else 0)
            return s
        end = max(finals, key=fs)
        picks = {}
        k = end
        while k is not None:
            i, j = k
            if j >= 0: picks[fis[i]] = per[i][j]
            k = best[k][1]
        shots_eval += 1
        for fi, cl in club_lab.items():
            if not (imp-3 <= fi <= imp+1): continue
            tot += 1
            p = picks.get(fi)
            if p is None: continue
            err = math.hypot(p['cx']-cl['cx'], p['cy']-cl['cy'])
            if err <= 15: hit += 1
            else: off += 1
    print(f"\nCHAIN+SCORER window coverage: {hit}/{tot} = {100*hit/max(tot,1):.1f}%   off {off}   missed {tot-hit-off}   shots {shots_eval}")

chain_eval()
