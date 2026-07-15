#!/usr/bin/env python3
"""TrueCarry replay viewer — renders live-pipeline replay results with overlays.

The tracking is NEVER done here: the Swift live pipeline (LiveParityTestRunner, run
headlessly in the iOS simulator with TC_REPLAY_EXPORTS=1) writes a replay.json per shot;
this GUI only draws frames + overlays. Zero third-party deps (tkinter + Tk 8.6+ PNG).

Usage:
    python3 tools/replay_viewer.py --dir <folder containing shot_*/ dirs>

Each shot dir needs frame_XXX.png files plus a replay.json (copied from the app
container's Documents/ReplayResults/<shot>.json).

Keys:  ←/→ step frames · space play/pause · [ / ] previous/next shot
"""

import argparse
import json
import os
import sys
import tkinter as tk
from tkinter import ttk

SCALE = 4          # integer zoom of the 360px-wide frames
FPS_PLAYBACK = 10  # playback speed


def load_shots(root_dir):
    shots = []
    for name in sorted(os.listdir(root_dir)):
        d = os.path.join(root_dir, name)
        j = os.path.join(d, "replay.json")
        if not (os.path.isdir(d) and os.path.exists(j)):
            continue
        frames = sorted(f for f in os.listdir(d) if f.startswith("frame_") and f.endswith(".png"))
        if not frames:
            continue
        with open(j) as fh:
            data = json.load(fh)
        shots.append({"name": name, "dir": d, "frames": frames, "data": data})
    return shots


class Viewer:
    def __init__(self, root, shots):
        self.root = root
        self.shots = shots
        self.shot_i = 0
        self.frame_i = 0
        self.playing = False
        self.photo = None
        self._img_cache = {}

        root.title("TrueCarry Replay Viewer — live-pipeline results")
        root.configure(bg="#111")

        top = tk.Frame(root, bg="#111")
        top.pack(fill="x", padx=8, pady=6)
        self.shot_var = tk.StringVar()
        self.shot_menu = ttk.Combobox(top, textvariable=self.shot_var, state="readonly",
                                      values=[s["name"] for s in shots], width=34)
        self.shot_menu.pack(side="left")
        self.shot_menu.bind("<<ComboboxSelected>>", lambda e: self.select_shot(self.shot_menu.current()))
        self.verdict_lbl = tk.Label(top, bg="#111", fg="#7f7", font=("Menlo", 12, "bold"))
        self.verdict_lbl.pack(side="left", padx=14)

        self.canvas = tk.Canvas(root, bg="black", highlightthickness=0)
        self.canvas.pack(padx=8, pady=2)

        info = tk.Frame(root, bg="#111")
        info.pack(fill="x", padx=8)
        self.frame_lbl = tk.Label(info, bg="#111", fg="#ddd", font=("Menlo", 12), anchor="w", justify="left")
        self.frame_lbl.pack(side="left")

        ctrl = tk.Frame(root, bg="#111")
        ctrl.pack(fill="x", padx=8, pady=6)
        tk.Button(ctrl, text="◀", command=lambda: self.step(-1)).pack(side="left")
        self.play_btn = tk.Button(ctrl, text="▶ Play", command=self.toggle_play)
        self.play_btn.pack(side="left", padx=4)
        tk.Button(ctrl, text="▶", command=lambda: self.step(1)).pack(side="left")
        self.slider = tk.Scale(ctrl, from_=0, to=40, orient="horizontal", showvalue=False,
                               command=self.on_slider, length=760, bg="#111", fg="#ddd",
                               troughcolor="#333", highlightthickness=0)
        self.slider.pack(side="left", fill="x", expand=True, padx=10)

        self.metrics_lbl = tk.Label(root, bg="#111", fg="#bbb", font=("Menlo", 11),
                                    anchor="w", justify="left")
        self.metrics_lbl.pack(fill="x", padx=10, pady=(0, 8))

        root.bind("<Left>",  lambda e: self.step(-1))
        root.bind("<Right>", lambda e: self.step(1))
        root.bind("<space>", lambda e: self.toggle_play())
        root.bind("[", lambda e: self.select_shot((self.shot_i - 1) % len(self.shots)))
        root.bind("]", lambda e: self.select_shot((self.shot_i + 1) % len(self.shots)))

        self.select_shot(0)

    # ── shot / frame handling ────────────────────────────────────────────────
    def select_shot(self, i):
        self.shot_i = i
        self.shot_menu.current(i)
        shot = self.shots[i]
        self._img_cache = {}
        self.frame_i = max(0, shot["data"].get("impactDetected", 0))
        self.slider.configure(to=len(shot["frames"]) - 1)
        d = shot["data"]
        verdict = d.get("verdict", "?")
        color = "#7f7" if verdict.startswith("accepted") else "#f77"
        auto = " · auto-lock" if d.get("lockAutoDerived") else ""
        self.verdict_lbl.configure(text=f"{verdict}{auto}", fg=color)
        m = d.get("metrics", {})
        def fmt(v, suf=""):
            return "—" if v is None else (f"{v:.1f}{suf}" if isinstance(v, float) else f"{v}{suf}")
        self.metrics_lbl.configure(text=(
            f"impact: detected f{d.get('impactDetected')} (fallback f{d.get('impactFallback')}, {d.get('impactReason')})   "
            f"ball {fmt(m.get('ballSpeedMph'),' mph')}   HLA {m.get('hlaDisplay','—')}   "
            f"VLA {fmt(m.get('vlaDegrees'),'°')}   carry {fmt(m.get('carryYards'),' yd')}   "
            f"total {fmt(m.get('totalYards'),' yd')}   club {fmt(m.get('clubSpeedMph'),' mph')}   "
            f"ballPts {m.get('ballPoints','—')}"))
        self.render()

    def step(self, dz):
        shot = self.shots[self.shot_i]
        self.frame_i = max(0, min(len(shot["frames"]) - 1, self.frame_i + dz))
        self.render()

    def on_slider(self, val):
        self.frame_i = int(val)
        self.render()

    def toggle_play(self):
        self.playing = not self.playing
        self.play_btn.configure(text="⏸ Pause" if self.playing else "▶ Play")
        if self.playing:
            self.tick()

    def tick(self):
        if not self.playing:
            return
        shot = self.shots[self.shot_i]
        self.frame_i = (self.frame_i + 1) % len(shot["frames"])
        self.render()
        self.root.after(int(1000 / FPS_PLAYBACK), self.tick)

    # ── drawing ──────────────────────────────────────────────────────────────
    def image_for(self, shot, i):
        if i not in self._img_cache:
            img = tk.PhotoImage(file=os.path.join(shot["dir"], shot["frames"][i]))
            self._img_cache[i] = img.zoom(SCALE)
        return self._img_cache[i]

    def render(self):
        shot = self.shots[self.shot_i]
        data = shot["data"]
        self.slider.set(self.frame_i)
        img = self.image_for(shot, self.frame_i)
        W, H = img.width(), img.height()
        c = self.canvas
        c.configure(width=W, height=H)
        c.delete("all")
        c.create_image(0, 0, anchor="nw", image=img)
        self.photo = img  # keep reference

        def px(nx, ny):
            return nx * W, ny * H

        def draw_rect(r, color, dash=None, width=2, label=None):
            if not isinstance(r, dict):
                return
            x0, y0 = px(r["x"], r["y"])
            x1, y1 = px(r["x"] + r["w"], r["y"] + r["h"])
            c.create_rectangle(x0, y0, x1, y1, outline=color, dash=dash, width=width)
            if label:
                c.create_text(x0 + 3, y0 - 9, text=label, fill=color, anchor="w", font=("Menlo", 10))

        # Static geometry
        draw_rect(data.get("lockedBallRect"), "#ffffff", dash=(4, 3), label="lock")
        draw_rect(data.get("lockedImpactROI"), "#ffaa33", dash=(2, 4), label="impact ROI")

        frames = {f["i"]: f for f in data.get("frames", [])}
        clubs = {cx["i"]: cx for cx in data.get("club", [])}
        impact = data.get("impactDetected", 0)

        # Search ROI for the current frame
        fcur = frames.get(self.frame_i, {})
        if isinstance(fcur.get("roi"), dict):
            draw_rect(fcur["roi"], "#557788", dash=(1, 5), width=1, label="search")

        # Ball track: full trajectory as connected dots (past=solid cyan, future=dim)
        pts = [(i, f) for i, f in sorted(frames.items()) if "cx" in f]
        for k in range(1, len(pts)):
            (i0, f0), (i1, f1) = pts[k - 1], pts[k]
            if i1 <= impact:
                continue
            x0, y0 = px(f0["cx"], f0["cy"])
            x1, y1 = px(f1["cx"], f1["cy"])
            c.create_line(x0, y0, x1, y1, fill="#00ddff", width=2)
        for i, f in pts:
            x, y = px(f["cx"], f["cy"])
            r = max(3, f.get("d", 0.02) * W / 2)
            if i == self.frame_i:
                c.create_oval(x - r, y - r, x + r, y + r, outline="#33ff66", width=3)
                c.create_text(x, y - r - 12, text=f"f{i} conf={f.get('conf', 0):.2f}",
                              fill="#33ff66", font=("Menlo", 11, "bold"))
            elif i <= impact:
                c.create_oval(x - 3, y - 3, x + 3, y + 3, outline="#888888", width=1)
            else:
                fill = "#00ddff" if i < self.frame_i else "#005566"
                c.create_oval(x - 4, y - 4, x + 4, y + 4, fill=fill, outline="")

        # Club overlay for the current frame
        club = clubs.get(self.frame_i)
        if club:
            draw_rect(club.get("box"), "#ff8800", width=2, label="club")
            if "cx" in club:
                x, y = px(club["cx"], club["cy"])
                c.create_line(x - 7, y, x + 7, y, fill="#ff8800", width=2)
                c.create_line(x, y - 7, x, y + 7, fill="#ff8800", width=2)
            if "lex" in club:
                x, y = px(club["lex"], club["ley"])
                c.create_oval(x - 4, y - 4, x + 4, y + 4, outline="#ffcc00", width=2)

        # Frame status line
        phase = "PRE" if self.frame_i < impact else ("IMPACT" if self.frame_i == impact else "POST")
        reason = fcur.get("reason", "—")
        rej = fcur.get("rej")
        status = f"frame {self.frame_i:02d}  [{phase}]   ball: {reason}"
        if rej:
            status += f"   rej: {rej}"
        if club:
            status += f"   club: {club.get('mode', '?')} conf={club.get('conf', 0):.2f}"
        self.frame_lbl.configure(text=status)

        c.create_text(8, H - 12, anchor="w", fill="#ffffff", font=("Menlo", 11),
                      text=f"{shot['name']}  ·  f{self.frame_i:02d}/{len(shot['frames']) - 1}")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir", required=True, help="folder containing shot_*/ dirs (frames + replay.json)")
    args = ap.parse_args()
    shots = load_shots(args.dir)
    if not shots:
        sys.exit(f"no shots with replay.json found in {args.dir}")
    root = tk.Tk()
    Viewer(root, shots)
    root.mainloop()


if __name__ == "__main__":
    main()
