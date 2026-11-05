# Handover reconciliation — 2026-11-05

This is a documentation-only review by a second Codex session, coordinated in
[handoff issue #1](https://github.com/SquirmyWormy275/STRATHVISION/issues/1#issuecomment-6672415404).
It does not change contracts, phase acceptance, or runtime behavior.

## Scope and ownership

The active Seagate research owner retains the footage inventory, axe and barbell
experiments, training references, private media, research tools, and running jobs.
This review owns only this file. The shared STATUS.md owner and heartbeat are
unchanged. The coordination message was posted; acknowledgment is pending.

## Starting point

At inspection, implementation was at `7d4e735` and main at `f5b8bf3`.
There were 96 implementation-only commits and one main-only commit. No open PRs
were returned by the GitHub connector. The working tree contained another
agent's untracked `tools/carne_asada/library_audit.py`; it was left untouched.

The original handover describes main. The implementation branch already contains
the Flutter app, dual-video workspace, analysis engine, and later research work.
[STATUS.md](STATUS.md) reports Phases 1–9 implemented, with outstanding device
checks. Those reports are historical evidence, not fresh verification in this
review. Restarting the skeleton would duplicate existing work.

## Findings and next checks

| Finding | Evidence | Next action |
| --- | --- | --- |
| Phase 1 acceptance remains open despite later implementation. | EXECUTION_PLAN requires Windows launch; STATUS explicitly records that launch as unverified. The builds workflow builds and archives Windows but does not launch it. | Obtain Windows launch/import/restart evidence before describing the strict phase gate as passed. Preserve existing later-phase work. |
| External integration guidance is absent from implementation. | The only main-only commit adds EXTERNAL_INTEGRATION_PLAN.md. | Reconcile the guidance with evolved implementation contracts before integrating it; do not use a blind merge as evidence of compliance. |
| Device-role instructions conflict. | The latest user handover says phone inference only and desktop profile fitting. DECISIONS permits phone profile creation; Library exposes Build a profile without a desktop gate, and invokes ProfileBuilderScreen. | The latest user instruction governs future changes. Reconcile DECISIONS and INTERFACES before changing the existing mobile flow; desktop-only fitting and its phone interaction need a concrete contract. |
| Uncertainty-aware ranking is not an existing contract. | The external plan proposes uncertainty and derivation fields and uncertainty-scaled ranking. Current Metric Vector contracts lack those fields; compare.dart computes score/deltas and then emits low-confidence warnings. | Define uncertainty semantics, propagation, rejection behavior, and versioning in the binding documents before implementing ranking changes. Warnings alone do not establish adequate input quality. |
| App instructions contain historical stub descriptions. | apps/strathvision/README.md still describes the pose model as a stand-in, while DECISIONS includes real pose decisions and the engine contains the BlazePose mapping. | Verify current runtime selection and then update the affected manual checks. Do not infer production accuracy from model availability. |

## Review limits

This pass inspected Git history, branch differences, the handoff, binding
documents, comparison code, the Library profile-building entry point, and build
configuration. It did not run tests, launch devices, inspect research holdouts,
or change any runtime files. No phase is newly certified by this review.

## Follow-up: app documentation and focused checks

On 2026-11-05, the second session claimed this file and
`apps/strathvision/README.md` in handoff issue #1. The active research owner retained
all research work and STATUS.md ownership. Runtime code and contracts were not
changed.

Inspection confirmed that WorkspaceRoute defaults to `visionRunner` and the
profile builder defaults to `visionEvaluator`. Both use real local pose tracks;
`GripImplementTracker` infers a segment from the wrists and forearms. The README
now describes that distinction, removes obsolete fixed placeholder counts, and
explains the difference between synthetic test fixtures and real-footage gates.
It also gives a beginner entry path and the focused Phase 1 test command.

Verification against runtime source at `4c892c8`:

```sh
cd apps/strathvision
flutter test --no-pub --concurrency=1 test/widget_test.dart test/profile_package_test.dart
```

All **14 tests passed**: Library/Workspace navigation, dummy import display,
invalid import rejection without storage, metadata persistence after database
reopen, JSON/directory/ZIP package reading, and malformed-package rejection.
The first attempt failed before assertions because Flutter could not copy a
temporary compiler artifact (`Disk quota exceeded` under `/tmp`). The successful
retry used a fresh private `TMPDIR` under the home filesystem. No shared temporary
files or other agents' processes were removed.

These tests use substituted players and file pickers. They do not establish
Windows launch acceptance, native dialog behavior, real-decoder accuracy, or
mobile device acceptance. The strict Phase 1 Windows gate remains open.

Next: collect Windows launch/import/restart evidence; coordinate device-role
contract reconciliation before changing the mobile profile-building flow.
