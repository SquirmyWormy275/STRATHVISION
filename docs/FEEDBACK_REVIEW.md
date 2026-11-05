# Collect and evaluate real coaching feedback

The local review tool plays private clips, lets a reviewer select one complete stroke, choose an attribute and red/green judgment, and save an explanation. **Another stroke in this clip** creates a fresh unlabelled task. Judgments persist atomically in the private packet and export as `coach-feedback/1`. Videos and audio stay on the computer; the server listens on loopback only.

Start with the pinned research environment from [Gurr Academy](experiments/Gurr-Academy.md#reproduce-the-run). From the repository root:

```sh
SV_PY='/path/to/private-analysis/venv/bin/python'
SV_REVIEW='/path/to/private-analysis/coach-review'
"$SV_PY" tools/carne_asada/feedback_review.py prepare \
  --reference docs/experiments/evaluation/round2/axe-reference.json \
  --root '/path/to/Gurr Academy ' --directory "$SV_REVIEW"
"$SV_PY" tools/carne_asada/feedback_review.py serve --directory "$SV_REVIEW"
```

Open the localhost URL printed by the server. The prepared twelve-task packet contains no judgments. Existing packets are never overwritten by `prepare`; restart `serve` to continue reviewing. Copies used for playback are rotated upright, tone-mapped from HDR where necessary, and encoded as browser-compatible MP4 with audio. Original footage is unchanged.

1. Watch the movement. Use the start/end buttons to select one stroke.
2. Enter the reviewer name, choose the attribute and judgment, and optionally explain it.
3. Confirm the complete stroke and the review, then save. Uncertain movements can remain unreviewed.
4. Review another stroke or move to the next clip. Export judgments when ready.

The source and fitting/evaluation group come from the packet and cannot be changed by a submitted judgment. A reviewed label records human-entered author/reviewer provenance; the tool does not verify professional credentials. Automated tests use a separate, explicitly synthetic packet and never insert their labels into the real Gurr packet.

## Replay a learning experiment

CARNE's **Save experiment** now includes measured Metric Vectors, phase confidence and implement dropout for each stroke, alongside its source hash. The separate replay tool binds reviewed spans uniquely to usable measured strokes. It rejects source leakage, inconsistent duplicate analyses, and overlap between base-profile references and evaluation recordings. Duplicate exports cannot inflate usable minutes.

Use a ready coaching profile with the original minimum-reference/self-consistency gates. Add `reference_sources` to the feedback export: a mapping from each base-profile reference clip ID to its video SHA-256. This proves that the evaluation recordings were not already used by the profile. Without that provenance, sufficient usable footage, reviewed fitting/evaluation judgments, or usable aligned measurements, the result remains pending.

From `packages/analysis_engine`:

```sh
dart run tool/feedback_evaluation.dart \
  /path/to/coach-feedback.json /path/to/learning-result.json \
  /path/to/carne-run.json
```

Additional run files can follow the first. The tool evaluates the unchanged profile, runs the bounded CARNE loop on fitting recordings only, and measures feedback agreement on separate evaluation recordings. It reports edits, the existing hull log, agreement before/after, exclusions and a candidate profile snapshot. It does not publish a new package version. Agreement gains remain an experimental result until measurement accuracy and real-world coaching outcomes are independently validated.

## Checked behavior

- Python tests cover draft rejection, immutable source/partition provenance, byte-range video playback, persistence, repeated stroke tasks, failed-write rollback and cross-origin write rejection.
- A Chromium test decoded the licensed cleave fixture, selected 1–2 seconds, saved/exported a synthetic judgment, created a new unlabelled stroke and checked the 390-pixel layout.
- Dart tests replay synthetic measured exports through the actual CARNE loop, preserve the original profile, reject source leakage and count duplicate footage once.
- The real Gurr packet currently contains zero judgments. Its [evaluation status](experiments/evaluation/round2/genuine-feedback-status.json) is explicitly pending; no coach-learning improvement is claimed.
