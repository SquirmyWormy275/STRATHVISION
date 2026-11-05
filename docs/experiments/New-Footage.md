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

Fifty-four of the 56 supplied videos are HDR. Frame preparation applies the native study's Hable tone mapping before 1,600-pixel-edge image export. Detector fitting will use training pixels only; validation controls threshold/checkpoint selection. Test pixels remain unopened until a separate model freeze exists, and no test result will be used to tune that model.

The new candidate uses a COCO-pretrained Faster R-CNN/ResNet-50 FPN model with an axe-head predictor, following the [official TorchVision fine-tuning interface](https://docs.pytorch.org/tutorials/intermediate/torchvision_tutorial). A trained image detector remains research-only until independent localization, timing and native-runtime checks support integration. The earlier failed HOG/SSDLite weights, references and results remain unchanged.

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
