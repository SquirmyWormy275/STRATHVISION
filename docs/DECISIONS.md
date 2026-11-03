# Architectural Decisions

## ADR-001: Rust/Python hybrid analysis engine

**Status**: Accepted

**Context**

The analysis runtime (pose orchestration, phase detection, metric extraction, comparison, profile fitting) must be fast, distributable, and callable from Flutter on desktop and mobile. Early metric and phase definitions will change frequently.

**Decision**

- **Rust** owns the stable, performance-sensitive core and the Flutter boundary:
  - Frame/keypoint containers
  - Metric vector assembly
  - Comparison engine
  - Profile serialization and fitting
  - Quality-gate evaluation
  - C ABI / `flutter_rust_bridge` (or equivalent) interface
- **Python** is permitted only for early experimentation on phase rules and metric definitions. Winning definitions are ported into Rust (or expressed as pack data consumed by Rust) before they are considered production.
- The contracts in INTERFACES.md remain the source of truth. Neither language may introduce concepts that are not in the contracts.

**Consequences**

- Desktop and mobile can share the same comparison and profile logic.
- Profile packages are produced by Rust code, so they are consistent across platforms.
- Iteration on new metrics is slightly slower once ported, but the final artifact is a single, predictable binary component.
- Pose estimation itself stays behind a replaceable backend interface; the language choice does not lock the pose model.

**Rejected alternatives**

- Pure Python: simpler iteration, harder distribution and mobile story.
- Pure Rust from day one: cleaner, but higher cost on the first rounds of phase/metric experimentation.

## ADR-002: Pose estimation backend interface

**Status**: Accepted

**Context**

Pose estimation is the most likely component to be replaced or upgraded. The rest of the pipeline (phase detection, metrics, comparison) must not depend on any single model's output format or quirks.

**Decision**

Pose estimation sits behind a narrow interface owned by the Rust core:

```text
PoseBackend::extract(video_path: &Path) -> Result<Vec<FrameKeypoints>, PoseError>
```

- `FrameKeypoints` contains timestamp or frame index, joint positions, and per-joint confidence.
- v1 default implementation may use MediaPipe, an ONNX model, or equivalent. The choice is an implementation detail.
- Swapping or adding a backend requires no changes to phase detection, metric extraction, comparison, or profile code.
- All downstream stages consume only `FrameKeypoints`. They never call a pose library directly.

**Consequences**

- Backend upgrades are localized.
- Tests for phase and metric logic can use recorded or synthetic `FrameKeypoints` fixtures.
- Low per-joint or per-frame confidence is available for the degradation rules in ADR-004.

## ADR-003: Dual-video sync model

**Status**: Accepted

**Context**

Users need to align two clips (own movement vs reference, or two of their own) and scrub or play them together. Complex time-warping is unnecessary for v1 and easy to get wrong.

**Decision**

- Each synced pair stores a single primary offset (in milliseconds or frame delta) inside the Project.
- Offset is set by the user choosing a frame on stage A and a frame on stage B and invoking "Set Sync Point".
- When locked, both timelines advance by the same media-time delta after the offset is applied.
- Frame step operates on the locked pair when sync is active; otherwise it operates on the active stage.
- Mirror affects display only and does not alter the offset.
- Only one primary offset per pair in v1. Multi-point or dynamic warping is out of scope.

**Consequences**

- Sync state is simple to persist and restore.
- Implementation and testing stay bounded.
- The interaction remains fast enough for the "align in under 15 seconds" acceptance criterion.

## ADR-004: Device capability split (v1)

**Status**: Accepted

**Context**

Profile building requires multiple clean reference clips, quality-gate evaluation, and self-consistency checks. Mobile devices are poor hosts for that workflow in v1.

**Decision**

**Laptop / desktop may**:
- Manage full library and projects
- Run pose → phase → metrics on reference sets
- Build, validate, and export profile packages
- Perform deeper metric inspection

**Phone may**:
- Capture and import video
- Run the full dual-video workspace
- Score clips against already-installed profile packages
- Display ranked deltas and drift history
- Import/export profile packages

**Phone may not (v1)**:
- Build or refit profiles from raw reference clips
- Bypass quality gates

**Consequences**

- Mobile scope stays shippable.
- The same Rust comparison code runs on both sides; only profile *construction* is desktop-only.
- Users who want new profiles use the laptop, then move the package.

## ADR-005: Confidence and score degradation

**Status**: Accepted

**Context**

Low-quality pose or phase detection must not produce confident-looking style-match scores.

**Decision**

- Packs define critical phases and minimum confidence thresholds.
- If pose or phase confidence on a critical phase falls below threshold:
  - The Comparison Result must include an explicit warning.
  - The overall score is visually secondary or marked degraded.
  - Affected deltas are marked low-confidence.
- Implementation may not suppress these warnings or present a clean primary score when coverage is insufficient.

**Consequences**

- Results stay trustworthy under poor filming conditions.
- Users can see when they need a better clip instead of receiving a misleading number.
