# Gurr accuracy round 2

This work measures the current committed standing-block engine, brings anonymous competitor tracking into the app, and tests a separately trained axe-head detector. A detection is an observation of an object in an image; it is not a named-person identity or an independently verified coaching judgment.

## Fixed protocol

- Pin the engine at `ce649ed2cc00c81703f0bc5b35504d06cf807d79` for the new baseline. Replay the existing frozen pose predictions and score the original pilot/follow-up separately. These already-opened references are diagnostic comparisons, not a new holdout.
- Select twelve previously unused source recordings, six from `24-25` and six from `Competition`, excluding the unsupported three-board event. Sort eligible videos by content SHA-256; take the first six in each folder and assign alternating train/validation/test groups, giving four sources per group. Exclude all thirteen source hashes from the first pilot and follow-up. Duplicate content stays in one group.
- Review only source images before inference. Choose an eight-second window with visible movement, or explicitly record an idle/occluded case. Record the initial spatial target, orientation, visible axe-head boxes, optional visible grip points, contact intervals, and uncertainty. Do not infer invisible contacts or label timing annotations as good/bad technique.
- Train a compact local image detector on the training sources only. Use validation sources for threshold selection. Freeze code, model, settings and reference hashes before test inference. Report object detection precision/recall, localization error, false detections and contact timing separately. Preserve all failures.
- A small CPU HOG/linear-SVM detector is the first reproducible axe prototype. It observes image texture/edges rather than synthesizing an axe from body joints. Its performance is an experiment; passing app unit tests does not qualify it for coaching or 3D implement metrics.
- Keep per-frame pixels and video private. Publish annotations, model coefficients, provenance, aggregate/per-window results, reproduction commands and limitations. Original experiment artifacts remain unchanged.
- App person detection/orientation is Claude's active scope. Codex owns this benchmark, the axe prototype, CARNE integration and feedback evaluation. Use explicit-path commits and preserve concurrent files.

## Genuine feedback

The user confirmed that technique judgments have not been created or field-tested yet. Build the local collection/review workflow and evaluator; draft entries remain unlabelled until someone supplies and reviews an actual judgment. Learning evaluation needs source/stroke provenance, separate fitting and evaluation recordings, and the existing readiness/hull gates. Empty or unreviewed feedback must produce a clear pending result, never fabricated labels or a claimed learning improvement.

## Results

The pinned engine replay uses exactly the earlier pose predictions. Target selection is therefore unchanged. These are diagnostic scores on already-opened labels:

| Existing set | Contact matches | Extra predictions | Missed contacts |
|---|---:|---:|---:|
| Original development | 3/7 | 0 | 4 |
| Original test | 1/15 | 2 | 14 |
| Three-source follow-up | 3/3 | 1 | 0 |

The original test includes one idle false positive. The narrow follow-up's matched contacts still average 0.206 s midpoint error. Results: [development](evaluation/round2/ce649ed-pilot-development.json), [original test](evaluation/round2/ce649ed-pilot-test.json), [follow-up](evaluation/round2/ce649ed-followup-test.json). The revised standing-block rules help some clear training footage but do not establish broad contact detection.

The first trained HOG prototype used ten visible axe-head examples (150 jittered positive patches, 1,555 background patches). It matched 0/9 validation heads; validation threshold selection chose abstention. Frozen test result: 0/16 visible heads, no false predictions, with 16 uncertain frames unrated. This is a failed detector, retained as a negative baseline rather than promoted into coaching.

The second prototype transferred a COCO-pretrained TorchVision SSDLite MobileNet V3 detector, replaced its classification head with axe/background classes, and fitted the detection heads on the same training sources. Fixed settings: seed 365, 400 optimizer steps, batch 4, AdamW at 0.001, frozen backbone, random positive/background crops and horizontal flips. Validation chooses the detection-score threshold; no test data selects weights or parameters. The four newly reserved [test sources](evaluation/round2/transfer-test-sources.json) replace the already-opened first axe test. Its image observations remain separate from 3D implement metrics and coach judgments.


The SSDLite prototype also matched **0/9 validation heads**. Its validation-selected threshold rejected all test predictions: **0/8 visible heads**, zero extras and eight misses, with 24 uncertain frames unrated. The two competition test views could not be labelled confidently, so visible-head coverage comes from just two training-view recordings. Both experiments failed. Zero extras from abstaining is not successful detection; localization error is undefined when no heads match. Neither detector drives production implement metrics or contact timing.

| Experiment | Training data | Validation | Frozen test | Evidence |
|---|---|---|---|---|
| HOG + linear hinge classifier | 10 visible frames, 150 jittered positives, 1,555 background patches | 0/9 | 0/16; 16 unrated | [model](evaluation/round2/axe-model.json), [validation](evaluation/round2/axe-validation.json), [test](evaluation/round2/axe-test.json) |
| Pretrained SSDLite, fitted heads | Same 10 visible training frames | 0/9 | 0/8; 24 unrated | [model metadata](evaluation/round2/axe-transfer-model.json), [freeze](evaluation/round2/axe-transfer-freeze.json), [validation](evaluation/round2/axe-transfer-validation.json), [test](evaluation/round2/axe-transfer-test.json) |

The [first references](evaluation/round2/axe-reference.json) and [transfer references](evaluation/round2/axe-transfer-reference.json) contain coarse boxes from one visual reviewer. Only confidently visible axe heads are scored; uncertainty is not a negative label. Inputs use a manually chosen initial search region, eight sparse image samples per recording and a maximum image edge of 960 pixels. Training pixels use the original FFmpeg PNG conversion without HDR tone mapping. Tiny heads, blur, occlusion, limited independent positive examples and that preprocessing restrict interpretation. The browser review videos use a separate HDR-corrected conversion; they do not replace the frozen training pixels.

Annotation/code commits precede fitting, and model commits precede test inference: `f6a21cc` → `1b090c4` for HOG; reserved fresh sources in `b11924d`, then model/reference/code freeze `5b236c6` for SSDLite. Opened test results were not used to tune these models. The [published detector state](evaluation/round2/axe-transfer.pt) is retained for inference reproduction. Frozen source hashes deliberately reject changed code or references.

## Application and feedback delivery

CARNE consumes the app's person detector and selected-track API. A four-second selection preview lets uncertain long recordings ask for a competitor before processing the whole video. **Choose competitor** and **Change competitor** open the spatial picker; a correction replaces that source's measurements and requires refreshed feedback. Copies still count once. The desktop sampling budget retains up to 30 samples/second across the longest Gurr recording rather than thinning it below two samples/second. This tracks a selected person within a recording; automatic named-athlete identity matching remains open.

The [local review workflow](../FEEDBACK_REVIEW.md) is implemented and verified with private Gurr playback. Its twelve real tasks start unlabelled. A separate synthetic packet exercises saving/export, repeated strokes and narrow layouts; synthetic labels never enter the real packet. Measured CARNE exports support a bounded learning replay with disjoint source recordings and unchanged base-profile gates. The [real feedback result](evaluation/round2/genuine-feedback-status.json) remains pending: zero judgments and zero edits. The collection/evaluation mechanism is delivered; learning effectiveness has not been field-tested.

## Reproduce the image experiments

Use the private Python 3.12 research environment described in [Gurr Academy](Gurr-Academy.md#reproduce-the-run). SSDLite used Torch 2.10.0+cu128 / TorchVision 0.25.0+cu128 on the RTX 4070 Laptop GPU; [requirements-training.txt](../../tools/carne_asada/requirements-training.txt) records the complete environment. CUDA wheels come from the official PyTorch cu128 index. GPU fitting uses deterministic settings with warnings enabled, so newly fitted weights need not be byte-identical; use the committed state for the frozen test.

From the repository root, set private paths and prepare the frozen image samples:

```sh
SV_PY='/path/to/private-analysis/venv/bin/python'
SV_ML_PY='/path/to/private-analysis/ml-venv/bin/python'
SV_FRAMES='/path/to/private-analysis/round2-frames'
SV_RESULTS='/path/to/private-analysis/reproduced-results'
SV_ARTIFACTS='docs/experiments/evaluation/round2'
mkdir -p "$SV_RESULTS"
"$SV_PY" tools/carne_asada/axe_data.py "$SV_ARTIFACTS/axe-reference.json" \
  --root '/path/to/Gurr Academy ' --frames "$SV_FRAMES"
"$SV_PY" tools/carne_asada/axe_data.py "$SV_ARTIFACTS/axe-transfer-reference.json" \
  --root '/path/to/Gurr Academy ' --frames "$SV_FRAMES"
"$SV_PY" tools/carne_asada/axe_detector.py test \
  --reference "$SV_ARTIFACTS/axe-reference.json" --frames "$SV_FRAMES" \
  --model "$SV_ARTIFACTS/axe-model.json" --output "$SV_RESULTS/hog-test.json"
"$SV_ML_PY" tools/carne_asada/axe_transfer.py test \
  --reference "$SV_ARTIFACTS/axe-transfer-reference.json" --frames "$SV_FRAMES" \
  --model "$SV_ARTIFACTS/axe-transfer.pt" --metadata "$SV_ARTIFACTS/axe-transfer-model.json" \
  --freeze "$SV_ARTIFACTS/axe-transfer-freeze.json" --output "$SV_RESULTS/transfer-test.json"
```

The `fit` actions document and implement training; write any refitted models/results to new private paths and keep the published failures intact. Private images, video and per-frame poses are not repository artifacts.


## Reproduce native diagnostics

The native harness runs the real Flutter person/pose pipeline on the thirteen existing eight-second pilot/follow-up windows, automatically selecting competitors. Scoring references are used only after inference. Ambiguity/orientation deferrals produce no contacts and count as missed observations. Torso-centre error is normalized by image diagonal and differs from the original detector-box checkpoint coverage metric. These opened references are diagnostic; this is not another independent holdout. Person selection, HDR handling, sampling and engine revision differ from the saved-pose baseline, so their contributions cannot be isolated from this comparison.

Use an isolated checkout of `9430b3d` to reproduce the native runtime under test (`77c95b3` plus the diagnostic harness/preflight). Generate Drift code as described in the [app setup](../../apps/strathvision/README.md#setup). From that checkout's repository root:

```sh
SV_NATIVE='/path/to/private-analysis/native-windows'
"$SV_PY" tools/carne_asada/native_benchmark.py prepare \
  --references docs/experiments/evaluation --root '/path/to/Gurr Academy ' \
  --directory "$SV_NATIVE"
cd apps/strathvision
flutter test --no-pub integration_test/carne_gurr_benchmark_test.dart -d linux \
  --dart-define=WINDOWS="$SV_NATIVE/inputs.json" \
  --dart-define=OUT="$SV_NATIVE/native-result.json" \
  --dart-define=STRATHVISION_REVISION=77c95b3208adf43d4e81b07cc133eb658646e166
cd ../..
"$SV_PY" tools/carne_asada/native_benchmark.py score \
  --references docs/experiments/evaluation --native "$SV_NATIVE/native-result.json" \
  --repo "$PWD" --output "$SV_NATIVE/native-score.json"
```

Preparation verifies source hashes, preserves HDR transfer metadata and scales the longest image edge to 960 pixels in lossless FFV1 windows. The native app performs its own HDR tone mapping/orientation. This establishes neither full-recording throughput nor real-world coaching accuracy. Partial or duplicate-window runs cannot be published by the scorer. Published source/model hashes identify the exact tested runtime; concurrent later changes require separate validation.
