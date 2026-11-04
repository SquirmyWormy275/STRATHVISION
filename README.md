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
- **Cross-platform** — Flutter UI for iOS, Android, Windows, macOS, Linux. The analysis engine is a pure-Dart package (`packages/analysis_engine`) shared by phone and desktop (see docs/DECISIONS.md, Phase 3).

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

The downloaded Gurr Academy archive has now been processed locally: **12 videos, 29 min 3.6 s**, including every competition and training video in this download. The first recorded experiment is anonymous multi-person ingestion plus a no-feedback control; it does not claim improved technique analysis or named-athlete recognition.

### Recorded results on November 4 2026

| Measurement | Result |
|---|---:|
| Sampled frames at 5 fps | 8,718 |
| Person detections | 10,364 |
| Pose samples passing model presence gate | 7,541 |
| Frames with multiple detected people | 1,608 |
| Underhand candidate pass: strokes passing current pack gates | 26 of 151 |
| Standing-block candidate pass: strokes passing current pack gates | 9 of 159 |
| Accepted edits with no supplied coach marks | **0** |

Both event packs were stress-tested on every clip, so candidate counts are not human-validated event counts. Spectators, rotated video, fragmented tracks and a grip-based implement proxy limit interpretation. Underhand met Good but correctly stopped at “no marks”; standing block remained below Good. No marks were fabricated, no coach-specific profile was declared ready, and no improvement is claimed.

Read the [method, limitations and reproduction commands](docs/experiments/Gurr-Academy.md), or inspect the [full recorded results and source hashes](docs/experiments/gurr-20261104-results.json). Raw footage and contact sheets stay local. The same work fixes destructive exemplar edits, retains merged coach evidence, shares prototype scoring between research and inference, and splits missing-pose gaps before stroke detection.

The following protocol remains the planned coach-specific learning experiment once identity/event ground truth and genuine feedback are available.

### How to run it

Prerequisites:
- A desktop build (docs/DISTRIBUTION.md).
- The footage on that computer.
- The real 3D pose path and an independently validated implement tracker. The current grip-derived implement is a proxy, and coach-specific results require confirmed athlete/event labels.

1. **Choose the event.** In the Library, pick **Underhand** (later **Standing block**) from the event menu in the top bar.
2. **Build each coach's profile.** For each of Matthew Gurr and Daniel Gurr, tap **Build a profile** (person-plus icon), name it, and add that coach's clips for the event. Every clip reports Clean or why not. **Build profile** needs 15+ clean clips that pass self-consistency. Record the clip counts it reports.
3. **Optional: marks.** Review clips in a workspace and add green/red **Slope** marks on strokes. CARNE ASADA binds marks from any review of the same file to the stroke at that time. Coach marks override athlete marks.
4. **Feed CARNE ASADA.** Open the profile's **Workbench** (tune icon) → **CARNE ASADA**. Priority starts at slope (a text note `priority: spacing` or `priority: hinge` changes it before the first edit). Drop the whole set onto **Feed CARNE ASADA**. Record each status line.
5. **Let it run.** Updates are tried automatically once usable footage passes Good (2 min), and **Look for an update** tries again. It stops at the session limit. **What did it just do?** lists every explanation, and **Undo** is one click.
6. **Save as vN+1.** The package gets `carne_asada/mixture_edits_vN.json` holding the priority, usable minutes, the coach hull, and every edit (before/after values, objective before/after, explanation, time).
7. **Publish** the numbers above from that file, plus the profile versions.
   - Usable strokes: the "Found N strokes. K are clean enough…" lines.
   - Accepted edits: the `edits` count.
   - Feedback-agreement objective: `objective_before` of the first edit against `objective_after` of the last. Measure physical residuals separately; these objective values are not angle errors.
   - Explanations: copy each `explanation` verbatim.
   - Hull compliance: every `after.center` lies within `hull`.
   - Raw logs: attach the zip.

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

The `implementation` branch has a working review UI, real local 3D pose path, pack-driven analysis, and research tooling. It remains a prototype with open acceptance criteria; the earlier “all phases implemented” claim does not establish a complete v1. The implement direction is still a grip/forearm proxy. Live progress and open checks are in [docs/handoff/STATUS.md](docs/handoff/STATUS.md). App usage and manual checks are in [apps/strathvision/README.md](apps/strathvision/README.md). Test builds are described in [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).

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
