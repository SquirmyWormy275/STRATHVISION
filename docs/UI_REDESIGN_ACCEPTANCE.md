# UI redesign acceptance

Record the exact source/run in [handoff](handoff/UI_REDESIGN.md). A build, widget test or concept render is not device/coaching acceptance.

## Automated gates

- Existing engine/app/research/handoff checks remain enabled.
- Canceled imports create no empty project; failed loading preserves originals and prior saved references.
- Single view uses one stage; comparison and resize do not reopen the existing player or reset position.
- Linked/independent scrubbing, stepping, 0.25×, mirror, swap, marks and Undo retain their semantics.
- Resume restores timestamps, active stage/attribute, explicit event/schema and exact profile version. Later library selection cannot relabel an old review. Missing versions require explicit choice or measurements-only; unknown context stays intact.
- Presentation writes cannot overwrite Project state or reorder the filmstrip on each playback tick; old-route writes are rejected.
- Preview generation is lazy/single-worker, coalesced, cancelable, source-revision checked and cache bounded. Failures are nonfatal; originals are not modified.
- Analysis cannot disable playback. Modal text entry suppresses workspace shortcuts.
- Check light/dark, phone/desktop, 200% text and short landscape. Screenshot candidates need visual review before becoming approved golden baselines.

## Native/device gates

Use licensed/generated media. Record native texture-capture limitations. Validate HDR/orientation, file access after restart, missing/reconnected drives and package parity. No private athlete footage in source/screenshots/CI artifacts.

Measure scrolling/scrubbing in a profile build on target hardware: frame-time distributions, long frames, seek correctness, peak decoders and memory. A 60 Hz UI budget differs from video fps and pose sampling. No 60 fps claim without measurement. Windows/macOS/iPhone/physical Android acceptance and production signing remain separate.
