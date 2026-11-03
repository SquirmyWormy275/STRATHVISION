# STRATHVISION Architecture

## Purpose

STRATHVISION is a local-first athletic video analysis workstation with an inspectable style-matching engine.

Primary product: excellent dual-video review (independent scrub, set-sync-point, locked playback, mirror, variable speed, frame step).

Secondary product: pack-driven comparison of a swing/lift against private coach or mentor profiles, producing ranked, inspectable deltas.

Timber is the first pack. Olympic lifting is the second. The core never hard-codes either.

## Non-Negotiable Invariants

1. The dual-video workspace is usable and excellent even if the analysis engine is disabled or fails.
2. Analysis is pack-driven. The engine does not contain timber- or lifting-specific logic.
3. Coach/mentor profiles are versioned, inspectable artifacts. They are built on a capable machine and consumed on mobile.
4. Every match score is accompanied by ranked deltas that reference explicit metric definitions, user values, and coach ranges.
5. A profile is not marked ready until it passes defined quality gates (minimum clean clips, self-consistency check).
6. No required accounts or cloud. All primary data lives on the user’s devices. Transfer of profiles is user-controlled.
7. Confidence and coverage are first-class. Low-quality pose or phase detection must degrade results visibly, never silently.
8. Interfaces are strict. Implementation may not invent new top-level concepts without updating the contracts in INTERFACES.md.

## High-Level System

```
┌──────────────────────────────────────────┐
│  Flutter Application (all platforms)     │
│  - Local library & projects             │
│  - Dual-video workspace                 │
│  - Analysis result & delta views        │
│  - Profile consumption                  │
│  - Drift history                        │
└──────────────────────────────────────────┘
                    │
                    │ uses
                    ▼
┌──────────────────────────────────────────┐
│  Analysis Runtime (shared)              │
│  - Pose estimation (replaceable)        │
│  - Phase detection (pack-driven)        │
│  - Metric extraction (pack-driven)      │
│  - Style comparison engine              │
│  - Profile fitting                      │
└──────────────────────────────────────────┘
                    │
         ┌──────────┴──────────┐
         ▼                     ▼
┌──────────────┐     ┌──────────────┐
│ Timber Pack    │     │ Oly Lifting  │
│ (first)        │     │ Pack         │
└──────────────┘     └──────────────┘
```

## Device Roles

- **Laptop / desktop**: Full library management, profile building, batch processing, deeper inspection. Primary place for heavy analysis and quality gates.
- **Phone**: Capture, dual-video review, scoring against installed profiles, drift view. Consumes finished profile packages. Does not build profiles from scratch in v1.

Transfer of profile packages is explicit (export/import or local network). No silent cloud sync.

## Technology Constraints

- UI: Flutter (single codebase for iOS, Android, macOS, Windows, Linux).
- Local storage: SQLite (Drift or equivalent) + filesystem for videos and profile packages.
- Pose estimation: replaceable backend. Start with a strong off-the-shelf 2D model. Do not hard-code a single provider deep into the engine.
- Analysis engine: must expose a clean interface consumable from Flutter. Language of the engine core is implementation detail; contracts are not.

## Pack Model

A pack defines:
- Ordered phases and detection rules/hints
- Metric catalog (definitions, units, version)
- Default weights for style matching
- Profile schema extensions if needed
- Filming guidance and quality heuristics
- UI labels

The comparison engine only knows how to compare feature vectors against profiles according to the active pack’s schema. It contains no domain vocabulary.

## Profile Lifecycle

1. User imports reference clips for a coach + event on laptop.
2. System runs pose → phase → metrics.
3. Quality gates are evaluated (clip count, detection confidence, self-consistency).
4. If gates pass, a versioned profile artifact is produced.
5. Profile is exported and imported to phone (or used locally).
6. Phone scores new clips against the installed profile and stores results for drift.

Profiles are immutable once published. Updates create a new version.

## Failure Modes That Must Be Explicit

- Insufficient clean reference clips
- Low pose confidence on critical frames
- Phase detection failure
- Missing required metrics for the pack
- Profile version mismatch with current metric definitions

These must surface as structured errors or degraded results, never as confident scores.

## Out of Scope for Architecture v1

- Multi-user collaboration
- Server-side training or inference
- Learned style embeddings (explicit metrics + statistical profiles only)
- Automatic drill prescription
- Live streaming or multi-device simultaneous capture
