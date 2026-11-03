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
