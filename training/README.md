# TrueCarry Training Pipeline

GPU/training work lives **off-repo on Google Drive + Colab Pro**. This folder holds the index,
notebooks, and scripts; results flow back into the app repo (`Resources/Models/`).

## Where things live
- **Frames + Garmin CSVs** — already on Drive (flat, folder `0AB-hpMM103nJUk9PVA`), uploaded by the
  app + by you. `MANIFEST.json` maps each session → its Drive file IDs (nothing needs moving).
- **Drive project folder** `TrueCarry-Training/` (`145BzESan3TtLW71h0_alTmse4kEYmMqy`):
  `notebooks/` (Colab), `results/` (model outputs), `features/` (Swift feature exports).

## Pipeline (Swift extracts → Colab trains)
Colab (Python) can't run the tracker (Swift), so:
1. **Extract features** (Swift): run the replay harness over a session's frames → per-frame
   `(shot_id, t, u, v, diameter, ball_speed)` CSV. See `extract_features.md`.
2. **Upload** the feature CSV to Drive `TrueCarry-Training/features/`.
3. **Train** (Colab): `notebooks/truecarry_pipeline.ipynb` loads features + Garmin by ID, pairs by
   timestamp, fits VLA, writes the model to `results/`.
4. **Land**: download the trained model into the app repo `Resources/Models/`.

## The VLA problem this is solving
TrueCarry VLA reads **27% of Garmin truth on high launches, 67% on low** — a nonlinear under-read.
Lever: feed the growth-VLA the **720 subpixel minor-axis diameter**, not the 360 bbox. 168 Garmin
shots exist across 10 sessions; only ~13 are 720px + tracked + paired today (fast shots blurred at
1/1001 in the dark). The daylight 500-shot session is the one that yields a real trainable set.
