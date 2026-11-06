# STRATHVISION

**Review athletic technique locally. Compare clips, inspect measurements, and test whether bounded model updates help.**

STRATHVISION is a Flutter prototype for athletes and coaches working with technique video. Its dual-video workspace works without AI: align two clips, play them together in slow motion, step through frames, and save feedback. Optional local analysis compares movement with a private reference profile and shows the measurements behind the score.

The engineering contribution is a complete path from video review to a versioned, inspectable analysis package: a cross-platform client, a shared Dart engine, declarative sport packs, and a desktop research workbench. CARNE ASADA investigates whether small, constrained model edits can improve agreement with genuine coaching feedback. **That learning benefit has not been established.**

## Start here

1. [Try the review workflow](docs/GETTING_STARTED.md): two bundled test clips, sync, slow motion, marks, and reopening a project.
2. [Set up and run the app](apps/strathvision/README.md), or [download a test build](docs/DISTRIBUTION.md).
3. [Understand the architecture](docs/ARCHITECTURE.md), then follow the [learning guide](docs/wiki/Home.md).
4. [Inspect results and failures](docs/RESEARCH_STATUS.md), [validation](docs/VALIDATION.md), and the [prioritized roadmap](docs/ROADMAP.md).

## What works, and what remains experimental

| Area | Current scope | Evidence and limits |
|---|---|---|
| Video review | Two players, sync, slow motion, stepping, mirror, saved projects and red/green marks | [Real-decoder checks](apps/strathvision/integration_test/real_player_test.dart); physical-device acceptance remains open |
| Local analysis | Person selection, BlazePose/ONNX, phases, metrics and profile comparison | [Native pose test](apps/strathvision/integration_test/real_pose_test.dart); implement position is a **grip/forearm proxy**, not detected tool position |
| Private profiles | Desktop fitting, quality gates, versioned file transfer, phone inference | [Builder](packages/analysis_engine/lib/src/builder.dart); renamed copies count once, but different files are not necessarily independent sessions |
| Inspectable comparison | Score decomposition, confidence-aware ordering, warnings and historical results | [Comparison tests](packages/analysis_engine/test/compare_test.dart); confidence is heuristic, not calibrated uncertainty or a technique grade |
| Research workbench | Specialist patches, optional adapter compilation, bounded CARNE ASADA updates | [Research records](docs/CARNE_RUN_REPORT.md); synthetic tests establish software behavior, not coaching improvement |

The latest full-duration study processed **47 recordings in 195 windows** with no failed windows. Contact-timing diagnostics still matched only **2 of 15** annotated contacts. The committed population-review snapshot contains no coach judgments and establishes no learning improvement. Axe detectors failed validation; the barbell pilot remains research-only. Read the [study reports](docs/RESEARCH_STATUS.md) before using analysis as evidence about technique.

## Design decisions worth inspecting

- **Local-first:** core review and inference require no account, cloud storage, or hosted model. Optional adapter compilation uses an explicitly configured external provider on desktop.
- **One runtime:** Flutter hosts the UI; `packages/analysis_engine` is pure Dart on both desktop and phone. Python tools evaluate research datasets separately.
- **Explainable failure:** rejected footage, ambiguous athletes and uncertain orientation stay visible. Fitting cannot silently accept an unresolved person selection.
- **Portable evidence:** packages contain profiles and optional patches/adapters. Marks carry event and source-content identity; filenames cannot attach feedback to unrelated video.
- **Separate research from product claims:** private footage stays outside Git. Reports publish methods, aggregate results, hashes and limitations, including zero-edit runs and failed models.

## Repository map

| Path | Purpose |
|---|---|
| [apps/strathvision](apps/strathvision) | Flutter app, storage, native playback and pose integration |
| [packages/analysis_engine](packages/analysis_engine) | Contracts, metrics, profile fitting, comparison and bounded updates |
| [apps/strathvision/assets/packs](apps/strathvision/assets/packs) | Event definitions; Springboard remains provisional |
| [tools/carne_asada](tools/carne_asada) | Python ingestion, evaluation and private-feedback workflows |
| [docs/experiments](docs/experiments) | Reproducible research reports and published aggregate results |
| [.github/workflows/builds.yml](.github/workflows/builds.yml) | PR checks, test coverage reports, research tests, native Linux smoke and five platform builds |

This is a testable prototype, not a validated coaching product. Desktop fits and edits profiles; phones review, annotate and run installed packages. See [contribution guidance](CONTRIBUTING.md) and [model/media attribution](apps/strathvision/integration_test/assets/ATTRIBUTION.md).
