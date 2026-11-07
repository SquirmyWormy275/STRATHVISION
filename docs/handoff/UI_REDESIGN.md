# Footage-first UI implementation

Branch: `codex/footage-first-ui`. Draft PR #9 targets `implementation`. The user authorized implementation, not release or main merge. Work is isolated from the user's local workstation and existing release candidate.

## Delivered source

Shared graphite/chalk/cobalt theme and bundled fonts; footage-led library; direct clip opening; optional comparison; explicit human marks; saved event/profile/version and positions; separate local presentation storage; bounded native thumbnails; regression and screenshot tooling. Engine mathematics, sport-pack boundaries, feedback content provenance and research results remain unchanged.

References: [visual system](../VISUAL_SYSTEM.md), [local-state contract](../UI_REDESIGN_CONTRACT.md), [acceptance gates](../UI_REDESIGN_ACCEPTANCE.md).

## Observed evidence

On 2026-11-07, the isolated integration run 42402300585 passed `flutter analyze` and the focused rendered-UI/presentation/thumbnail regression step on repaired source `dfec9530cfb3bf6c7803688998776dc682529936`. The complete app suite was still running when this checkpoint was written. Exact counts and later checks must come from their completed runs, not this note.

Earlier compile failures are retained in GitHub Actions. Pinned font/license provisioning passed. The temporary, narrowly scoped repair workflow committed only allowed app/test files and is now removed, along with its one-time script. Ongoing CI is read-only. New exact-profile/save-recovery tests and the final source need their own checks.

Rendered candidates use actual Flutter widgets and deterministic test players, not native footage. They are not approved golden baselines. Native decoder/device behavior, physical-device acceptance, production signing, 60 fps performance and coaching accuracy are separate gates. No claim of those outcomes is made here.

## Review priorities

Save/close ordering; canceled or failed imports; event change followed by reopening; missing profile versions; corrupt/future settings; large text and short windows; source change; native decoder seeking/screenshots; profile/export/workbench parity. Keep the draft unmerged while required checks fail.
