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

In progress. No round-2 accuracy or learning result is claimed until its measured artifacts are linked here.
