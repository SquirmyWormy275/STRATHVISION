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

## Claude completion pass, 2026-11-11

- **Linux CI repair.** The native `Real Linux decoder` step failed at `1315a14`: `MediaKitStagePlayer.open` treated mpv's nonfatal `Could not open codec.` message as a failed open, though the same clips decode on main. `open` now fails only when no playable duration follows the error within 2 s. Broken files still fail; the 10 s overall timeout is unchanged.
- **Review fixes** (from a code review of this PR against the review priorities above):
  - Playback clears an unconfirmed seek target, so a later pause can still mark or save.
  - Seeks clamped to the end of a clip confirm on the last frame's start time.
  - Lifecycle saves wait until restore finishes, so they no longer overwrite saved positions with 0.
  - A checkpoint requested during an in-flight save saves again with the newer state.
  - With no compatible profile, an implicit measurements-only choice is no longer pinned.
  - Note reports a frame-settle failure instead of doing nothing.
  - A preview decoded after every tile cancelled is still cached.
  - Regression tests were added for the profile and preview-cache fixes; each fails on the previous source.
- **Deliberately unchanged:** reviews with no saved event still open without one, with the event chooser offered, rather than inheriting the library's current selection. That matches the "library event changes do not relabel existing reviews" contract.
- **Observed:** analyzer clean, 173 app tests pass locally. All 11 jobs in builds, ui-review-evidence and ui-regression-diagnostics passed on the same source tree (run 42977893581): the native Linux decoder, pose and full desktop workflow, plus the Android, Windows, macOS and iOS builds.
- **Native screenshots:** the 14 native Linux screenshots from that run were inspected, with real footage visible in single, linked, mirrored, analysis and library views. They are inspected candidates, not approved golden baselines.
- **Still open (unchanged):** physical-device acceptance, production signing, measured 60 fps / frame-time performance on target hardware, and coaching/model validity.
