# Additional event and early-training footage

This experiment uses the additional footage supplied on 2026-11-05 to train and evaluate visible axe-head localization. It is in progress; no new accuracy or coaching improvement is claimed yet.

## Corpus and frozen split

All four ZIPs in the private `New Training Footage/` folder were read to EOF with member CRC checks, archive/member SHA-256 records and stable-file checks. They contain 56 unique video payloads and one photo. One video is byte-identical to the earlier Gurr corpus (`IMG_8024.MOV`), leaving **55 new videos**. The supplied video duration, including that duplicate, is **4,914.657592 seconds**. Original archives remain unchanged; extracted media, frames and contact sheets stay private.

The [source plan](evaluation/new-footage/source-plan.json) was fixed before fitting or opening test pixels:

| Partition | New videos | Fixed temporal samples |
|---|---:|---:|
| Training | 36 | 144 |
| Validation | 13 | 52 |
| Test | 6 | 24 |

Whole local capture dates stay together. When available, the QuickTime creation-date offset defines the calendar day, avoiding UTC midnight splitting a daytime event. Dates already present in the previously inspected Gurr corpus are excluded from validation/test; undated footage stays in training. A seeded hash selects three new capture days each for validation and test. Adjacent frames, renamed copies and exact duplicates cannot cross partitions. The public plan uses capture-group hashes rather than exact dates/timestamps.

Four samples per video (15%, 35%, 55%, 75% of its duration) span each recording. This is a sampled-image training study, distinct from the earlier [full-duration native scan](Gurr-Population.md). Capture dates are metadata proxies, not verified session boundaries; athletes and venues can recur across dates. Evaluation is not athlete-independent.

## Supervision and experiment boundaries

Engineering annotations describe visible axe-head boxes and explicit visibility states. Blurred, hidden and uncertain heads remain unrated. The user's description of early training is context, not a red/green technique judgment. Genuine coaching feedback remains a separate first-review workflow.

Fifty-four of the 56 supplied videos are HDR. Frame preparation applies the native study's Hable tone mapping before 1,600-pixel-edge image export. The detector receives a broad, manually supplied anonymous athlete ROI at inference. These regions include the body, block and swing area; they are not axe-tight ground-truth crops. This experiment does not identify named athletes or automatically select everyone in a heat. Detector fitting uses training pixels only; validation controls threshold/checkpoint selection. Test pixels remain unopened until a separate model freeze exists, and no test result will be used to tune that model.

The new candidate uses a COCO-pretrained Faster R-CNN/ResNet-50 FPN v2 model with an axe-head predictor, following the [official TorchVision fine-tuning interface](https://docs.pytorch.org/tutorials/intermediate/torchvision_tutorial). A trained image detector remains research-only until independent localization, timing and native-runtime checks support integration. The earlier failed HOG/SSDLite weights, references and results remain unchanged.

## Training protocol frozen before fitting

All 144 baseline training and 52 validation frames have single-reviewer Codex visual engineering annotations. The [fit reference](evaluation/new-footage/fit-reference.json) records boxes, broad athlete regions and explicit visibility states. Box overlays were visually checked before fitting. These are coarse engineering references, not independent expert annotations.

A separate [training-only candidate plan](evaluation/new-footage/training-augmentation-plan.json) samples six offsets (−0.6, −0.4, −0.2, +0.2, +0.4, +0.6 seconds) around the 55% point of each training video. It prepared 216 candidates; visual curation of five training-source sheets retained 11 additional clear-head examples from three sources. Candidate preparation does not change validation/test times. All 36 training videos were surveyed at their four fixed times. Clear positive boxes came from 13 training videos; a fourteenth supplied the three clear empty frames. The fit uses **35 positive frames and three clearly empty frames**; 117 training frames remain unrated. Validation contains 26 visible heads and 26 unrated frames. There are no clearly empty validation frames, so this study cannot estimate general background false-alarm rates.

The ResNet body stays frozen at its verified COCO weights. FPN, RPN and the two-class ROI heads train for 1,000 SGD steps, batch size two, seed 365, learning rate 0.002 with warmup and a final reduction. Small anchor sizes are 8/16/32/64/128 pixels. Images resize to minimum edge 640, maximum 1,024 after cropping the supplied region; training adds horizontal flips and brightness jitter. Only training examples contribute gradients. Validation chooses among steps 200/400/600/800/1000 and sets the score threshold by IoU ≥ 0.5 F1, retaining at most one head per frame. An incorrect retained box counts as both a false positive and a missed visible head. Occluded, blurred, uncertain and out-of-frame labels are excluded from localization scoring.

The saved detector delta excludes the unchanged ResNet body and must be restored with the exact upstream COCO checkpoint. A model/code/metadata/source-plan hash freeze is committed before test images are prepared. Test annotations will be committed before test predictions. No test tuning or coaching promotion is allowed. [Prepared-image hashes](evaluation/new-footage/fit-image-hashes.json) preserve input provenance without publishing pixels.

## Reproduce preparation

Use the research Python 3.12 environment documented in [Gurr Academy](Gurr-Academy.md). From the repository root:

```sh
SV_PY='/path/to/research/venv/bin/python'
SV_NEW='/path/to/private-analysis/new-footage'
"$SV_PY" tools/carne_asada/ingest_archives.py \
  --directory '/path/to/New Training Footage' --output "$SV_NEW" \
  --known '/path/to/previous/manifest.json'
```

Record prior-source capture metadata with the same `ingest_archives.metadata()` function in `known-source-metadata.json`, then:

```sh
"$SV_PY" tools/carne_asada/new_dataset.py plan --parent "$SV_NEW"
"$SV_PY" tools/carne_asada/new_dataset.py sample --parent "$SV_NEW" --partition train
"$SV_PY" tools/carne_asada/new_dataset.py sample --parent "$SV_NEW" --partition validation
```

The source plan refuses replacement, and the test-image path requires a model freeze matching that plan. Raw footage and frame pixels are excluded from the repository.

The committed references make the engineering labels reviewable without footage disclosure. To repeat fitting with the same private media and frozen plans, export the pixel-coordinate annotations with `new_dataset.py reference`, then run in the CUDA environment recorded in [`requirements-training.txt`](../../tools/carne_asada/requirements-training.txt):

```sh
SV_ML='/path/to/ml-venv/bin/python'
"$SV_ML" tools/carne_asada/axe_faster.py fit --parent "$SV_NEW" \
  --reference "$SV_NEW/reference.json" --model "$SV_NEW/models/axe-faster.pt" \
  --metadata "$SV_NEW/models/axe-faster.json" --output "$SV_NEW/validation.json"
```

`fit` verifies the source plan, complete training/validation review, allowed temporal samples, prepared pixel hashes and ROI bounds. Additional temporal samples are restricted to the frozen training-only allowlist. Before exposing test pixels, save and commit `freeze.json` with `plan_sha256`, `model_sha256`, `metadata_sha256` and `code_sha256` from `axe_faster.code_hashes()`:

```sh
"$SV_PY" tools/carne_asada/new_dataset.py sample --parent "$SV_NEW" --partition test \
  --freeze "$SV_NEW/freeze.json" --model "$SV_NEW/models/axe-faster.pt"
# Review and commit held-out engineering labels before predictions.
"$SV_ML" tools/carne_asada/axe_faster.py test --parent "$SV_NEW" \
  --reference "$SV_NEW/reference.json" --model "$SV_NEW/models/axe-faster.pt" \
  --metadata "$SV_NEW/models/axe-faster.json" --freeze "$SV_NEW/freeze.json" \
  --output "$SV_NEW/test.json"
```

Test execution rejects changed weights, code, metadata, fitting annotations or source plans. It also requires reviewed test frames and a source-disjoint fit. Raw videos remain necessary for reproduction; public hashes and rectangles do not reconstruct the private footage.
