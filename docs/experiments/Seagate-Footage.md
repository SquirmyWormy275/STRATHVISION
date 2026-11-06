# Seagate footage: axe follow-up and weightlifting research

This study uses the private Seagate library to expand engineering supervision and evaluate implement localization. Raw video, frames, contact sheets and voice recordings stay private. The earlier [55-video experiment](New-Footage.md) and [47-video Gurr population run](Gurr-Population.md) remain unchanged.

## Protocol frozen before fitting

The library inventory hashes completed video files to EOF, probes media streams, records aliases and compares content hashes with both previous corpora. Downloader fragments, temporary merge outputs and archives are not counted as additional completed videos. A file changed during verification is deferred. This is a dated snapshot while another downloader may continue adding footage; it is not a full-duration decode claim.

The axe follow-up retains the previous 36/13/6 capture-day source split, 144 baseline training frames, 52 validation frames, and all original broad athlete regions. All 216 previously prepared training-only burst candidates are now visually reviewed. These add 49 visible-head boxes (including the 11 previously retained), yielding **73 positive training frames and three clear negatives**. Uncertain, obscured, blurred and out-of-frame candidates are recorded but excluded from fitting. All added positive boxes were checked in enlarged overlays before fitting. References remain coarse single-reviewer engineering labels, not independent expert measurements or judgments of technique.

The follow-up uses exactly the previous Faster R-CNN architecture, 1,000-step schedule, seed, COCO initialization, checkpoint selection and validation threshold procedure. The question is whether expanded training references improve the **same validation** localization score. This is an exploratory validation comparison after the first study's test was opened; the six old test sources are not a fresh holdout and will not be re-scored here. Training and validation image hashes, references and model metadata will accompany the result.

Weightlifting is a separate task and corpus with source-grouped partitions fixed before fitting. Video titles are descriptive metadata, not coach judgments. Commentary has not been transcribed or bound to repetitions. Barbell localization must be evaluated separately from body pose, lift classification, bar-path accuracy and coaching quality; no production lifting capability is implied by a research fit.

## Reproduction entry points

- [`ingest_library.py`](../../tools/carne_asada/ingest_library.py): stable library snapshot, SHA-256 deduplication and download-component exclusions.
- [`axe_faster.py`](../../tools/carne_asada/axe_faster.py): unchanged source-guarded training and validation selection.
- [Expanded axe fit references](evaluation/seagate/axe/fit-reference.json) and [prepared-image hashes](evaluation/seagate/axe/fit-image-hashes.json).

## Expanded axe result

The real CUDA fit completed 1,000 steps; validation selected step 600 and score threshold 0.1577141136. The original validation references, pixels, architecture and training schedule were unchanged.

| Same validation set: 26 visible heads, 26 unrated frames | Correct | Incorrect boxes | Misses | Precision | Recall | F1 |
|---|---:|---:|---:|---:|---:|---:|
| Earlier 35-positive fit | 8 | 2 | 18 | 80.0% | 30.8% | 44.4% |
| Expanded 73-positive fit | 11 | 11 | 15 | 50.0% | 42.3% | 45.8% |

Expanded supervision increased recall while introducing many more incorrect boxes at the independently selected validation thresholds. The 1.4 percentage-point F1 increase is exploratory, not an independently tested improvement. Correlated neighboring frames do not equal new recording sessions. No old-test re-score or app promotion was performed. The conditional athlete ROI and lack of clear empty validation frames still limit the claim.

The [weights](evaluation/seagate/axe/axe-faster.pt), [training metadata and checkpoint history](evaluation/seagate/axe/axe-faster.json), [validation predictions](evaluation/seagate/axe/validation.json), and [fit log](evaluation/seagate/axe/fit.log) preserve the result. The separate weightlifting result follows below; library verification is still running.


## Barbell pilot frozen before fitting

The deterministic source selection ranks completed Instructional uploads by SHA-256 of `barbell-365:` plus the upload ID, takes 60, and assigns 36/12/12 to train/validation/test. It samples 35% and 65% of duration. All 60 payloads were hashed before fitting. The [plan](evaluation/seagate/weightlifting/plan.json), [fit references](evaluation/seagate/weightlifting/fit-reference.json) and [image hashes](evaluation/seagate/weightlifting/fit-image-hashes.json) are fixed before model training. The 24 test frames remain unopened at this checkpoint.

A box covers the foreground demonstration barbell, including visible shaft, sleeves and attached plates; both loaded and unloaded bars count. Background storage equipment, PVC demonstration sticks and blurred side-panel copies do not count. Mild boundary clipping is boxed to the image edge; close-ups that omit most of the implement are unrated. Split-screen comparisons with multiple equally prominent targets, severe occlusion, blur, and recurring promotional endings are unrated. Unrated frames are excluded from fitting and scored localization metrics, with their counts reported. All 60 positive fit/validation boxes were visually checked in overlays. These single-reviewer engineering references are approximate.

The 72 training frames comprise 47 visible bars, nine clear negatives and 16 unrated frames. Validation has 13 visible bars, two clear negatives and nine unrated frames. The full-frame Faster R-CNN baseline uses COCO initialization, a frozen ResNet body, 1,000 SGD steps, seed 365 and validation checkpoint/threshold selection. Wide anchors support horizontal bars. The 12 held-out uploads will be opened only after the chosen weights, metadata, plan and code hashes are frozen. Source-disjoint uploads may still reuse demonstration scenes, venues and athletes: this pilot is not an independent-session benchmark or a coaching test.


## Frozen barbell test result

The 1,000-step CUDA fit took 317 seconds. Validation selected step 600 and score threshold 0.5447220206. The weights and source/code hashes were committed in `4496fa6` before the 12 test uploads were decoded. Their 24 engineering annotations were committed in `3aa0d1e` before the first test prediction. No threshold, weights or references were changed afterward.

| Partition | Visible bars | Clear negatives | Unrated | Correct | Incorrect boxes | Misses | Precision | Recall | F1 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Validation, selected checkpoint | 13 | 2 | 9 | 8 | 3 | 5 | 72.7% | 61.5% | 66.7% |
| Frozen test, 12 uploads | 15 | 1 | 8 | 9 | 2 | 6 | 81.8% | 60.0% | 69.2% |

A retained prediction must overlap the reference at IoU ≥ 0.5. A misplaced retained box counts as both an incorrect box and a miss. Unrated frames do not contribute to accuracy. The one clear-negative test frame produced no retained detection. Mean IoU among the nine matches was 0.722. With only 15 positive test frames, one clear negative and potentially reused demonstration scenes, these numbers are a pilot result, not a deployment acceptance test.

Post-test visual inspection found eight matches among ten loaded-bar references and only one among five unloaded-bar references. The six misses include thin horizontal, diagonal and end-on bars, a bench-press view whose box covered only part of the implement, and an oversized box with IoU 0.494. That last case is close to the fixed cutoff and emphasizes sensitivity to approximate single-reviewer boxes. This breakdown is descriptive after testing; the labels, cutoff and scores remain unchanged. A bounding box alone does not measure shaft centerline, plate centers, calibrated bar path, lift phases or coaching quality.

Published evidence: [weights](evaluation/seagate/weightlifting/barbell.pt), [training metadata](evaluation/seagate/weightlifting/barbell.json), [training log](evaluation/seagate/weightlifting/fit.log), [model freeze](evaluation/seagate/weightlifting/freeze.json), [validation predictions](evaluation/seagate/weightlifting/validation.json), [test references](evaluation/seagate/weightlifting/test-reference.json), [test image hashes](evaluation/seagate/weightlifting/test-image-hashes.json) and [first frozen test predictions](evaluation/seagate/weightlifting/test.json). Both detectors remain research artifacts; the app still uses its existing implement proxy.

## Reproduce the barbell experiment

Use the Python 3.12/CUDA environment in [`requirements-training.txt`](../../tools/carne_asada/requirements-training.txt), plus the private original sources. Copy the published `plan.json` byte-for-byte into a new private work directory and make `media/` point to the original library root. The plan records each relative source path and payload hash. Keep the published models and original experiment directory unchanged.

```sh
python tools/carne_asada/barbell_data.py sample --parent "$BARBELL_WORK" --partition train
python tools/carne_asada/barbell_data.py sample --parent "$BARBELL_WORK" --partition validation
python tools/carne_asada/barbell_detector.py fit \
  --parent "$BARBELL_WORK" \
  --reference docs/experiments/evaluation/seagate/weightlifting/fit-reference.json \
  --model "$BARBELL_WORK/models/barbell.pt" \
  --metadata "$BARBELL_WORK/models/barbell.json" \
  --output "$BARBELL_WORK/validation.json"
```

The sampler rehashes each original source before decoding and uses the same autorotation, HDR handling and maximum 1600-pixel edge used here. Training verifies every prepared PNG hash. The saved model is a delta excluding the frozen ResNet body; the exact COCO checkpoint URL and SHA-256 are in its metadata, and that checkpoint belongs under `model-cache/checkpoints/`. To replay the published test, use the published weights, metadata, freeze and full `test-reference.json`, with the exact frozen code and plan. `barbell_data.py sample --partition test` requires `--freeze` and actual `--model` files. `barbell_detector.py test` additionally checks metadata, fitting references and code hashes and refuses to overwrite an existing test result. Refitting does not create a fresh holdout from these now-opened test videos.
