# CARNE ASADA research tools

These local tools measure video-analysis failures, train experimental axe detectors, and collect real feedback for the bounded CARNE learning loop. Original videos and per-frame outputs stay private. Published JSON records identify source content, splits, models, settings and failures.

Start with the [Gurr results and project purpose](../../README.md#experiment-carne-asada-on-the-gurr-footage), then follow this sequence:

1. **Understand the corpus:** [Gurr Academy](../../docs/experiments/Gurr-Academy.md) explains the five ZIP parts, deduplication, Python environment and full-corpus coverage. `footage.py` and `deduplicate.py` preserve content provenance.
2. **Inspect tracking and contacts:** [the first accuracy pilot](../../docs/experiments/Gurr-Accuracy.md) fixes inputs/references before inference. `predict_accuracy.py` and `score_accuracy.py` keep target coverage, contacts and uncertain references separate.
3. **Reproduce image-detector failures:** [round 2](../../docs/experiments/Gurr-Round2.md) links source-disjoint references, trained HOG/SSDLite models and frozen test results. Use `axe_data.py`, `axe_detector.py` and `axe_transfer.py`; neither failed model is a production implement detector.
4. **Check the actual app:** `native_benchmark.py` prepares private FFV1 windows and scores the Flutter harness. The round-2 guide gives exact native commands. Partial runs cannot be published; opened references remain diagnostic.
5. **Cover complete recordings:** [the full-population native study](../../docs/experiments/Gurr-Population.md) uses `window_population.py` and `window_batches.py` to cover every source interval with bounded jobs. `replay_population.py` checks pinned engines against the same native poses; `compare_population.py` refuses incomplete coverage or a mismatched baseline. Window selection resets, event stress tests and phase quality gates have distinct limits.
6. **Create the first genuine labels:** [feedback review](../../docs/FEEDBACK_REVIEW.md) uses `feedback_review.py` and its browser UI. Empty drafts stay unlabelled. The Dart replay evaluates measured exports on disjoint fitting/evaluation recordings; synthetic regression fixtures never count as coaching evidence.

Run Python tests from the repository root using the pinned research environment:

```sh
/path/to/private-analysis/venv/bin/python -m pytest tools/carne_asada -q
```

The image studies use Python 3.12; `requirements-training.txt` records the separate CUDA training environment. App/engine tests have their own Flutter/Dart setup. Tests establish mechanism correctness; detector accuracy, coaching judgments and field outcomes require their respective evidence.
