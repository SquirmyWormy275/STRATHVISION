# CARNE ASADA research tools

For new local corpora, start with the [sport-agnostic dataset inventory](../../docs/DATASETS.md). These older experiment-specific ingestion commands remain for reproducing their frozen studies.

These local tools measure video-analysis failures, train experimental axe and barbell detectors, and collect real feedback for the bounded CARNE learning loop. Original videos and per-frame outputs stay private. Published JSON records identify source content, splits, models, settings and failures.

Start with the [Gurr results and project purpose](../../README.md#experiment-carne-asada-on-the-gurr-footage), then follow this sequence:

1. **Understand the corpus:** [Gurr Academy](../../docs/experiments/Gurr-Academy.md) explains the five ZIP parts, deduplication, Python environment and full-corpus coverage. `footage.py` and `deduplicate.py` preserve content provenance.
2. **Inspect tracking and contacts:** [the first accuracy pilot](../../docs/experiments/Gurr-Accuracy.md) fixes inputs/references before inference. `predict_accuracy.py` and `score_accuracy.py` keep target coverage, contacts and uncertain references separate.
3. **Reproduce image-detector failures:** [round 2](../../docs/experiments/Gurr-Round2.md) links source-disjoint references, trained HOG/SSDLite models and frozen test results. Use `axe_data.py`, `axe_detector.py` and `axe_transfer.py`; neither failed model is a production implement detector.
4. **Check the actual app:** `native_benchmark.py` prepares private FFV1 windows and scores the Flutter harness. The round-2 guide gives exact native commands. Partial runs cannot be published; opened references remain diagnostic.
5. **Cover complete recordings:** [the full-population native study](../../docs/experiments/Gurr-Population.md) uses `window_population.py` and `window_batches.py` to cover every source interval with bounded jobs. `replay_population.py` checks pinned engines against the same native poses; `compare_population.py` refuses incomplete coverage or a mismatched baseline. Window selection resets, event stress tests and phase quality gates have distinct limits.
6. **Train with additional event footage:** [the new-footage experiment](../../docs/experiments/New-Footage.md) uses `ingest_archives.py`, `new_dataset.py`, `mine_training.py` and `axe_faster.py`. Capture-day groups, engineering annotations, a validation-selected Faster R-CNN and a model freeze separate fitting from held-out testing. Inference requires a manually supplied broad athlete region.
7. **Extend to another sport:** [the Seagate study](../../docs/experiments/Seagate-Footage.md) adds a stable multi-sport inventory, expanded axe supervision and a separate full-frame barbell pilot. `ingest_library.py` excludes download fragments and deduplicates by bytes. `barbell_data.py` and `barbell_detector.py` keep source partitions and model freezes explicit. `library_audit.py` checks sampled decode/person coverage across the verified lifting library; it does not measure accuracy or process every frame.
8. **Create the first genuine labels:** [feedback review](../../docs/FEEDBACK_REVIEW.md) uses `feedback_review.py` and its browser UI. Empty drafts stay unlabelled. The Dart replay evaluates measured exports on disjoint fitting/evaluation recordings; synthetic regression fixtures never count as coaching evidence.

Run Python tests from the repository root using the pinned research environment:

```sh
/path/to/private-analysis/venv/bin/python -m pytest tools/carne_asada -q
```

The image studies use Python 3.12; `requirements-training.txt` records the separate CUDA training environment. App/engine tests have their own Flutter/Dart setup. Tests establish mechanism correctness; detector accuracy, coaching judgments and field outcomes require their respective evidence.

## Maintained training environment and historical reproduction

`requirements-training.txt` now pins patched setuptools and a compatible Torch/TorchVision pair, and includes the ordinary research requirements. Install it into a fresh Python 3.12 environment. It is optional research tooling and is not shipped inside the Flutter app. The old full CUDA 12.8 environment remains available with `git show 7367abb:tools/carne_asada/requirements-training.txt` for auditing the historical experiment. It contains known-vulnerable packages and should not be installed for new work. New fits under the maintained environment are new experiments; frozen weights, references and historical results remain unchanged.

The pairing is checked against the [published TorchVision dependency metadata](https://pypi.org/pypi/torchvision/0.28.0/json). Package-update validation uses dependency resolution, model construction, detection operators and one synthetic forward/backward step; it does not establish reproduction of historical accuracy or CUDA performance.

Validate the installed training environment with `python -m pip check`, `python tools/carne_asada/check_training_env.py --device cpu`, and `python -m pytest -q tools/carne_asada`. On a compatible GPU, `--device cuda` additionally exercises the same synthetic steps on CUDA. CI installs the matching CPU wheels and makes this compatibility check a build gate.
