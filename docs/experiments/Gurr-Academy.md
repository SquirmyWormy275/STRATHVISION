# Gurr Academy real footage experiments

The recorded runs measure anonymous multi-person ingestion and the CARNE ASADA no-feedback control. The first run covered one archive part. All five parts of the replacement download have been verified, extracted and processed against the same committed engine. These experiments do not establish athlete identity, event ground truth, or improved coaching accuracy.

## Five-part export inventory

The Google Drive export `20261104T223331Z` consists of parts `001` through `005`, totaling 8,446,295,283 archive bytes. All 55 entries passed ZIP CRC validation during extraction; archive and extracted-file SHA-256 values are recorded locally. There are 48 MOV video files and seven HEIC photos. `Competition/IMG_8055(1).MOV` and `Competition/IMG_8055.MOV` have identical SHA-256, so analysis includes that recording once: **47 unique videos, 7,787.428656 seconds (2 h 9 min 47.4 s)**. Raw files are preserved.

| Source folder | Video files | Unique videos | Unique recording time |
|---|---:|---:|---:|
| `24-25` | 20 | 20 | 1:27:19.5 |
| `Competition` | 23 | 22 | 17:23.2 |
| `Competition/3-Board` | 4 | 4 | 12:59.2 |
| `Training/25-26` | 1 | 1 | 12:05.6 |

The longest recordings are `IMG_3747.MOV` (28:38.9), `IMG_3698.MOV` (17:54.9), `IMG_3746.MOV` (15:10.1), and `Gurr 30DEC25.mov` (12:05.6). The [public export inventory](gurr-20261104-five-part-inventory.json) contains exact durations, archive hashes and duplicate provenance. It describes the five downloaded parts; a separate remote folder listing has not been compared.

## Expanded five-part run on November 4 2026

All **47 unique videos** were decoded at five sampled frames per second. The run produced **38,941 sampled frames**, **63,317 person detections** and **50,637 pose samples** passing model presence 0.5. A person was detected in 34,319 sampled frames; 15,337 contained multiple detections. The largest observed count was 12 simultaneous detections, including spectators. Photos and the duplicate video were excluded from motion analysis.

| Candidate pack pass | Candidate strokes | Passing current pack gates | Passing track seconds | Source recordings with passing strokes | Whole corpus control |
|---|---:|---:|---:|---:|---|
| Underhand | 1,165 | 260 | 2439.75 | 36 | Good threshold met; no marks; zero edits |
| Standing block | 991 | 65 | 480.04 | 18 | Good threshold met; no marks; zero edits |

Both configurations are candidate stress tests on every recording, including 3-board footage. These are not verified event counts or technique accuracy measurements. The no-feedback controls accepted zero edits; before/after learning gains and accepted-edit explanations are unavailable because no coach marks were supplied to these controls. Diagnostic profiles remain non-ready and are not exported as coaching packages.

[Expanded results](gurr-20261104-five-part-results.json) preserve all 47 per-recording summaries, controls and engine/model hashes. The engine and inference pipeline were frozen at commit `5861e2f6835863a6dbf7e05b0d26f614d345a491`; the content-deduplication helper is recorded from `1d65770`. Twelve pose caches were reused from the earlier run and 35 new recordings were analyzed, using three workers after initial sequential processing. `pipeline_elapsed_s` sums per-recording inference times, including the reused caches; it is not the wall-clock duration of this expansion and is not a portable speed benchmark.

## Earlier subset run on November 4 2026

That archive part contains 12 MOV videos (1,743.553568 seconds; 29 minutes 3.6 seconds) and three HEIC photos. All 12 videos were processed at five sampled frames per second. Photos are excluded from motion analysis. The decoded pipeline produced 8,718 sampled frames, 10,364 person detections and 7,541 pose samples passing model presence 0.5. A person was detected in 6,209 sampled frames; 1,608 contained multiple detections. Competition footage reached eight simultaneous detections, including spectators.

| Candidate pack pass | Candidate strokes | Passing current pack gates | Passing track seconds | Whole corpus control |
|---|---:|---:|---:|---|
| Underhand | 151 | 26 | 223.24 | Good threshold met; no marks; zero edits |
| Standing block | 159 | 9 | 63.11 | Below Good; zero edits |

Every clip was tested with both event configurations as a stress test. These are **candidate pass counts**, not human-validated counts of actual underhand/standing-block strokes. The 3-board clip remains included in the corpus rather than silently excluded. Track seconds can overlap across people and must not be summed as unique recording time. Pose gaps longer than 0.6 seconds split the track before stroke detection, so an occlusion does not become usable action.

The no-feedback control runs the real `CarneSession` on measured, anonymous stroke data with no invented red/green marks. Underhand has enough pack-gated track time to pass Good but stops with `no marks`; standing block stops with `below baseline`. Both accept zero edits. There are no accepted-edit explanations, before/after learning gains, or new ready coaching packages to report. The control profiles are deliberately not marked ready and are not exported as coach packages.

The measured person-detection/pose pass took about 402 seconds on this workstation. This is one observed run, not a portable performance guarantee. JSON preserves the exact duration and source/model hashes.

## What the run exposed and changed

- An accepted exemplar edit previously cleared the entire metric map through an aliased candidate. The map is now copied before replacement, with a regression that checks the saved profile before undo.
- Merged coach reference evidence is retained in the edited profile and survives serialization.
- Production comparison and the research objective now share `prototypeMatch`: the better of the base Gaussian match and each weighted residual exemplar match. Previously an accepted exemplar could improve the research objective while doing nothing to production scoring. `distance_spreads` continues to describe displacement from the base coach center; contribution includes the exemplar match.
- Held-out protection compares with the session's initial score, preventing a chain of individually allowed five-percent regressions. Candidate exemplars participate in that check.
- `analyzeContinuousTrack` splits gaps before segmentation and keeps stroke indices unique across the resulting fragments.

The geometric tracker does not use face recognition, appearance embeddings, tattoos, or body shape to infer identity. Tracks expire after missing observations, restart at scene cuts, and avoid ambiguous overlap assignments. A person track is an observation link within a shot, not a named athlete or proof that the person is competing.

## Dataset completeness

The earlier `203933Z` download had one part, containing 12 videos and three photos. It was replaced locally by the complete five-part `223331Z` download described above. All 12 previously processed video hashes occur in the expanded export. The earlier result remains a historical subset and has not been relabeled as a full-export run.

The five-part inventory distinguishes `downloaded_export_complete: true` from unverified remote-collection completeness. Analysis deduplicates by video content hash before counting frames or aggregating controls. The expanded run uses committed engine snapshot `5861e2f6835863a6dbf7e05b0d26f614d345a491`, excluding concurrent changes in the shared worktree.

## Local artifacts and public results

[Expanded results](gurr-20261104-five-part-results.json) and the unchanged [earlier subset results](gurr-20261104-results.json) contain aggregate counts, per-clip hashes, candidate gate failures, track coverage and pipeline provenance. Raw videos, pixel crops, pose coordinates, local contact sheets and draft naming UI stay outside Git. The raw files remain in the user's `CARNE ASADA` directory.

Local `athlete_tracks/1` analysis files hold `clip_sha256`, duration/fps/dimensions, sampling rate, detector/pose/pipeline hashes, observations (`time_s`, numeric `track_id`, normalized box, confidence), anonymous `pose_samples` and explicit optional assignments from metadata. A regenerated pipeline invalidates its cache. The engine never obtains coach names from those observations.

## Reproduce the run

From the current repository root, with all five archives extracted locally. For the recorded numbers, point `SV_ENGINE_ROOT` at a separate checkout of engine commit `5861e2f`; the current repository supplies the deduplication helper:

```sh
SV_ENGINE_ROOT='/path/to/checkout-at-5861e2f'
SV_FOOTAGE_ROOT='/path/to/Gurr Academy '
SV_RESULTS='/path/to/private-analysis'
uv venv --python 3.12 "$SV_RESULTS/venv"
uv pip install --python "$SV_RESULTS/venv/bin/python" -r tools/carne_asada/requirements.txt
curl -L --fail -o "$SV_RESULTS/yolox_nano.onnx" \
  https://github.com/Megvii-BaseDetection/YOLOX/releases/download/0.1.1rc0/yolox_nano.onnx
"$SV_RESULTS/venv/bin/python" "$SV_ENGINE_ROOT/tools/carne_asada/footage.py" inventory \
  --root "$SV_FOOTAGE_ROOT" --output "$SV_RESULTS/source-inventory"
"$SV_RESULTS/venv/bin/python" tools/carne_asada/deduplicate.py \
  "$SV_RESULTS/source-inventory/manifest.json" "$SV_RESULTS/manifest.json"
"$SV_RESULTS/venv/bin/python" "$SV_ENGINE_ROOT/tools/carne_asada/footage.py" analyze \
  --root "$SV_FOOTAGE_ROOT" --output "$SV_RESULTS" \
  --detector "$SV_RESULTS/yolox_nano.onnx" \
  --pose "$SV_ENGINE_ROOT/apps/strathvision/assets/models/pose_landmark_full.onnx" --rate 5
cd "$SV_ENGINE_ROOT/packages/analysis_engine"
dart pub get
dart run tool/gurr_experiment.dart "$SV_RESULTS/manifest.json" \
  "$SV_RESULTS/tracks" "$SV_RESULTS/experiment.json"
```

The detector is [YOLOX Nano from Megvii's official release](https://github.com/Megvii-BaseDetection/YOLOX), licensed under Apache 2.0. Its SHA-256 is `c789161ed43c8269fcd4e67c67eeeb4e80c622da2eb296a20bc6007bd18a0b7d`. Pose uses the separately attributed MediaPipe BlazePose GHUM 3D model in `apps/strathvision/assets/models/NOTICE.md`. Inference is local through ONNX Runtime. The implement is a forearm/grip proxy; there is no independently validated axe detector in this experiment.

Tests:

```sh
"$SV_RESULTS/venv/bin/python" -m pytest tools/carne_asada -q
cd packages/analysis_engine
dart analyze
dart test
```

## Further evidence required for coach learning claims

Athlete and event assignments, genuine coach feedback, and a true implement track are needed before reporting coach-specific accuracy or accepted learning improvements. Whole source recordings must remain the grouping boundary for train/test splits; duplicate downloads and adjacent strokes from the same source must not leak across folds. The default minimum of 15 reference clips remains in effect. The expanded export has 47 unique source videos before athlete/event subdivision; that total alone does not establish 15 clean references for any particular coach and event. No ready coach profile is manufactured by duplicating clips or weakening gates.

Automatic recognition of named athletes across new footage is not implemented. A manual-label draft was preserved locally and is not delivered as fulfillment of that requirement.
