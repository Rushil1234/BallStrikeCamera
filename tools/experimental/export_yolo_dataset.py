#!/usr/bin/env python3
"""Export Noah's labels to YOLO fine-tune datasets (for the Colab GPU notebook).

Classes: 0=head (club label point -> box), 1=hosel (point -> small box), 2=ball
(circle -> box). Images are the club-window / flight frames that carry labels.

Two variants in ONE zip (Noah, July 20):
  all    every session, junk shots rejected — the volume model
  jul17  only the July 17 range session (TT+Garmin truth, best capture
         quality) — the purity model

Junk shots (hosel_junk_shots.json, written by hosel_speed_shootout.py) are
excluded ENTIRELY — static/backwards hosels or no club labeled at all. These
wouldn't register in the sim and must not teach the detector.

Output: ~/Documents/TrueCarryTraining/yolo_datasets/{all,jul17}/... + one
yolo_datasets.zip for upload to Colab.

Run after labeling:  python3 tools/experimental/export_yolo_dataset.py
"""
import json, os, random, shutil, zipfile

import cv2

TRAIN = os.path.expanduser('~/Documents/TrueCarryTraining')
LABELS = json.load(open(os.path.join(TRAIN, 'labels/labels.json')))
# Shots that failed the physics gates (static/backwards hosel) or have no club
# labeled anywhere — see hosel_speed_shootout.py. Excluded from BOTH variants.
try:
    _j = json.load(open(os.path.join(TRAIN, 'hosel_junk_shots.json')))
    JUNK = set(_j) if isinstance(_j, (list, dict)) else set()
except FileNotFoundError:
    JUNK = set()
ARCHIVES = [os.path.expanduser(a) for a in (
    '~/Documents/TrueCarryTraining/hosel_archive',   # symlinks; covers all 375 hosel-round shots
    '~/Documents/TrueCarryFramesArchive_20260717/AllFramesArchive',
    '~/Documents/TrueCarryFramesArchive_20260716/AllFramesArchive',
    '~/Documents/TrueCarryFramesArchive_20260712/AllFramesArchive')]
OUT_ROOT = os.path.join(TRAIN, 'yolo_datasets')
W, H = 360.0, 203.0
HEAD_BOX = 26.0     # px box around the club-head label point
HOSEL_BOX = 14.0    # px box around the hosel point


def frame_path(shot, fi):
    # July-14 JPEG switch: new captures are .jpg, older archives .png
    for a in ARCHIVES:
        for ext in ('jpg', 'png'):
            p = os.path.join(a, shot, f'frame_{fi:03d}.{ext}')
            if os.path.exists(p):
                return p
    return None


def collect_rows(shot_filter=None):
    rows = []
    for shot, labs in sorted(LABELS.items()):
        if shot in JUNK:
            continue
        if shot_filter and not shot.startswith(shot_filter):
            continue
        for fi_s, e in labs.items():
            if not isinstance(e, dict) or not e.get('reviewed'):
                continue
            lines = []
            if e.get('club'):
                c = e['club']
                lines.append(f"0 {c['cx']/W:.5f} {c['cy']/H:.5f} {HEAD_BOX/W:.5f} {HEAD_BOX/H:.5f}")
            if e.get('hosel'):
                c = e['hosel']
                lines.append(f"1 {c['cx']/W:.5f} {c['cy']/H:.5f} {HOSEL_BOX/W:.5f} {HOSEL_BOX/H:.5f}")
            if e.get('ball'):
                b = e['ball']
                r = max(3.0, b.get('r', 6))
                lines.append(f"2 {b['cx']/W:.5f} {b['cy']/H:.5f} {2.4*r/W:.5f} {2.4*r/H:.5f}")
            if not lines:
                continue
            p = frame_path(shot, int(fi_s))
            if p:
                rows.append((shot, int(fi_s), p, lines))
    return rows


def write_dataset(name, rows):
    out = os.path.join(OUT_ROOT, name)
    for split in ('train', 'val'):
        os.makedirs(os.path.join(out, 'images', split))
        os.makedirs(os.path.join(out, 'labels', split))
    # split by SHOT, not frame — frames of one swing are near-duplicates and
    # would leak train->val, flattering the metrics
    shots = sorted({r[0] for r in rows})
    random.Random(0).shuffle(shots)
    n_val = max(5, len(shots) // 10)
    val_shots = set(shots[:n_val])
    nv = 0
    for shot, fi, p, lines in rows:
        split = 'val' if shot in val_shots else 'train'
        nv += split == 'val'
        stem = f'{shot}_f{fi:03d}'
        dst = os.path.join(out, 'images', split, stem + '.jpg')
        if p.endswith('.png'):
            # old white archives are PNG — recompress to JPEG q92 (the zip was
            # 464 MB otherwise; q92 is invisible to the detector)
            cv2.imwrite(dst, cv2.imread(p), [cv2.IMWRITE_JPEG_QUALITY, 92])
        else:
            shutil.copy(p, dst)
        open(os.path.join(out, 'labels', split, stem + '.txt'), 'w').write('\n'.join(lines))
    # No 'path:' key — ultralytics then roots the dataset at the yaml's own
    # directory, so the zip works wherever it's extracted (a hardcoded
    # /content path broke Noah's Colab run when he extracted elsewhere).
    open(os.path.join(out, 'data.yaml'), 'w').write(
        "train: images/train\nval: images/val\n"
        "names:\n  0: head\n  1: hosel\n  2: ball\n")
    print(f'  {name}: {len(rows)} frames / {len(shots)} shots '
          f'({nv} val frames from {n_val} held-out shots)')
    return out


def main():
    shutil.rmtree(OUT_ROOT, ignore_errors=True)
    print(f'junk shots excluded: {len(JUNK)}')
    write_dataset('all', collect_rows())
    write_dataset('jul17', collect_rows('shot_20260717'))
    zpath = os.path.join(TRAIN, 'yolo_datasets.zip')
    with zipfile.ZipFile(zpath, 'w', zipfile.ZIP_DEFLATED) as z:
        for root, _, files in os.walk(OUT_ROOT):
            for f in files:
                fp = os.path.join(root, f)
                z.write(fp, os.path.relpath(fp, TRAIN))
    print(f'upload to Colab: {zpath}')


if __name__ == '__main__':
    main()
