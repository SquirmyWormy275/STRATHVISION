# STRATHVISION

**Review athletic technique on your own machine. Compare clips side-by-side, slow them down, mark what matters, and optionally measure movement against a private reference profile.**

STRATHVISION is a local-first Flutter app for athletes and coaches. The core dual-video workspace needs no account, no cloud, and no AI: align two clips, play them together in slow motion, step through frames, mirror one side, and save red/green marks with feedback. Optional on-device analysis uses pose estimation to compare movement against a private profile you control and shows the measurements behind any score.

It is a testable prototype, not a validated coaching product. Desktop can fit and edit profiles; phones review, annotate, and run installed packages. Analysis results are inspectable and limited; they are not a technique grade.

## What you can do today

- Sync and review two technique clips together (slow motion, frame stepping, mirror, saved projects)
- Add red/green marks and feedback that stay tied to the actual video content
- Run optional local analysis (person selection, phases, metrics, profile comparison)
- Keep everything private: core review and inference require no account or hosted model

[Try the review workflow](docs/GETTING_STARTED.md) with the bundled test clips, or [set up and run the app](apps/strathvision/README.md) / [download a test build](docs/DISTRIBUTION.md).

## What works, and what remains experimental

| Area | Current scope | Evidence and limits |
|---|---|---|
| Video review | Two players, sync, slow motion, stepping, mirror, saved projects and red/green marks | [Real-decoder checks](apps/strathvision/integration_test/real_player_test.dart); physical-device acceptance remains open |
| Local analysis | Person selection, BlazePose/ONNX, phases, metrics and profile comparison | [Native pose test](apps/strathvision/integration_test/real_pose_test.dart); implement position is a **grip/forearm proxy**, not detected tool position |
| Private profiles | Desktop fitting, quality gates, versioned file transfer, phone inference | [Builder](packages/analysis_engine/lib/src/builder.dart); renamed copies count once, but different files are not necessarily independent sessions |
| Inspectable comparison | Score decomposition, confidence-aware ordering, warnings and historical results | [Comparison tests](packages/analysis_engine/test/compare_test.dart); confidence is heuristic, not calibrated uncertainty or a technique grade |
| Research workbench | Specialist patches, optional adapter compilation, bounded CARNE ASADA updates | [Research records](docs/CARNE_RUN_REPORT.md); synthetic tests establish software behavior, not coaching improvement |

The latest full-duration study processed **47 recordings in 195 windows** with no failed windows. Contact-timing diagnostics still matched only **2 of 15** annotated contacts. The committed population-review snapshot contains no coach judgments and establishes no learning improvement. Axe detectors failed validation; the barbell pilot remains research-only. Read the [study reports](docs/RESEARCH_STATUS.md) before using analysis as evidence about technique.

CARNE ASADA investigates whether small, constrained model edits can improve agreement with genuine coaching feedback. **That learning benefit has not been established.**

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
| [tools/datasets](tools/datasets) | Sport-agnostic read-only inventory, private manifests and reviewed split safeguards |
| [tools/carne_asada](tools/carne_asada) | Python ingestion, evaluation and private-feedback workflows |
| [docs/experiments](docs/experiments) | Reproducible research reports and published aggregate results |
| [.github/workflows/builds.yml](.github/workflows/builds.yml) | PR checks, test coverage reports, research tests, native Linux smoke and five platform builds |

See [contribution guidance](CONTRIBUTING.md) and [model/media attribution](apps/strathvision/integration_test/assets/ATTRIBUTION.md). For architecture and deeper reading: [ARCHITECTURE.md](docs/ARCHITECTURE.md), [learning guide](docs/wiki/Home.md), [validation](docs/VALIDATION.md), and the [roadmap](docs/ROADMAP.md).
