#!/usr/bin/env python3
"""Export Noah's labels to a YOLO fine-tune dataset (for the Colab GPU notebook).

Classes: 0=head (club label point -> box), 1=hosel (point -> small box), 2=ball
(circle -> box). Images are the club-window / flight frames that carry labels.
Output: ~/Documents/TrueCarryTraining/yolo_dataset/{images,labels}/{train,val}
+ data.yaml, zipped for upload to Colab.

Run after labeling:  python3 tools/experimental/export_yolo_dataset.py
"""
import json, math, os, random, shutil, zipfile

TRAIN = os.path.expanduser('~/Documents/TrueCarryTraining')
LABELS = json.load(open(os.path.join(TRAIN, 'labels/labels.json')))
# Shots whose hosel labels sat on static clutter (peak hosel speed < 30 mph —
# see hosel_speed_shootout.py). Their ball/club labels are fine; hosels are not.
try:
    HOSEL_JUNK = set(json.load(open(os.path.join(TRAIN, 'hosel_junk_shots.json'))))
except FileNotFoundError:
    HOSEL_JUNK = set()
ARCHIVES = [os.path.expanduser(a) for a in (
    '~/Documents/TrueCarryTraining/hosel_archive',   # symlinks; covers all 375 hosel-round shots
    '~/Documents/TrueCarryFramesArchive_20260717/AllFramesArchive',
    '~/Documents/TrueCarryFramesArchive_20260716/AllFramesArchive',
    '~/Documents/TrueCarryFramesArchive_20260712/AllFramesArchive')]
OUT = os.path.join(TRAIN, 'yolo_dataset')
W, H = 360.0, 203.0
HEAD_BOX = 26.0     # px box around the club-head label point
HOSEL_BOX = 14.0    # px box around the hosel point


def frame_path(shot, fi):
    for a in ARCHIVES:
        p = os.path.join(a, shot, f'frame_{fi:03d}.jpg')
        if os.path.exists(p):
            return p
    return None


def main():
    shutil.rmtree(OUT, ignore_errors=True)
    for split in ('train', 'val'):
        os.makedirs(os.path.join(OUT, 'images', split))
        os.makedirs(os.path.join(OUT, 'labels', split))

    rows = []
    for shot, labs in sorted(LABELS.items()):
        for fi_s, e in labs.items():
            if not isinstance(e, dict) or not e.get('reviewed'):
                continue
            lines = []
            if e.get('club'):
                c = e['club']
                lines.append(f"0 {c['cx']/W:.5f} {c['cy']/H:.5f} {HEAD_BOX/W:.5f} {HEAD_BOX/H:.5f}")
            if e.get('hosel') and shot not in HOSEL_JUNK:
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

    random.Random(0).shuffle(rows)
    n_val = max(20, len(rows) // 10)
    for i, (shot, fi, p, lines) in enumerate(rows):
        split = 'val' if i < n_val else 'train'
        stem = f'{shot}_f{fi:03d}'
        shutil.copy(p, os.path.join(OUT, 'images', split, stem + '.jpg'))
        open(os.path.join(OUT, 'labels', split, stem + '.txt'), 'w').write('\n'.join(lines))

    open(os.path.join(OUT, 'data.yaml'), 'w').write(
        "path: /content/yolo_dataset\ntrain: images/train\nval: images/val\n"
        "names:\n  0: head\n  1: hosel\n  2: ball\n")

    zpath = os.path.join(TRAIN, 'yolo_dataset.zip')
    with zipfile.ZipFile(zpath, 'w', zipfile.ZIP_DEFLATED) as z:
        for root, _, files in os.walk(OUT):
            for f in files:
                fp = os.path.join(root, f)
                z.write(fp, os.path.relpath(fp, TRAIN))
    print(f'{len(rows)} labeled frames -> {OUT}  ({n_val} val)')
    print(f'upload to Colab: {zpath}')


if __name__ == '__main__':
    main()
