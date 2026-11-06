# STRATHVISION External Integration Plan

This document augments the locked `docs/EXECUTION_PLAN.md`. It does not invent new top-level concepts or alter contracts in `ARCHITECTURE.md`, `DECISIONS.md`, or `INTERFACES.md`. All recommendations stay inside the existing phases, quality gates, and non-goals.

**Historical proposal, not current implementation.** The app now uses a Dart runtime with local BlazePose/ONNX; RTMPose/Sports2D below are possible alternatives requiring measured validation. See [current architecture](ARCHITECTURE.md) and [roadmap](ROADMAP.md). Dual-video excellence remains the first usable product. Analysis is progressive enhancement. CARNE ASADA stays desktop-only research.

## Guiding Constraints (reaffirmed)

- Local-first. No required cloud.
- Engine contains zero timber- or lifting-specific logic. Packs supply phases, metrics, weights.
- Every score is a style match with inspectable ranked deltas.
- Quality gates are hard and cannot be bypassed.
- Phone does inference only. Desktop workbench does heavy work.
- Free-form generative coaching is a non-goal.
- Dual-video workspace must be excellent even if analysis is unavailable.

## Phase Mapping of External Insights

### Phase 2 — Dual-Video Workspace
**Kinovea patterns (highest priority)**  
Study and match the proven interaction model:
- Set a common time origin on a visible event (or “synchronize on current frames”).
- Joint timeline and controls that drive both stages.
- Linked playback rate by default (same slow-mo factor).
- Frame-step on the locked pair.
- Optional superposition overlay.
- Instant clear of sync.

These map directly onto the Workspace Events contract in `INTERFACES.md`. Acceptance remains: align two clips and play locked at 0.25× in under 15 seconds, relationship survives project reopen.

No analysis code in this phase.

### Phase 3 — Analysis Runtime Skeleton
**Sports2D / RTMPose foundation**  
On the desktop workbench, the analysis engine should call (or wrap) a local Sports2D-style pipeline:
- RTMPose (via RTMLib) for 2D keypoints.
- Person selection and tracking.
- Joint and segment angles with explicit conventions.
- Confidence per keypoint.
- Optional Butterworth / One Euro filtering and Hampel outlier rejection.

The stub in Phase 3 can return a valid Metric Vector. Real pose can be wired later without changing the contract.

**Uncertainty fields**  
Extend the Metric Vector (without breaking the schema) with optional `uncertainty` and `derivation` per metric. Ranked deltas later weight by both coach spread and per-stroke uncertainty.

### Phase 4 — Profile Builder
**NVIDIA-style data-quality gates**  
Adopt the onboarding checklist and gates from the Sports Intelligence Playbooks:
- Split by source (session/athlete), never by stroke.
- Ambiguity filters so every metric has one clear ground-truth source.
- Duration- or confidence-only baselines.
- Self-consistency check already required; make it automated and report the baseline.
- Defect gating: low-confidence frames, missing implement, inconsistent phase labels. Count every exclusion.

A profile is not ready unless minimum usable strokes, pose/implement confidence, and self-consistency all pass. Failure returns the Error Contract.

### Phase 5 — Style Comparison
**Uncertainty-aware ranked deltas**  
Contribution = distance in units of coach spread, scaled by stroke uncertainty. Large noisy deltas rank below moderate clean ones. Every delta remains expandable to user value, coach center, coach spread, phase, and uncertainty.

**PoseForge-inspired counterfactual ghost**  
Once metrics are stable, the ghost is the minimal anatomically plausible residual edit that moves the athlete toward the coach center on the highest-ranked, lowest-uncertainty delta. Use a lightweight FABRIK-style chain (spine/arms/legs, bone-length preservation, hinge limits) or a simple residual exemplar. Ghost is re-projected into the athlete’s camera. No free-form generative cues.

### Phase 6 — Timber Pack + Specialist Net
**Implement tracking (TTool-inspired)**  
Class templates for axe, chainsaw, hot saw, barbell, etc.:
- Rigid attachment model with length/offset prior.
- Per-instance refinement only inside the prior (versioned).
- Low-confidence frames zero implement dimensions, suppress dependent metrics (slope, spacing, hinge), and keep body-only comparison.
- Confidence is a hard gate.

**AthletePose3D (optional fine-tune)**  
If monocular 3D error is too high on timber or lifting motions, use the AthletePose3D dataset on the desktop workbench to fine-tune a monocular lifter. This is optional and does not change the Metric Vector contract.

**Specialist residual**  
`slope_residual` remains the day-one net (2-layer MLP, <10k params). Probes stay exactly as defined in `DECISIONS.md`.

### Phase 7 — Workbench Harness + Compile-Once Adapters
**Compile-once adapters**  
Already in the design. Treat usable-footage gates, attribute priority, and event classification as English specs in the pack, compiled once on the workbench into tiny local adapters. Zero LLM cost at inference. This is a first-class accuracy tool.

### Phase 8 — CARNE ASADA
Unchanged. Desktop-only, max 5–10 accepted edits, priority-attribute isolation, coach-hull constraint, one-sentence explanations. Phone ignores the directory.

### Phase 9 — Drift, Polish, Distribution
**Progress view**  
Secondary surface only. Shows residual trend on the prioritized attribute from already-stored parameter history. No video re-processing. Observational language only.

## Data Engineering Hardening (cross-cutting)

Apply NVIDIA Sports Intelligence Playbooks patterns without adopting the large AVLM stack:

- Source = session or athlete. All strokes from one source stay in the same split.
- Every pack metric must satisfy: clear ground-truth field (or trusted derived rule), ambiguity filter, real example row, unit, phase.
- Report per-class support and imbalance before enabling a metric.
- Regeneration of a Metric Vector or Profile from the same inputs is deterministic.
- Evaluation sets (optional, desktop): MCQ-style probes for residuals and ranked deltas; open-ended descriptions that are direct translations of measured deltas only.

## Immediate Next Artifacts for Agents

1. Versioned timber pack metric schema (JSON) that satisfies the Metric Vector contract and includes uncertainty and derivation.
2. Automated quality-gate and self-consistency test specification with exact pass/fail criteria.
3. Sample Metric Vector + Comparison Result pairs for underhand (slope, spacing, hinge), including low-confidence and rejection cases.
4. Phase-segmenter evaluation protocol (temporal IoU against coach-corrected boundaries).
5. Kinovea-style sync contract notes for the Flutter dual-video implementation.
6. Sports2D / RTMPose wrapper sketch that produces a valid Metric Vector.

## Non-Goals (reaffirmed)

- Adopting NeMo / Megatron large multimodal fine-tuning stacks.
- Free-form generative coaching chat as the primary interface.
- Required cloud for the core loop.
- CARNE ASADA on mobile.
- Replacing explicit metrics with end-to-end learned embeddings in v1.

## Status

This plan is ready for agent consumption. It does not authorize any change to locked contracts. If a recommendation appears to require a contract change, stop and update `INTERFACES.md` and `DECISIONS.md` first.
