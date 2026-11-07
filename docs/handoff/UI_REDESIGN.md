# Footage-first UI implementation

Branch: `codex/footage-first-ui`. Draft PR #9 targets `implementation`. The user authorized implementation, not release or main merge. Work is isolated from the user's local workstation and existing release candidate.

## Scope

Shared graphite/chalk/cobalt theme and bundled fonts; footage-led library; direct clip opening; optional comparison; explicit human marks; saved event/profile/version and positions; separate local presentation storage; bounded native thumbnails; regression and screenshot evidence tooling. Engine mathematics, sport-pack boundaries, feedback content provenance and research results remain unchanged.

References: [visual system](../VISUAL_SYSTEM.md), [local-state contract](../UI_REDESIGN_CONTRACT.md), [acceptance gates](../UI_REDESIGN_ACCEPTANCE.md).

## Evidence — in progress

Initial compile at `3eec0e2` found a Clip name collision, missing Drift extension import and style diagnostics. Pinned font/license retrieval passed. A guarded maintenance runner on this topic branch applies only explicitly allowed app/test edits and Dart fixes, checks the expected head, and can only fast-forward this branch. It cannot modify workflows, main, implementation or the analysis engine. Remove it after integration and rerun required checks on the final head.

Tests are added, not yet certified here as passing. Record exact observed results before closing acceptance. Rendered candidates using player doubles are not native or physical-device evidence. Preserve failed runs; never fabricate throughput or coaching accuracy.

## Priorities for review

Save/close ordering; canceled or failed imports; event change followed by reopening; missing profile versions; corrupt/future settings; large text and short windows; source change; native decoder seeking and screenshots; all profile/export/workbench operations. Keep the draft unmerged while checks fail or device evidence is outstanding.
