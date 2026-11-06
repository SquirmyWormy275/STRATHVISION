# Additional event and early-training footage

This completed experiment used the additional footage supplied on 2026-11-05 to fit a Faster R-CNN axe-head prototype. The frozen model localized **1 of 9 visible held-out heads**, retained one incorrect box and missed eight heads. It remains research-only; no production or coaching improvement is claimed. Start with the [compact results and artifact hashes](evaluation/new-footage/results.json), then follow the method below.

## Corpus and frozen split

All four ZIPs in the private `New Training Footage/` folder ([verified archive/member inventory](evaluation/new-footage/archives.json)) were read to EOF with member CRC checks, archive/member SHA-256 records and stable-file checks. They contain 56 unique video payloads and one photo. One video is byte-identical to the earlier Gurr corpus (`IMG_8024.MOV`), leaving **55 new videos**. The supplied video duration, including that duplicate, is **4,914.657592 seconds**. Original archives remain unchanged; extracted media, frames and contact sheets stay private.

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

Fifty-four of the 56 supplied videos are HDR. Frame preparation applies the native study's Hable tone mapping before 1,600-pixel-edge image export. The detector receives a broad, manually supplied anonymous athlete ROI at inference. These regions include the body, block and swing area; they are not axe-tight ground-truth crops. This experiment does not identify named athletes or automatically select everyone in a heat. Detector fitting uses training pixels only; validation controls threshold/checkpoint selection. Test pixels stayed unopened until a separate model freeze existed. The test result was not used to tune the model.

The new candidate uses a COCO-pretrained Faster R-CNN/ResNet-50 FPN v2 model with an axe-head predictor, following the [official TorchVision fine-tuning interface](https://docs.pytorch.org/tutorials/intermediate/torchvision_tutorial). A trained image detector remains research-only until independent localization, timing and native-runtime checks support integration. The earlier failed HOG/SSDLite weights, references and results remain unchanged.

## Training protocol frozen before fitting

All 144 baseline training and 52 validation frames have single-reviewer Codex visual engineering annotations. The [fit reference](evaluation/new-footage/fit-reference.json) records boxes, broad athlete regions and explicit visibility states. Box overlays were visually checked before fitting. These are coarse engineering references, not independent expert annotations.

A separate [training-only candidate plan](evaluation/new-footage/training-augmentation-plan.json) samples six offsets (−0.6, −0.4, −0.2, +0.2, +0.4, +0.6 seconds) around the 55% point of each training video. It prepared 216 candidates; visual curation of five training-source sheets retained 11 additional clear-head examples from three sources. Candidate preparation does not change validation/test times. All 36 training videos were surveyed at their four fixed times. Clear positive boxes came from 13 training videos; a fourteenth supplied the three clear empty frames. The fit uses **35 positive frames and three clearly empty frames**; 117 of the 155 annotated training frames remain unrated. Other burst candidates were not treated as labels. Validation contains 26 visible heads and 26 unrated frames. There are no clearly empty validation frames, so this study cannot estimate general background false-alarm rates.

The ResNet body stays frozen at its verified COCO weights. FPN, RPN and the two-class ROI heads train for 1,000 SGD steps, batch size two, seed 365, learning rate 0.002 with warmup and a final reduction. Small anchor sizes are 8/16/32/64/128 pixels. Images resize to minimum edge 640, maximum 1,024 after cropping the supplied region; training adds horizontal flips and brightness jitter. Only training examples contribute gradients. Validation chooses among steps 200/400/600/800/1000 and sets the score threshold by IoU ≥ 0.5 F1, retaining at most one head per frame. An incorrect retained box counts as both a false positive and a missed visible head. Occluded, blurred, uncertain and out-of-frame labels are excluded from localization scoring.

The saved detector delta excludes the unchanged ResNet body and must be restored with the exact upstream COCO checkpoint. The model/code/metadata/source-plan hash freeze was committed at [3bfac94](https://github.com/SquirmyWormy275/STRATHVISION/commit/3bfac94) before test-image preparation. The [test reference](evaluation/new-footage/test-reference.json) was committed at [054f5cb](https://github.com/SquirmyWormy275/STRATHVISION/commit/054f5cb) before test predictions; the training/validation reference hash remained unchanged. No test tuning or coaching promotion is allowed. [Prepared-image hashes](evaluation/new-footage/fit-image-hashes.json) preserve input provenance without publishing pixels.

## Frozen result and failure analysis

The actual CUDA fit ran 1,000 steps in **340.2 seconds** on an RTX 4070 Laptop GPU. The unchanged COCO ResNet body was frozen; 19,748,121 parameters in the remaining detector trained. Validation selected step 800 and threshold **0.6178619266**. The saved [79 MB detector delta](evaluation/new-footage/axe-faster.pt), [model metadata and validation history](evaluation/new-footage/axe-faster.json), [fit log](evaluation/new-footage/fit.log) and [hash freeze](evaluation/new-footage/freeze.json) are committed. Restoration requires the [upstream COCO checkpoint](https://download.pytorch.org/models/fasterrcnn_resnet50_fpn_v2_coco-dd69338a.pth), SHA-256 `dd69338a24b8d7381807e247652bdc356325bcbaf1cd3e092e00e0a1a58706bf`.

| Partition | Fixed frames reviewed | Visible heads scored | Correct boxes | Incorrect retained boxes | Missed heads | Unrated frames | Precision on rated frames | Recall | F1 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Validation, selected checkpoint | 52 | 26 | 8 | 2 | 18 | 26 | 80.0% | 30.8% | 44.4% |
| Test, one frozen pass | 24 | 9 | 1 | 1 | 8 | 15 | 50.0% | 11.1% | 18.2% |

Inspect the [validation predictions](evaluation/new-footage/validation.json), [test predictions](evaluation/new-footage/test.json), [test image hashes](evaluation/new-footage/test-image-hashes.json) and [post-test descriptive diagnostics](evaluation/new-footage/test-diagnostics.json). Fifteen of 24 test frames (**62.5%**) are unrated, and there are no confirmed empty validation/test frames. Thus precision here measures localization on visible-head frames, not a general background false-alarm rate. No candidates crossed the fixed threshold on the 15 unrated test frames; that observation does not establish correct handling of hidden axes generally.

| Held-out source | Visible heads | Correct | Incorrect retained boxes | Missed | Unrated |
|---|---:|---:|---:|---:|---:|
| IMG_7950.MOV | 2 | 0 | 0 | 2 | 2 |
| IMG_3844.MOV | 1 | 0 | 0 | 1 | 3 |
| IMG_3847.MOV | 3 | 1 | 1 | 2 | 1 |
| IMG_4050.MOV | 2 | 0 | 0 | 2 | 2 |
| IMG_4052.MOV | 0 | 0 | 0 | 0 | 4 |
| IMG_7949.MOV | 1 | 0 | 0 | 1 | 3 |

The only correct retained test box is the raised axe in IMG_3847 at 89.409 seconds (IoU 0.627). The incorrect retained box in that recording has zero overlap with the annotated target. A candidate in IMG_7949 overlaps its target at IoU 0.601 but scores below the frozen threshold, so it remains a miss. The threshold was not lowered after this observation.

Test head boxes have median prepared-frame dimensions **28 × 28 pixels**, compared with **60 × 49** for training and **85.5 × 46.5** for validation; test widths range from 8 to 73 pixels. This size difference and the thin edge-on views are observed limitations, not proof of a single cause of failure. The references are coarse boxes from one visual engineering reviewer; small-box IoU is sensitive to boundary errors. Six recordings from three metadata capture days are a small, correlated holdout, and one recording has no rateable heads. This is not athlete-independent or field validation.

The study contributes verified archive ingestion, reproducible grouped splits, reviewed engineering references, a real fitted model and an auditable negative result. It does **not** establish that more footage improved the app: historical axe prototypes used different references, contact timing was not re-evaluated here, and no coach judgments were created. The app continues using its disclosed grip proxy. Next research work should expand small/edge-on training boxes across the existing training sources and add clear background examples, use validation for decisions, then reserve fresh capture days for a new final test. These published test sources are now opened and cannot serve as a fresh independent holdout for later revisions.

Verification: **65 research tests pass**; the real CUDA forward/backward smoke passed; the fitted delta restored with the verified COCO body and completed all 24 test predictions; all 55 extracted source hashes were rechecked without mismatch. The original four archives remain intact. No raw footage, contact sheets, prepared pixels or per-frame poses were published.

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

The committed references make the engineering labels reviewable without footage disclosure. Exact reproduction also requires the retained private plan and pixel manifests; the public source plan redacts calendar metadata. To repeat fitting with the same private media and frozen plans, prepare the training-only burst manifest and copy the committed normalized fit reference. Use the CUDA environment recorded in [`requirements-training.txt`](../../tools/carne_asada/requirements-training.txt):

```sh
SV_ML='/path/to/ml-venv/bin/python'
"$SV_PY" tools/carne_asada/mine_training.py --parent "$SV_NEW"
cp docs/experiments/evaluation/new-footage/fit-reference.json "$SV_NEW/reference.json"
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

Use the published weights, metadata and freeze to reproduce the reported test; after test-frame preparation, copy `test-reference.json` over the private reference. A retraining run needs its own freeze. Training is seeded but is not promised byte-identical across CUDA devices/software; these opened test sources cannot become a fresh independent holdout.

Test execution rejects changed weights, code, metadata, fitting annotations or source plans. It also requires reviewed test frames and a source-disjoint fit. Raw videos remain necessary for reproduction; public hashes and rectangles do not reconstruct the private footage.

### Environment preservation

The maintained training requirements have since received security updates. Exact historical pins remain in Git at `7367abb:tools/carne_asada/requirements-training.txt`; they are evidence, not a recommendation for new installations. Fits under the maintained environment require a new run record and do not inherit these frozen results.
