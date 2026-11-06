# STRATHVISION Execution Plan

## Authorized inventory-first research workstream (2026-11-06)

The user explicitly requested this parallel research prerequisite; outstanding physical-device acceptance remains open and is not bypassed or relabeled complete.

1. Read the current contracts and historical experiments; confirm local source availability and, for Seagate, the mounted volume UUID.
2. Implement and test a read-only, sport-agnostic inventory: immutable outputs outside originals, streaming SHA-256 aliases, metadata, per-file failures and final change detection.
3. Implement and test reviewed provenance and transitive split safeguards; unknown provenance stays quarantined, and previous holdouts cannot silently change partitions.
4. Run the inventory when the volume is mounted; publish aggregate evidence and reproducible commands without private paths or footage.
5. Only after inventory, assess the evidence for baseline versus learned/hybrid representations. Actual model/CARNE ASADA comparisons require reviewed groups, genuine labels and a frozen protocol. Report unmet gates explicitly.

Acceptance: automated safety/metadata/deduplication/split tests, a real local run when accessible, source-change checks, public documentation and a focused PR. No changes to production scoring or sport packs are required.

Strict, ordered tasks for implementation. Do not start a task until all acceptance criteria of the previous task are met. Do not invent features outside ARCHITECTURE.md, DECISIONS.md, INTERFACES.md, and CARNE_ASADA.md.

If a requirement is ambiguous, stop and ask rather than inventing behavior.

## Phase 0 — Repository & Contracts (done)

- [x] ARCHITECTURE.md
- [x] DECISIONS.md
- [x] INTERFACES.md
- [x] EXECUTION_PLAN.md
- [x] CARNE_ASADA.md
- [x] README research question + experiment section

## Phase 1 — Project Skeleton

**Goal**: Flutter monorepo that builds on at least one desktop and one mobile target.

**Tasks**:
1. Create Flutter app under `apps/strathvision`.
2. Add basic local storage (SQLite via Drift or equivalent).
3. Implement empty Library and Workspace screens that navigate.
4. Add placeholder for profile import (file picker that accepts a profile package and stores metadata).
5. Confirm builds for Windows + one mobile target (iOS simulator or Android).

**Acceptance**:
- App launches on Windows and on iOS or Android simulator.
- User can import a dummy profile JSON and see its metadata listed.
- No analysis code yet.

**Forbidden**:
- Adding video playback in this phase.
- Adding any timber- or lifting-specific strings outside pack placeholders.
- Any weight-space or CARNE ASADA code.

## Phase 2 — Dual-Video Workspace

**Goal**: The product is already useful for review without any analysis.

**Tasks**:
1. Implement video loading into stage A and stage B.
2. Independent scrubbing with visible timelines.
3. Set Sync Point / Clear Sync.
4. Locked playback using the stored offset.
5. Playback rate control including slow-mo.
6. Frame step.
7. Mirror toggle on stage B.
8. Persist sync relationships inside a Project.
9. Basic red/green buttons (attribute selector + mark on current stroke) that store marks locally.

**Acceptance**:
- User can load two clips, align them in under 15 seconds, play locked at 0.25x, and re-open the project with the sync still intact.
- Frame stepping works on the locked pair.
- Red/green marks persist.
- All operations match the Workspace Events contract in INTERFACES.md.

**Forbidden**:
- Any scoring or profile comparison in this phase.
- Cloud upload of videos.
- Specialist nets or CARNE ASADA.

## Phase 3 — Analysis Runtime Skeleton

**Goal**: Clean interface from Flutter to an analysis backend that can produce a Metric Vector from a clip (even if pose is stubbed).

**Tasks**:
1. Define the analysis engine package with the contracts from INTERFACES.md.
2. Implement a stub pose + phase + metric path that returns a valid Metric Vector for a test clip.
3. Wire “Analyze” button in Workspace to call the stub and display raw metrics.
4. Stub the slope_residual head so it returns a number.

**Acceptance**:
- Clicking Analyze on a clip produces a Metric Vector that validates against the schema (including specialist_residuals).
- Failure cases return the Error Contract.

## Phase 4 — Profile Builder (Laptop / Workbench)

**Goal**: User can build a real profile artifact from reference clips.

**Tasks**:
1. Implement clip import and quality evaluation.
2. Implement profile fitting (center, spread, weights) from Metric Vectors.
3. Implement quality gates including self-consistency check.
4. Export a versioned profile package matching the contract (including empty specialist_patches/ and adapters/ directories).

**Acceptance**:
- Given 15+ clean synthetic or real clips of one “coach”, the builder produces a ready profile or a structured rejection.
- Profile JSON validates against INTERFACES.md.
- Self-consistency test is automated.

## Phase 5 — Style Comparison

**Goal**: Score a new clip against an installed profile and show ranked deltas.

**Tasks**:
1. Implement comparison engine that consumes Metric Vector + Profile and returns Comparison Result.
2. Display overall score + ranked deltas in the Analyze view.
3. Make each delta expandable to show definition, values, and phase.
4. Store results for later drift.
5. Load and apply any specialist patches present in the package.

**Acceptance**:
- Scoring is deterministic for the same inputs.
- Top deltas correctly identify the largest measured differences.
- Low-confidence inputs produce warnings, not silent high scores.
- Applied patches appear in the result.

## Phase 6 — Timber Pack + Specialist Net

**Goal**: First real domain pack and locked specialist net.

**Tasks**:
1. Define phases and initial metric catalog for underhand and standing block (or chosen events).
2. Add pack configuration that the engine loads.
3. Implement the real slope_residual head (2-layer MLP spec from DECISIONS.md).
4. Register the five probes.
5. Validate that comparison works with timber-specific metrics and the residual.

**Acceptance**:
- Engine code contains zero timber-specific strings or logic.
- Pack can be swapped without recompiling the comparison engine.
- slope_residual produces a residual that the probes can measure.

## Phase 7 — Workbench Harness + Compile-Once Adapters

**Goal**: Specialist patches and compile-once adapters work on desktop.

**Tasks**:
1. Implement local weight-space harness interface for registered specialist nets.
2. Wire the five probes as the only feedback.
3. Accept/reject patches according to the exact rules in DECISIONS.md and write them into the package.
4. Implement compile-once path for at least usable-footage and priority-scorer specs.
5. Adapters load on both desktop and phone inference.

**Acceptance**:
- A failing slope bias can be patched on the workbench and the patch improves the probe without regressing others.
- Compiled adapter runs locally with no LLM call at inference time.
- Packages containing patches and adapters import cleanly on phone.

## Phase 8 — CARNE ASADA Research Playground

**Goal**: Desktop-only recursive mixture editor with user-friendly ingestion.

**Tasks**:
1. Implement drop-zone playground with exact status messages from DECISIONS.md.
2. Implement the constrained recursive loop (diagnose → propose sparse update → evaluate → accept/reject → log one-sentence explanation).
3. Enforce max 5–10 edits, priority-attribute isolation, coach-hull (or soft personal pull) constraint, threshold gating.
4. One-click undo and “what did it just do?” view.
5. Write mixture_edits into the package under carne_asada/.

**Acceptance**:
- Dropping clips produces the exact status language.
- Accepted edits stay inside bounds and produce the one-sentence explanations.
- Phone inference ignores the carne_asada/ directory completely.
- Undo restores previous mixture state.

## Phase 9 — Drift, Polish, Distribution Builds

**Goal**: History of match scores, basic UX hardening, and testable builds.

**Tasks**:
1. Drift view for an athlete + profile + event.
2. Profile health indicators.
3. Export/import of profile packages between laptop and phone.
4. Produce Android APK, iOS ad-hoc IPA instructions, and desktop zips.
5. Document the Gurr footage experiment steps in README (already templated).

**Acceptance**:
- User can see match trend over multiple sessions.
- Profile packages move between devices without cloud.
- Test builds install via the locked distribution methods.

## Global Rules for All Phases

- Every task must have automated tests for its acceptance criteria where feasible.
- No new top-level concepts without updating INTERFACES.md and DECISIONS.md first.
- Video files never leave the device unless the user explicitly exports them.
- CARNE ASADA code must be clearly isolated and must not be required for any Phase 1–7 acceptance.
- If a requirement is ambiguous, stop and ask rather than inventing behavior.

## Definition of Done for v1

- Dual-video workspace meets Phase 2 acceptance on Windows and at least one mobile platform.
- User can build a profile on laptop and score clips against it on phone.
- Specialist patches and compile-once adapters function.
- All scores are inspectable via ranked deltas.
- Timber pack exists and is not hard-coded into the engine.
- CARNE ASADA playground runs on desktop and can ingest the Gurr set.
- No required accounts or cloud services.
- Test distribution paths (APK, ad-hoc IPA, desktop zip) documented and working.
