# STRATHVISION

**Local-first athletic video analysis with inspectable style matching and weight-space programming.**

STRATHVISION is a dual-video workstation and pack-driven analysis engine for technique sports. Visual review works independently of analysis. Its experimental AI layer records measured differences, versioned profiles and bounded local model edits, with accuracy and learning evidence reported separately below.

This repository answers a research question while remaining a usable product.

## Research Question

**Can a local, evidence-bounded weight-space programming loop improve a sports technique model over time without full retraining, cloud infrastructure, or drifting outside coach-derived bounds?**

Hypotheses for controlled evaluation:
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
- Videos use SHA-256 content IDs: copies and renames count once, while repeated drops refresh review marks. Same-named recordings remain independent.
- The current stop reason stays visible, including insufficient usable footage and missing feedback. **Save experiment** exports inputs, settings, outcomes and loop attempts even when no edits were accepted; **Save as vN+1** is reserved for accepted edits. See the [experiment record format](docs/CARNE_RUN_REPORT.md).

Status messages and edit explanations are specified in docs/DECISIONS.md.

Application evidence: [controller/widget regression tests](apps/strathvision/test/carne_run_test.dart) cover duplicates, mark refresh, failures, stop states and export retries; [native Linux checks](apps/strathvision/integration_test/carne_run_flow_test.dart) save a zero-edit report and verify content-keyed pose caching. Export/UI fixtures are explicitly synthetic. The real-footage research results follow below.

Competitor tracking now offers correction inside CARNE and pauses when a selection is uncertain. A four-second preview asks for uncertain competitors before full processing; its desktop sampling budget preserves swing timing on long recordings. The [local feedback review workflow](docs/FEEDBACK_REVIEW.md) collects real stroke judgments and supports a source-disjoint learning replay; it is ready for field use, with coaching effectiveness still unvalidated.

## Experiment: CARNE ASADA on the Gurr Footage

**All five downloaded ZIPs are verified, extracted and processed.** The `20261104T223331Z` export contains **48 video files and seven photos**. One video is an exact duplicate, leaving **47 unique videos, 2 h 9 min 47.4 s**, including recordings lasting 28:39, 17:55, 15:10 and 12:06. The [five-part inventory](docs/experiments/gurr-20261104-five-part-inventory.json) records archive hashes, folder coverage and the excluded duplicate.

### Recorded results on November 4 2026

Both runs use the same committed analysis engine. The earlier 12-video archive part remains a historical subset; the expanded run processes all 47 unique recordings from the five-part download.

| Measurement | Earlier 12-video subset | Five-part export: 47 unique videos |
|---|---:|---:|
| Sampled frames at 5 fps | 8,718 | 38,941 |
| Person detections | 10,364 | 63,317 |
| Pose samples passing model presence gate | 7,541 | 50,637 |
| Frames with multiple detected people | 1,608 | 15,337 |
| Underhand candidate pass: strokes passing current pack gates | 26 of 151 | 260 of 1,165 |
| Standing-block candidate pass: strokes passing current pack gates | 9 of 159 | 65 of 991 |
| Accepted edits with no supplied coach marks | **0** | **0** |

Both event configurations were stress-tested on every recording, so candidate counts are not human-validated event counts. Spectators, rotated video, fragmented tracks and a grip-based implement proxy limit interpretation. Expanded controls: underhand **Good threshold met; no marks; zero edits**; standing block **Good threshold met; no marks; zero edits**. No coach-specific profile was declared ready and no improvement is claimed.

Read the [method, limitations and reproduction commands](docs/experiments/Gurr-Academy.md), inspect the [expanded results and source hashes](docs/experiments/gurr-20261104-five-part-results.json), or compare the [original subset results](docs/experiments/gurr-20261104-results.json). Raw footage, contact sheets and per-frame poses stay local. The research work fixes destructive exemplar edits, retains merged coach evidence, shares prototype scoring between research and inference, and splits missing-pose gaps before stroke detection.

### Checked tracking and timing pilot

A separate 80-second pilot uses ten source recordings, frozen visual references and five reserved test windows. On those test windows, the revised research pipeline improved sparse target coverage from **20/25 to 24/25 checkpoints** and orientation from **4/5 to 5/5 windows**. The committed engine still matched **0/15** annotated contacts. An experimental wrist-motion proxy matched only **3/15**, added five false detections and remains research-only.

Read the [evaluation protocol, frozen sources, test results and failures](docs/experiments/Gurr-Accuracy.md). These single-reviewer results measure a small tracking/timing pilot; they do not establish coaching accuracy or learning gains. A separate check of the existing standing-block phase candidate matched three contacts on fresh training footage, with one extra detection and about 0.2 s delay. Its tested patch and the limited follow-up evidence are included in the report; it remains experimental.

The following protocol remains the planned coach-specific learning experiment once identity/event ground truth and genuine feedback are available.

### Current engine and axe-detector follow-up

The [full-duration native study](docs/experiments/Gurr-Population.md) is complete: **all 47 unique videos, 2 h 9 min 47 s**, processed in **195 bounded windows**, with **207,987 pose samples inside scored cores** and zero failed windows. The [source coverage ledger](docs/experiments/evaluation/population/gurr-full-windowed-results.json) accounts for every source tail. Expanding the scan found and fixed an early exit that discarded recordings with quiet openings; a full-video review packet now offers 960 unreviewed navigation suggestions.

On the same cached poses, the revised phase engine increased standing-block gate-passing candidates **922 → 952**. Existing timing checks remained **2/15 contacts with one extra** and **2/3 with two extras**; these already-opened references are diagnostic. More accepted phases have not established improved contact timing or coaching effectiveness. The full report separates native inference, engine-only replay and the first genuine review workflow. The smaller studies below remain historical results.

The [round-2 report](docs/experiments/Gurr-Round2.md) pins the standing-block engine and publishes diagnostic replays: **1/15** contact matches with two extras on the original test, and **3/3** with one extra on the smaller follow-up. These already-opened references are comparisons, not a new holdout.

Two earlier image-only axe prototypes were trained and evaluated: a HOG/linear-SVM baseline and a COCO-pretrained SSDLite model with locally fitted detection heads. Both failed validation. Frozen test results were **0/16** visible axe heads for HOG and **0/8** on four newly reserved recordings for SSDLite. Uncertain/occluded frames were unrated. Code, coarse single-reviewer annotations, model coefficients/weights, source hashes and failures are published in the report. The axe prototypes remain research-only; the app still uses its disclosed grip proxy for implement measurements.

The [additional event and early-training study](docs/experiments/New-Footage.md) adds **55 new videos from four verified archives**, with capture-day groups split into 36 training, 13 validation and six test recordings. A Faster R-CNN prototype trained for 1,000 CUDA steps using 35 visible-head images and three clear empty frames. Its frozen test found **1/9 visible heads**, with one incorrect retained box and eight misses; 15/24 test frames were unrated. [Weights, engineering references, hashes and results](docs/experiments/evaluation/new-footage/results.json) are published. Inference requires a manually supplied broad athlete region. This remains a failed research prototype; it does not provide named-athlete identification or improved coaching measurements.

A separate native Flutter diagnostic completed all thirteen existing pilot/follow-up windows. Its original test matched **4/15** contacts with three extras; all matches were underhand, while the standing-block heat deferred to competitor selection. One follow-up rear view also showed a large target mismatch without an ambiguity flag. The [native result and limitations](docs/experiments/Gurr-Round2.md#native-app-diagnostic-result) document the tested runtime and remaining failures. These opened references do not establish field coaching accuracy.

### How to run it

Prerequisites:
- A desktop build (docs/DISTRIBUTION.md).
- The footage on that computer.
- The real 3D pose path and an independently validated implement tracker. The current grip-derived implement is a proxy, and coach-specific results require confirmed athlete/event labels.

1. **Choose the event.** In the Library, pick **Underhand** or **Standing block** from the event menu in the top bar. **Springboard** currently has provisional metrics for review.
2. **Build each coach's profile.** For each of Matthew Gurr and Daniel Gurr, tap **Build a profile** (person-plus icon), name it, and add that coach's clips for the event. Every clip reports Clean or why not. **Build profile** needs 15+ clean clips that pass self-consistency. Record the clip counts it reports.
3. **Optional: marks.** Review clips in a workspace and add green/red **Slope** marks on strokes. CARNE ASADA binds marks from any review of the same file to the stroke at that time. Coach marks override athlete marks.
4. **Feed CARNE ASADA.** Open the profile's **Workbench** (tune icon) → **CARNE ASADA**. Priority starts at slope (a text note `priority: spacing` or `priority: hinge` changes it before the first edit). Drop the whole set onto **Feed CARNE ASADA**. Record each status line.
5. **Let it run.** Updates are tried automatically once usable footage passes Good (2 min), and **Look for an update** tries again. It stops at the session limit. **What did it just do?** lists every explanation, and **Undo** is one click.
6. **Save experiment**, including runs that stop without edits. The standalone JSON records source hashes, duplicate/error outcomes, settings, usable minutes, stop reason and loop attempts. If edits were accepted, **Save as vN+1** also writes the updated package with `carne_asada/mixture_edits_vN.json` (before/after values, objective, explanation and time).
7. **Publish** the numbers above from the experiment record, plus any saved profile versions. Keep zero-edit outcomes in the results.
   - Usable strokes: the "Found N strokes. K are clean enough…" lines.
   - Accepted edits: the `edits` count.
   - Feedback-agreement objective: `objective_before` of the first edit against `objective_after` of the last. Measure physical residuals separately; these objective values are not angle errors.
   - Explanations: copy each `explanation` verbatim.
   - Hull compliance: every `after.center` lies within `hull`.
   - Raw logs: attach the experiment JSON and any edited package.

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
