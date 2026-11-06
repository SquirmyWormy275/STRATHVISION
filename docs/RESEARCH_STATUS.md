# Research status and recorded results

These are prototype results, including failed experiments. The source-linked reports below preserve their original study boundaries. See the [roadmap](ROADMAP.md) for promotion criteria and [project introduction](../README.md) for the application.

## CARNE ASADA (Desktop-Only Research Project)

CARNE ASADA is the recursive weight-space editor for the phase-conditioned Gaussian mixture + residual exemplars. It is nested inside the app ecosystem but **not required** for the athlete-facing product.

- Drop-zone playground: drag videos, packages, voice notes, or notes. Instant plain-language status.
- Hard constraints: max 5–10 accepted edits per session, priority-attribute only, must stay inside coach hull (or soft personal pull), low-quality clips ignored until threshold, full versioning + soft revoke.
- Every accepted edit produces a one-sentence explanation and is logged.
- Videos use SHA-256 content IDs: copies and renames count once, while repeated drops refresh review marks. Same-named recordings remain independent.
- The current stop reason stays visible, including insufficient usable footage and missing feedback. **Save experiment** exports inputs, settings, outcomes and loop attempts even when no edits were accepted; **Save as vN+1** is reserved for accepted edits. See the [experiment record format](CARNE_RUN_REPORT.md).

Status messages and edit explanations are specified in docs/DECISIONS.md.

Application evidence: [controller/widget regression tests](../apps/strathvision/test/carne_run_test.dart) cover duplicates, mark refresh, failures, stop states and export retries; [native Linux checks](../apps/strathvision/integration_test/carne_run_flow_test.dart) save a zero-edit report and verify content-keyed pose caching. Export/UI fixtures are explicitly synthetic. The real-footage research results follow below.

Competitor tracking now offers correction inside CARNE and pauses when a selection is uncertain. A four-second preview asks for uncertain competitors before full processing; its desktop sampling budget preserves swing timing on long recordings. The [local feedback review workflow](FEEDBACK_REVIEW.md) collects real stroke judgments and supports a source-disjoint learning replay; it is ready for field use, with coaching effectiveness still unvalidated.

## Experiment: CARNE ASADA on the Gurr Footage

**All five downloaded ZIPs are verified, extracted and processed.** The `20261104T223331Z` export contains **48 video files and seven photos**. One video is an exact duplicate, leaving **47 unique videos, 2 h 9 min 47.4 s**, including recordings lasting 28:39, 17:55, 15:10 and 12:06. The [five-part inventory](experiments/gurr-20261104-five-part-inventory.json) records archive hashes, folder coverage and the excluded duplicate.

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

Read the [method, limitations and reproduction commands](experiments/Gurr-Academy.md), inspect the [expanded results and source hashes](experiments/gurr-20261104-five-part-results.json), or compare the [original subset results](experiments/gurr-20261104-results.json). Raw footage, contact sheets and per-frame poses stay local. The research work fixes destructive exemplar edits, retains merged coach evidence, shares prototype scoring between research and inference, and splits missing-pose gaps before stroke detection.

### Checked tracking and timing pilot

A separate 80-second pilot uses ten source recordings, frozen visual references and five reserved test windows. On those test windows, the revised research pipeline improved sparse target coverage from **20/25 to 24/25 checkpoints** and orientation from **4/5 to 5/5 windows**. The committed engine still matched **0/15** annotated contacts. An experimental wrist-motion proxy matched only **3/15**, added five false detections and remains research-only.

Read the [evaluation protocol, frozen sources, test results and failures](experiments/Gurr-Accuracy.md). These single-reviewer results measure a small tracking/timing pilot; they do not establish coaching accuracy or learning gains. A separate check of the existing standing-block phase candidate matched three contacts on fresh training footage, with one extra detection and about 0.2 s delay. Its tested patch and the limited follow-up evidence are included in the report; it remains experimental.

The following protocol remains the planned coach-specific learning experiment once identity/event ground truth and genuine feedback are available.

### Current engine and axe-detector follow-up

The [full-duration native study](experiments/Gurr-Population.md) is complete: **all 47 unique videos, 2 h 9 min 47 s**, processed in **195 bounded windows**, with **207,987 pose samples inside scored cores** and zero failed windows. The [source coverage ledger](experiments/evaluation/population/gurr-full-windowed-results.json) accounts for every source tail. Expanding the scan found and fixed an early exit that discarded recordings with quiet openings; a full-video review packet now offers 960 unreviewed navigation suggestions.

On the same cached poses, the revised phase engine increased standing-block gate-passing candidates **922 → 952**. Existing timing checks remained **2/15 contacts with one extra** and **2/3 with two extras**; these already-opened references are diagnostic. More accepted phases have not established improved contact timing or coaching effectiveness. The full report separates native inference, engine-only replay and the first genuine review workflow. The smaller studies below remain historical results.

The [round-2 report](experiments/Gurr-Round2.md) pins the standing-block engine and publishes diagnostic replays: **1/15** contact matches with two extras on the original test, and **3/3** with one extra on the smaller follow-up. These already-opened references are comparisons, not a new holdout.

Two earlier image-only axe prototypes were trained and evaluated: a HOG/linear-SVM baseline and a COCO-pretrained SSDLite model with locally fitted detection heads. Both failed validation. Frozen test results were **0/16** visible axe heads for HOG and **0/8** on four newly reserved recordings for SSDLite. Uncertain/occluded frames were unrated. Code, coarse single-reviewer annotations, model coefficients/weights, source hashes and failures are published in the report. The axe prototypes remain research-only; the app still uses its disclosed grip proxy for implement measurements.

The [additional event and early-training study](experiments/New-Footage.md) adds **55 new videos from four verified archives**, with capture-day groups split into 36 training, 13 validation and six test recordings. A Faster R-CNN prototype trained for 1,000 CUDA steps using 35 visible-head images and three clear empty frames. Its frozen test found **1/9 visible heads**, with one incorrect retained box and eight misses; 15/24 test frames were unrated. [Weights, engineering references, hashes and results](experiments/evaluation/new-footage/results.json) are published. Inference requires a manually supplied broad athlete region. This remains a failed research prototype; it does not provide named-athlete identification or improved coaching measurements.

A separate native Flutter diagnostic completed all thirteen existing pilot/follow-up windows. Its original test matched **4/15** contacts with three extras; all matches were underhand, while the standing-block heat deferred to competitor selection. One follow-up rear view also showed a large target mismatch without an ambiguity flag. The [native result and limitations](experiments/Gurr-Round2.md#native-app-diagnostic-result) document the tested runtime and remaining failures. These opened references do not establish field coaching accuracy.

### Seagate follow-up: woodchopping and Olympic weightlifting

The [Seagate study](experiments/Seagate-Footage.md) inventories **424 unique videos totaling 16 h 3 min**: 102 existing woodchopping recordings and **322 new weightlifting videos**. All 322 lifting sources passed a three-frame decode/person audit (**966 frames, zero failures**); this is sampled coverage, not full-duration analysis. Downloads continued afterward; 12 later candidates are listed separately.

The study expands axe training supervision from 35 to **73 visible heads**. On the unchanged validation set, matches increased **8 → 11 of 26**, while incorrect boxes increased **2 → 11**. F1 moved only 44.4% → 45.8%; the old test was not reused as a fresh holdout.

A separate full-frame barbell prototype trained for 1,000 CUDA steps on **47 positive and nine negative frames** from 36 uploads. Its frozen 12-upload test found **9/15 visible bars**, with two incorrect boxes and six misses; eight uncertain frames were unrated. Thin unloaded bars remain a major failure case. The report publishes weights, references, source/image hashes, checkpoint history and reproduction steps. Edited uploads can reuse demonstrations, so this is a limited localization pilot, not evidence of independent-session generalization, bar-path accuracy or improved coaching. Both models remain research-only.

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

