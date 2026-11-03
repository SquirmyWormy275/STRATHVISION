# STRATHVISION Execution Plan

Strict, ordered tasks for implementation. Do not start a task until all acceptance criteria of the previous task are met. Do not invent features outside ARCHITECTURE.md and INTERFACES.md.

## Phase 0 — Repository & Contracts (done)

- [x] ARCHITECTURE.md
- [x] INTERFACES.md
- [x] EXECUTION_PLAN.md

## Phase 1 — Project Skeleton

**Goal**: Flutter monorepo that builds on at least one desktop and one mobile target.

**Tasks**:
1. Create Flutter app under `apps/strathvision`.
2. Add basic local storage (SQLite via Drift or equivalent).
3. Implement empty Library and Workspace screens that navigate.
4. Add placeholder for profile import (file picker that accepts a profile package and stores metadata).

**Acceptance**:
- App launches on macOS or Windows and on iOS or Android simulator.
- User can import a dummy profile JSON and see its metadata listed.
- No analysis code yet.

**Forbidden**:
- Adding video playback in this phase.
- Adding any timber- or lifting-specific strings outside pack placeholders.

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

**Acceptance**:
- User can load two clips, align them in under 15 seconds, play locked at 0.25x, and re-open the project with the sync still intact.
- Frame stepping works on the locked pair.
- All operations match the Workspace Events contract in INTERFACES.md.

**Forbidden**:
- Any scoring or profile comparison in this phase.
- Cloud upload of videos.

## Phase 3 — Analysis Runtime Skeleton

**Goal**: Clean interface from Flutter to an analysis backend that can produce a Metric Vector from a clip (even if pose is stubbed).

**Tasks**:
1. Define the analysis engine package with the contracts from INTERFACES.md.
2. Implement a stub pose + phase + metric path that returns a valid Metric Vector for a test clip.
3. Wire “Analyze” button in Workspace to call the stub and display raw metrics.

**Acceptance**:
- Clicking Analyze on a clip produces a Metric Vector that validates against the schema.
- Failure cases return the Error Contract.

## Phase 4 — Profile Builder (Laptop)

**Goal**: User can build a real profile artifact from reference clips.

**Tasks**:
1. Implement clip import and quality evaluation.
2. Implement profile fitting (center, spread, weights) from Metric Vectors.
3. Implement quality gates including self-consistency check.
4. Export a versioned profile package matching the contract.

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

**Acceptance**:
- Scoring is deterministic for the same inputs.
- Top deltas correctly identify the largest measured differences.
- Low-confidence inputs produce warnings, not silent high scores.

## Phase 6 — Timber Pack

**Goal**: First real domain pack.

**Tasks**:
1. Define phases and initial metric catalog for underhand and standing block (or chosen events).
2. Add pack configuration that the engine loads.
3. Validate that comparison works with timber-specific metrics.

**Acceptance**:
- Engine code contains zero timber-specific strings or logic.
- Pack can be swapped without recompiling the comparison engine.

## Phase 7 — Drift & Polish

**Goal**: History of match scores and basic UX hardening.

**Tasks**:
1. Drift view for an athlete + profile + event.
2. Profile health indicators.
3. Export/import of profile packages between laptop and phone.

**Acceptance**:
- User can see match trend over multiple sessions.
- Profile packages move between devices without cloud.

## Global Rules for All Phases

- Every task must have automated tests for its acceptance criteria where feasible.
- No new top-level concepts without updating INTERFACES.md first.
- Video files never leave the device unless the user explicitly exports them.
- If a requirement is ambiguous, stop and ask rather than inventing behavior.

## Definition of Done for v1

- Dual-video workspace meets Phase 2 acceptance on at least one desktop and one mobile platform.
- User can build a profile on laptop and score clips against it on phone.
- All scores are inspectable via ranked deltas.
- Timber pack exists and is not hard-coded into the engine.
- No required accounts or cloud services.
