# Gurr Academy real footage experiments

The first recorded run measures anonymous multi-person ingestion and the CARNE ASADA no-feedback control. It processes every video in the downloaded archive, including difficult and unsupported footage. It does not establish athlete identity, event ground truth, or improved coaching accuracy.

## Recorded run on November 4 2026

The archive contains 12 MOV videos (1,743.553568 seconds; 29 minutes 3.6 seconds) and three HEIC photos. All 12 videos were processed at five sampled frames per second. Photos are excluded from motion analysis. The decoded pipeline produced 8,718 sampled frames, 10,364 person detections and 7,541 pose samples passing model presence 0.5. A person was detected in 6,209 sampled frames; 1,608 contained multiple detections. Competition footage reached eight simultaneous detections, including spectators.

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

## Local artifacts and public results

[Recorded results](gurr-20261104-results.json) contain aggregate counts, per-clip hashes, candidate gate failures, track coverage and pipeline provenance. Raw videos, pixel crops, pose coordinates, local contact sheets and draft naming UI stay outside Git. The raw files remain in the user's `CARNE ASADA` directory.

Local `athlete_tracks/1` analysis files hold `clip_sha256`, duration/fps/dimensions, sampling rate, detector/pose/pipeline hashes, observations (`time_s`, numeric `track_id`, normalized box, confidence), anonymous `pose_samples` and explicit optional assignments from metadata. A regenerated pipeline invalidates its cache. The engine never obtains coach names from those observations.

## Reproduce the run

From the repository root, with the downloaded archive extracted locally:

```sh
SV_FOOTAGE_ROOT='/path/to/Gurr Academy '
SV_RESULTS='/path/to/private-analysis'
uv venv --python 3.12 "$SV_RESULTS/venv"
uv pip install --python "$SV_RESULTS/venv/bin/python" -r tools/carne_asada/requirements.txt
curl -L --fail -o "$SV_RESULTS/yolox_nano.onnx" \
  https://github.com/Megvii-BaseDetection/YOLOX/releases/download/0.1.1rc0/yolox_nano.onnx
"$SV_RESULTS/venv/bin/python" tools/carne_asada/footage.py inventory \
  --root "$SV_FOOTAGE_ROOT" --output "$SV_RESULTS"
"$SV_RESULTS/venv/bin/python" tools/carne_asada/footage.py analyze \
  --root "$SV_FOOTAGE_ROOT" --output "$SV_RESULTS" \
  --detector "$SV_RESULTS/yolox_nano.onnx" \
  --pose apps/strathvision/assets/models/pose_landmark_full.onnx --rate 5
cd packages/analysis_engine
dart run tool/gurr_experiment.dart "$SV_RESULTS/manifest.json" \
  "$SV_RESULTS/tracks" "$SV_RESULTS/experiment.json"
```

The detector is [YOLOX Nano from Megvii's official release](https://github.com/Megvii-BaseDetection/YOLOX), licensed under Apache 2.0. Its SHA-256 is `c789161ed43c8269fcd4e67c67eeeb4e80c622da2eb296a20bc6007bd18a0b7d`. Pose uses the separately attributed MediaPipe BlazePose GHUM 3D model in `apps/strathvision/assets/models/NOTICE.md`. Inference is local through ONNX Runtime. The implement is a forearm/grip proxy; there is no independently validated axe detector in this experiment.

Tests:

```sh
"$SV_RESULTS/venv/bin/python" -m pytest tools/carne_asada/test_footage.py -q
cd packages/analysis_engine
dart analyze
dart test
```

## Further evidence required for coach learning claims

Athlete and event assignments, genuine coach feedback, and a true implement track are needed before reporting coach-specific accuracy or accepted learning improvements. Whole source clips must remain the grouping boundary for train/test splits; adjacent strokes from the same source must not leak across folds. The default minimum of 15 reference clips remains in effect. This archive has only 12 source videos before any athlete/event subdivision, so the recorded run does not manufacture a ready coach profile by duplicating clips or weakening gates.

Automatic recognition of named athletes across new footage is not implemented. A manual-label draft was preserved locally and is not delivered as fulfillment of that requirement.
