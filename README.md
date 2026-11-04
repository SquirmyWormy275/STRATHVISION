# STRATHVISION

**Local-first athletic video analysis with inspectable style matching and weight-space programming.**

STRATHVISION is a dual-video workstation and pack-driven analysis engine for technique sports. The visual review tools are excellent on their own. The AI layer is constrained, versioned, fully inspectable, and includes local weight-space programming so models can actually improve from feedback.

This repository answers a research question while remaining a usable product.

## Research Question

**Can a local, evidence-bounded weight-space programming loop improve a sports technique model over time without full retraining, cloud infrastructure, or drifting outside coach-derived bounds?**

Secondary claims tested by the system:
- Sparse LLM-directed edits on specialist nets can fix concentrated failure modes faster than gradient steps on the same data.
- Compile-once adapters for fuzzy decisions (usable footage, attribute priority, event classification) match or beat hand-written rules while staying fully local.
- A constrained recursive loop (CARNE ASADA) on a phase-conditioned Gaussian mixture + residual exemplars can compound attribute-specific improvement from red/green + coach marks without context stuffing.

## What it is

- **Dual-video workspace** — independent scrub, set-sync-point, locked playback, mirror, variable speed, frame-accurate step. Usable without any analysis.
- **Private coach/mentor profiles** — built from an athlete’s own reference footage on a laptop, consumed on phone. No public marketplace, no required accounts.
- **Pack-driven style matching** — timber first, Olympic lifting second. The engine contains no domain-specific logic; packs supply phases, metrics, and weights.
- **Inspectable AI + weight-space programming** — every match score produces ranked deltas. Specialist nets accept sparse patches. Fuzzy decisions compile once into local adapters. CARNE ASADA (desktop-only) recursively edits the style mixture under hard bounds.
- **Cross-platform** — Flutter UI for iOS, Android, Windows, macOS, Linux. Rust core + Python for analysis and editing.

## Device Roles

- **Phone (iOS + Android)**: inference only. Loads coaching packages, runs specialist nets + compile-once adapters, dual-video UI, red/green, light updates. No weight editing.
- **Desktop workbench (Windows, macOS, Linux)**: ingest, specialist-net harness, compile-once adapter generation, full CARNE ASADA research loop. Primary place for heavy work.

Packages move between devices via local/wireless transfer (AirDrop, shared folder, QR, etc.). No required cloud.

## Distribution for Testing

- **Android**: release APK/AAB sideload.
- **iOS**: ad-hoc provisioning (register device UDIDs, signed IPA + profile). Cap 100 devices.
- **Desktop**: zip of the Flutter build. Unzip and run.
- Coaching packages are ordinary files. Send them the same way you send videos.

## CARNE ASADA (Desktop-Only Research Project)

CARNE ASADA is the recursive weight-space editor for the phase-conditioned Gaussian mixture + residual exemplars. It is nested inside the app ecosystem but **not required** for the athlete-facing product.

- Drop-zone playground: drag videos, packages, voice notes, or notes. Instant plain-language status.
- Hard constraints: max 5–10 accepted edits per session, priority-attribute only, must stay inside coach hull (or soft personal pull), low-quality clips ignored until threshold, full versioning + soft revoke.
- Every accepted edit produces a one-sentence explanation and is logged.

Status messages and edit explanations are specified in docs/DECISIONS.md.

## Experiment: CARNE ASADA on the Gurr Footage

After a working desktop build exists, upload **all** race and training footage of Matthew Gurr and Daniel Gurr (every underhand, single buck, and standing block clip).

Drop the entire set into the CARNE ASADA playground with priority set to slope (then optionally spacing and hinge). Let it run.

Results published in this section:
- Total usable strokes ingested per coach and per event
- Number of accepted mixture edits
- Before/after residual on the priority attribute
- Exact one-sentence explanations for every accepted edit
- Whether the final mixture stayed inside the original coach hull
- Raw logs and versioned package for reproduction

No cherry-picking. Date, footage count, and numbers go here.

## Repository map

| Document | Purpose |
|----------|---------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Boundaries, invariants, device roles, weight-space layers |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Binding architectural decisions |
| [docs/INTERFACES.md](docs/INTERFACES.md) | Exact schemas and contracts |
| [docs/EXECUTION_PLAN.md](docs/EXECUTION_PLAN.md) | Gated, foolproof implementation plan |
| [docs/CARNE_ASADA.md](docs/CARNE_ASADA.md) | Research project specification |
| [docs/wiki/](docs/wiki/) | Longer-form explanations |

## Current status

Architecture, contracts, specialist net, CARNE ASADA, distribution, and execution plan are locked. Implementation has not started. The plan produces a usable dual-video product before any analysis or research code.

## For reviewers

1. Read the research question and invariants.
2. Check that INTERFACES.md and DECISIONS.md define failure modes, quality gates, and bounds rather than only happy paths.
3. Note that the first usable product is the dual-video workspace.
4. CARNE ASADA is explicitly research and non-blocking.

## Non-goals

- Required accounts or cloud storage for core loop
- Public coach marketplace or social features
- Free-form generative coaching chat as the primary interface
- Live multi-cam cloud streaming
- CARNE ASADA on mobile
