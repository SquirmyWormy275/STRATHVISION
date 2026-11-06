# Roadmap after the November 2026 audit

The audit implementation is a correctness and delivery baseline. It does not turn a prototype into a validated coach. Historical phase checkmarks record implementation milestones; current acceptance is listed here.

| Priority | Work | Acceptance / status |
|---|---|---|
| P0 | Safe profile storage and atomic imports | Internal filenames; invalid extras cannot partially replace a profile; traversal and rollback regression tests |
| P0 | Correct feedback provenance | Export only the matching event and source hash; no filename binding; idempotent mark merge; research rejects missing/stale provenance |
| P1 | Reliable fitting and tuning | SHA-256 duplicate rejection, fail-closed athlete/orientation selection, per-file errors and builder retry; distinct files still need session review |
| P1 | Confidence-aware explanations | Versioned `confidence-v1` ranking with deterministic ties; low confidence labeled; historical overall score unchanged |
| P1 | Reproducible delivery | PR checks, Python research suite, Dart/Flutter coverage artifacts, native Linux decoder/pose smoke, five platform builds |
| P1 | Public repository and handoff | Current README and learning path; preserve research failures; reconcile main/implementation; explicitly scoped handoff commits |
| P1 — open | [Physical-device acceptance #2](https://github.com/SquirmyWormy275/STRATHVISION/issues/2) | Actual Windows/macOS/Android/iPhone review, persistence and offline package transfer; Apple signing and devices required |
| P1 — open | [Coach and independent-session evidence #3](https://github.com/SquirmyWormy275/STRATHVISION/issues/3) | Real labels, frozen session-disjoint holdout, contact/implement accuracy, controlled learning comparison, coach-approved packs/Springboard |
| P2 — open | [Local transcription #4](https://github.com/SquirmyWormy275/STRATHVISION/issues/4) | Choose a local runtime/model, review transcripts before binding, verify real audio and recovery; currently absent |
| P2 — open | [Live adapter compiler #5](https://github.com/SquirmyWormy275/STRATHVISION/issues/5) | Authorized credential, available provider/model, sanitized live compile evidence and offline package inference |

## Research promotion sequence

1. Confirm athlete, event and source-session identities. Group re-encodes and excerpts before splitting. Exact-file SHA-256 deduplication is only the first gate.
2. Collect genuine independent labels and record uncertainty. A coach must review metric meaning, thresholds and Springboard's provisional event definition.
3. Freeze dataset manifests, baseline, numeric acceptance thresholds and a test-opening policy before observing the holdout. Previously opened references remain diagnostics.
4. Report person/orientation coverage, contact precision/recall and timing error, implement localization, abstention/failure rates, and all denominators. Compare with the grip proxy and no-update control.
5. Evaluate bounded updates on unseen sessions with coach agreement and adverse-change checks. Preserve zero-edit cases, missed detections, false positives and hull compliance.
6. Promote a model only when those agreed gates pass. A passing unit suite, full coverage scan, or synthetic export is insufficient.

Until then, keep detector prototypes out of production and describe the score as style similarity with measured limitations. [Research status](RESEARCH_STATUS.md) and [validation](VALIDATION.md) contain the evidence.
