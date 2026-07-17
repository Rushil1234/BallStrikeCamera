#!/usr/bin/env python3.11
"""Club mask zoo: ~20 mask/differencing methods vs Noah's club labels.

For every labeled club frame, run each method, extract blobs, and check whether ANY
blob lands within 15px of the label. Reports per-method hit rate + the UNION ceiling
(aggregated findability) + candidate burden (how many blobs/frame the union emits).
"""
import json, math, os, sys
import cv2
import numpy as np

sys.path.insert(0, '/Users/noahtobias/Downloads/BallStrikeCamera/tools/experimental')
from hsv_object_explorer import frame_path
from hue_dist_gallery import hue_dist

A1 = os.path.expanduser('~/Documents/TrueCarryFramesArchive_20260712/AllFramesArchive')
A2 = os.path.expanduser('~/Documents/TrueCarryFramesArchive_20260716/AllFramesArchive')
LABELS = json.load(open(os.path.expanduser('~/Documents/TrueCarryTraining/labels/labels.json')))

def shot_dir(s):
    d = os.path.join(A1, s)
    return d if os.path.isdir(d) else os.path.join(A2, s)

def blobs(mask, amin=20, amax=9000):
    n, lab, stats, cents = cv2.connectedComponentsWithStats(mask.astype(np.uint8), 8)
    out = []
    for i in range(1, n):
        a = stats[i][4]
        if amin <= a <= amax:
            out.append((cents[i][0], cents[i][1], a))
    return out

K3 = np.ones((3,3), np.uint8)
K5 = np.ones((5,5), np.uint8)

def mo(m, ok=K3, ck=K5):
    m = cv2.morphologyEx(m.astype(np.uint8), cv2.MORPH_OPEN, ok)
    return cv2.morphologyEx(m, cv2.MORPH_CLOSE, ck)

def build_masks(bgr, prev, prev2, nxt, base):
    """Returns {name: binary mask}."""
    out = {}
    luma = bgr.mean(axis=2)
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    Hp, S, V = hsv[...,0].astype(int), hsv[...,1].astype(int), hsv[...,2].astype(int)
    dh, _ = hue_dist(bgr)
    mot = np.abs(luma - base) if base is not None else np.zeros_like(luma)
    bgr_i = bgr.astype(int)
    spread = bgr_i.max(axis=2) - bgr_i.min(axis=2)

    out['A_bright_dh160'] = mo(dh >= 160)
    out['B_bright_dh120'] = mo(dh >= 120)
    out['C_dark_cur']     = mo((V <= 78) & (S <= 130) & (mot >= 12))
    out['D_dark_v100']    = mo((V <= 100) & (mot >= 15))
    out['E_dark_v130']    = mo((V <= 130) & (mot >= 20))
    out['F_mot20']        = mo(mot >= 20)
    out['G_mot35']        = mo(mot >= 35)
    out['H_mot50']        = mo(mot >= 50)
    if prev is not None:
        fd1 = np.abs(luma - prev.mean(axis=2))
        out['I_diff1_15'] = mo(fd1 >= 15)
        out['J_diff1_25'] = mo(fd1 >= 25)
        if nxt is not None:
            fdn = np.abs(luma - nxt.mean(axis=2))
            out['K_3frame_12'] = mo((fd1 >= 12) & (fdn >= 12))
    if prev2 is not None:
        out['L_diff2_20'] = mo(np.abs(luma - prev2.mean(axis=2)) >= 20)
    g = np.clip(bgr_i * 2.2, 0, 255).astype(np.uint8)
    dh_g, _ = hue_dist(g)
    out['M_gained_dh160'] = mo(dh_g >= 160)
    ghsv = cv2.cvtColor(g, cv2.COLOR_BGR2HSV)
    out['N_gained_dark'] = mo((ghsv[...,2] <= 110) & (mot >= 12))
    gx = cv2.Sobel(luma, cv2.CV_64F, 1, 0, ksize=3)
    gy = cv2.Sobel(luma, cv2.CV_64F, 0, 1, ksize=3)
    grad = np.hypot(gx, gy)
    out['O_edges_mot'] = mo((grad >= 60) & (mot >= 10))
    out['P_steel']     = mo((spread <= 30) & (V >= 60) & (V <= 190) & (mot >= 15))
    out['Q_specular']  = mo((V >= 200) & (S <= 60))
    th = cv2.morphologyEx(luma.astype(np.uint8), cv2.MORPH_TOPHAT, np.ones((9,9), np.uint8))
    out['T_tophat']    = mo((th >= 25) & (mot >= 10))
    out['U_mot12']     = mo(mot >= 12)
    out['V_darkhat']   = mo((cv2.morphologyEx(luma.astype(np.uint8), cv2.MORPH_BLACKHAT, np.ones((9,9), np.uint8)) >= 25) & (mot >= 10))
    return out

# collect labeled club frames (window impact-6..impact+1 approx; we take all club labels)
tasks = []
for shot, v in sorted(LABELS.items()):
    d = shot_dir(shot)
    if not os.path.isdir(d):
        continue
    for k, e in v.items():
        if e.get('reviewed') and e.get('club'):
            tasks.append((shot, int(k), e['club']))
print(f"labeled club points: {len(tasks)}")

hits = {}
union_hits = 0
union_burden = []
frames_done = 0
base_cache = {}
for shot, fi, cl in tasks:
    d = shot_dir(shot)
    bgr = cv2.imread(frame_path(d, fi))
    if bgr is None: continue
    if shot not in base_cache:
        pres = []
        for i in range(0, 14, 3):
            p = frame_path(d, i)
            if os.path.exists(p): pres.append(cv2.imread(p).mean(axis=2))
        base_cache[shot] = np.median(np.stack(pres), axis=0) if len(pres) >= 3 else None
    prev = cv2.imread(frame_path(d, fi-1)) if os.path.exists(frame_path(d, fi-1)) else None
    prev2 = cv2.imread(frame_path(d, fi-2)) if os.path.exists(frame_path(d, fi-2)) else None
    nxt = cv2.imread(frame_path(d, fi+1)) if os.path.exists(frame_path(d, fi+1)) else None
    masks = build_masks(bgr, prev, prev2, nxt, base_cache[shot])
    frames_done += 1
    frame_hit = False
    nblobs = 0
    for name, m in masks.items():
        got = False
        bl = blobs(m)
        nblobs += len(bl)
        for (cx, cy, a) in bl:
            if math.hypot(cx - cl['cx'], cy - cl['cy']) <= 15:
                got = True
                break
        if got:
            hits[name] = hits.get(name, 0) + 1
            frame_hit = True
    if frame_hit: union_hits += 1
    union_burden.append(nblobs)

print(f"\nframes evaluated: {frames_done}")
print(f"{'method':16} hit-rate")
for name in sorted(hits, key=lambda n: -hits[n]):
    print(f"  {name:16} {100*hits[name]/frames_done:5.1f}%")
print(f"\nUNION (any method finds the club): {union_hits}/{frames_done} = {100*union_hits/frames_done:.1f}%")
print(f"candidate burden: median {int(np.median(union_burden))} blobs/frame across all masks")
