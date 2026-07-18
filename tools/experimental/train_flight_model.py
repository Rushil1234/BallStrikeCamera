#!/usr/bin/env python3
"""Retrain flight_model.json (carry + rollout ridge) on the TopTracer session.

Same JSON contract FlightModelPredictor.swift already parses — features, means, stds,
imputationMedians, coefficients, intercept — so deployment is a bundled-file swap.
Pure stdlib (no numpy): 119 rows x <=9 features solved by Gaussian elimination.
5-fold CV MAE reported; final model fit on all rows.
"""
import csv
import json
import math
import random
from datetime import datetime, timezone

CSVS = ["/Users/noahtobias/Downloads/BallStrikeCamera/swingsync-2026-07-12.csv",
        "/Users/noahtobias/Downloads/BallStrikeCamera/swingsync-2026-07-16.csv",
        "/Users/noahtobias/Downloads/BallStrikeCamera/swingsync-2026-07-17.csv"]
OUT = "/Users/noahtobias/Downloads/BallStrikeCamera/BallStrikeCamera/Resources/Models/flight_model.json"
LAMBDA = 1.0

rows = []
for _csv in CSVS:
  for r in csv.DictReader(open(_csv)):
    try:
        bs = float(r["ballSpeed"]); vla = float(r["launchAngle"])
        carry = float(r["carry"]); total = float(r["total"])
    except (ValueError, KeyError):
        continue
    if not (5 <= bs <= 220 and 0 < vla < 60 and 0 < carry <= total <= 400):
        continue
    spin = None
    try:
        spin = float(r["backSpin"])
    except (ValueError, TypeError):
        pass
    rows.append({"ball_speed": bs, "vla": vla, "carry": carry,
                 "roll": total - carry, "backspin": spin})
print(f"usable shots: {len(rows)}")

def derive(d):
    v = d["ball_speed"]; a = d["vla"]; ar = math.radians(a)
    mps = v * 0.44704
    return {
        "ball_speed": v, "vla": a,
        "ball_speed_sq": v * v, "vla_sq": a * a,
        "speed_times_vla": v * a, "sin_2vla": math.sin(2 * ar),
        "ideal_carry_yards": (mps * mps * math.sin(2 * ar)) / 9.80665 * 1.09361,
    }

CARRY_F = ["ball_speed", "vla", "ball_speed_sq", "vla_sq", "speed_times_vla",
           "sin_2vla", "ideal_carry_yards"]
ROLL_F = CARRY_F + ["carry_yards", "backspin"]

def feature_rows(data, feats, with_carry_truth):
    X = []
    for d in data:
        f = derive(d)
        f["carry_yards"] = d["carry"] if with_carry_truth else None
        f["backspin"] = d["backspin"]
        X.append([f.get(k) for k in feats])
    return X

def fit_ridge(X, y, feats, lam=LAMBDA):
    n, m = len(X), len(feats)
    med = []
    for j in range(m):
        vals = sorted(v for r in X for v in [r[j]] if v is not None)
        med.append(vals[len(vals) // 2] if vals else 0.0)
    Xi = [[r[j] if r[j] is not None else med[j] for j in range(m)] for r in X]
    mu = [sum(r[j] for r in Xi) / n for j in range(m)]
    sd = [max(math.sqrt(sum((r[j] - mu[j]) ** 2 for r in Xi) / n), 1e-10) for j in range(m)]
    Z = [[(r[j] - mu[j]) / sd[j] for j in range(m)] for r in Xi]
    ym = sum(y) / n
    # normal equations (Z'Z + lam I) w = Z'(y - ym)
    A = [[sum(Z[i][a] * Z[i][b] for i in range(n)) + (lam if a == b else 0.0)
          for b in range(m)] for a in range(m)]
    B = [sum(Z[i][a] * (y[i] - ym) for i in range(n)) for a in range(m)]
    # gaussian elimination with partial pivoting
    for col in range(m):
        piv = max(range(col, m), key=lambda r_: abs(A[r_][col]))
        A[col], A[piv] = A[piv], A[col]
        B[col], B[piv] = B[piv], B[col]
        for r_ in range(col + 1, m):
            f_ = A[r_][col] / A[col][col]
            for c_ in range(col, m):
                A[r_][c_] -= f_ * A[col][c_]
            B[r_] -= f_ * B[col]
    w = [0.0] * m
    for r_ in range(m - 1, -1, -1):
        w[r_] = (B[r_] - sum(A[r_][c_] * w[c_] for c_ in range(r_ + 1, m))) / A[r_][r_]
    return {"w": w, "mu": mu, "sd": sd, "med": med, "intercept": ym, "feats": feats}

def predict(model, xrow):
    z = model["intercept"]
    for j, v in enumerate(xrow):
        vv = v if v is not None else model["med"][j]
        z += model["w"][j] * (vv - model["mu"][j]) / model["sd"][j]
    return z

# ---- 5-fold CV ----
random.seed(20260715)
idx = list(range(len(rows)))
random.shuffle(idx)
folds = [idx[i::5] for i in range(5)]
carry_err, roll_err, total_err = [], [], []
for k in range(5):
    test = set(folds[k])
    tr = [rows[i] for i in idx if i not in test]
    te = [rows[i] for i in idx if i in test]
    cm = fit_ridge(feature_rows(tr, CARRY_F, False), [d["carry"] for d in tr], CARRY_F)
    rm = fit_ridge(feature_rows(tr, ROLL_F, True), [d["roll"] for d in tr], ROLL_F)
    for d in te:
        Xc = feature_rows([d], CARRY_F, False)[0]
        pc = max(predict(cm, Xc), 0)
        # inference-faithful: rollout uses the PREDICTED carry, like the app does
        f = derive(d); f["carry_yards"] = pc; f["backspin"] = d["backspin"]
        pr = max(predict(rm, [f.get(kk) for kk in ROLL_F]), 0)
        carry_err.append(abs(pc - d["carry"]))
        roll_err.append(abs(pr - d["roll"]))
        total_err.append(abs((pc + pr) - (d["carry"] + d["roll"])))

def mae(v): return sum(v) / len(v)
print(f"5-fold CV — carry MAE {mae(carry_err):.1f} yd | rollout MAE {mae(roll_err):.1f} yd | total MAE {mae(total_err):.1f} yd")

# ---- final fit on all data ----
cm = fit_ridge(feature_rows(rows, CARRY_F, False), [d["carry"] for d in rows], CARRY_F)
rm = fit_ridge(feature_rows(rows, ROLL_F, True), [d["roll"] for d in rows], ROLL_F)

def to_json(model):
    return {
        "features": model["feats"],
        "means": dict(zip(model["feats"], model["mu"])),
        "stds": dict(zip(model["feats"], model["sd"])),
        "imputationMedians": dict(zip(model["feats"], model["med"])),
        "coefficients": dict(zip(model["feats"], model["w"])),
        "intercept": model["intercept"],
    }

out = {
    "version": "toptracer-v2-20260718",
    "createdAt": datetime.now(timezone.utc).isoformat(),
    "sourceCsv": "swingsync 2026-07-12 + 07-16 + 07-17 (TopTracer, 289 range shots, full bag)",
    "carryModel": to_json(cm),
    "rollModel": to_json(rm),
    "metrics": {"carry_mae": round(mae(carry_err), 2), "roll_mae": round(mae(roll_err), 2),
                "total_mae": round(mae(total_err), 2), "n_shots": float(len(rows))},
}
json.dump(out, open(OUT, "w"), indent=1)
print("wrote", OUT)
