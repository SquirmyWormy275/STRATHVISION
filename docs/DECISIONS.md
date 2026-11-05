# STRATHVISION Architectural Decisions

## Reproducible Gurr Academy experiments

[Gurr Academy experiments](experiments/Gurr-Academy.md) defines the real-footage pipeline, anonymous track schema, quality gates and limits on interpreting the published results. Research exemplars use the same prototype scoring in evaluation and inference; gaps in a pose track never count as continuous action.

All decisions below are binding. Later implementation must conform. Do not invent alternatives.

## Core Engine

- Full-body 3D, root-relative, camera-agnostic pose before any metrics or manifold work.
- Implement track is required. Lightweight tracker supplies 3D point or short rigid segment in the same root-relative frame. Low-confidence implement frames drop implement dimensions, skip importance updates on them, and suppress dependent overlays/ghosts. Body-only comparison continues.
- Per-profile online-adapted rigid attachment for implements. Optional one-time photo/video seed for length, offset, and tracking prior. Class-level templates (axe, crosscut, chainsaw, hot saw, barbell, etc.) are required; per-instance refinement is optional. Untagged clips infer class; implement-specific updates only on match.
- Phase labeling is hybrid by default. Athlete/coach can switch between Automatic, Seeded, and Hybrid via dropdown. Corrections are soft bindings that gradually update the detector.
- Stroke boundaries detected from pack-supplied signals (implement-speed peaks + phase transitions). Manual drag/split/merge stored as soft corrections that can update the segmenter.
- Style manifold + counterfactual layer on top of phase-conditioned density. Sparse minimal-change ghost re-projected into the athlete’s camera.
- Shared base layer (body, general ranges, implement classes, cross-event mobility) + per-event overlays (density, importance weights, exemplars, reinforcement history).

## Weight-Space Programming Layers (first-class)

Three layers exist from day one. They are not optional extras.

### 1. Specialist Net Harness (always available on workbench)

- Target day-one net: `slope_residual`.
  - Tiny residual head (2-layer MLP, 64→32, <10k params) on top of base 3D pose + implement tracker.
  - Predicts entry-angle (slope) error relative to coach reference for the current phase.
- Probes (only feedback the harness sees):
  1. `slope_error_deg` — mean absolute slope error vs coach reference.
  2. `slope_bias` — signed mean error (primary target).
  3. `priority_agreement` — fraction of red/green marks on slope that match residual direction.
  4. `phase_stability` — slope variance inside phase (must not increase).
  5. `track_confidence_correlation` — correlation with implement-track confidence.
- Acceptance: slope_bias improves ≥0.8°, slope_error_deg does not regress, phase_stability and track_confidence_correlation within 5%, edit touches <2% of weights.
- Accepted patches stored as versioned residuals in the coaching package. Phone loads them; never edits.

### 2. Compile-Once Adapters

- Fuzzy decisions (usable-footage gates, attribute-priority scoring, event classification) expressed as short English specs in the pack.
- Workbench compiles once into tiny local adapters that ride inside the coaching package.
- Runtime is small on-device model + adapter. Zero ongoing LLM cost.
- Recompiled and pushed when pack or spec changes.

### 3. CARNE ASADA (desktop-only research)

- Recursive weight-space editor for the phase-conditioned Gaussian mixture + residual exemplars.
- Desktop workbench only. Nested research project. Athlete-facing product never depends on it.
- Hard constraints: max 5–10 accepted edits/session, priority-attribute only, stay inside coach hull or soft personal pull, ignore below-threshold clips, full versioning + soft revoke.
- Every accepted edit logged with one-sentence explanation.

See docs/CARNE_ASADA.md for full specification.

## Continuous Learning (parameter updates, not context)

- Density is a phase-conditioned mixture. New clean frames perform discounted online updates to μ and Σ.
- Importance vector w is updated from feedback embeddings. Corrective language raises weights; dismissive language lowers them.
- Residual exemplars store (feature delta, feedback embedding, weight).
- Inference sorts by w-scaled deviation and solves weighted sparse counterfactual. Parameters actually change; behavior changes.
- Recency bias on all bindings. Visual demonstration is ground truth; speech/tags only re-weight or add exemplars.
- Attribute-priority hybrid: session priority isolates learning rate to chosen dimension(s). Green/red marks are per-stroke, per-attribute reinforcement. Coach mark overrides athlete mark; newest coach mark wins. Only the winning label updates parameters.
- Soft personal pull: athlete accepted swings can slightly shift the target inside the coach-supported region at reduced learning rate.
- Multi-coach footage tightens shared directions and leaves style differences as higher variance.

## Phase 2 Workspace Decisions

- Android video output: `vo=mediacodec_embed` with `hwdec=mediacodec`, so MediaCodec decodes straight onto the surface. mpv's GPU output needs an EGL context that some Android GPUs (and the emulator) refuse (`EGL_BAD_ATTRIBUTE`). `frameRate()` polls mpv for up to 3 s, because Android reports `container-fps` late.
- The stage player creates its video controller as soon as it is constructed, and sets `vid=auto` after each open. media_kit disables the video track for files opened with no controller attached, and the stage's Video widget is only built once a clip has loaded. Without this, clips played with no picture: on silent clips nothing moved at all, and on clips with audio you got sound over a black screen. A regression test opens a clip before its view exists; it was confirmed to fail with the fix removed.
- Video engine: media_kit (libmpv) on all five platforms. Seeks are exact (`hr-seek=yes`). Frame step snaps to the frame grid (`container-fps`) and exact-seeks one frame, which is deterministic forward and back. mpv `frame-step` did not advance reliably through media_kit.
- Locked playback: stage A is the clock. Stage B is held at `A + offset_ms`. Every 250 ms during locked play: under 40 ms of drift is left alone, 40–250 ms is closed by nudging B's speed (closing the gap in about 0.5 s of wall time, capped at ±50% of the rate), and over 250 ms gets a hard seek. B is hard-aligned after every user seek, step, rate change, and pause. Hard-seeking small drift stalls the decoder and makes drift worse (measured on libmpv).
- Until segmentation exists, "current stroke" means the current timestamp on the active stage. Marks keep `stroke_index: null` and are re-bound to strokes once segmentation lands.
- Attribute chips come from the active pack. Before Phase 6, a neutral placeholder pack supplies the list. No domain words appear in app code.
- Undo is one tap and covers marks, annotations, sync changes, and clip loads within the open session.

## Phase 3 Analysis Runtime Decisions

- The analysis runtime is a pure-Dart package, `packages/analysis_engine`, shared by the phone and the workbench. It holds the INTERFACES.md contracts and validators, the pipeline stage interfaces (pose estimator, implement tracker, phase detector), generic metric extraction, the 64-wide feature vector, and specialist heads.
- The app runs the engine on a background isolate, so the UI keeps rendering during analysis. The workspace stays fully usable when analysis fails or is never run.
- Phase 3 stages are stubs, marked as stubs in code and in the UI:
  - The pose stub makes a deterministic skeleton seeded by `clip_id` and does not read video.
  - The implement stub follows the wrists.
  - The phase stub splits the clip evenly across the pack's phases at confidence 0.5.
  - Real models replace these behind the same interfaces from Phase 4 on.
- The `slope_residual` stub has the binding shape: a 64→32 ReLU MLP with 1 output and 2,113 parameters. Its weights are fixed and seeded, so its output is a number but not yet a meaningful residual. Real weights and patches arrive in Phase 6.
- Long clips are pose-sampled at a stride, up to 1,800 samples per clip. Phase frames still refer to the clip's own frame indices.
- Analyze works on the clip on the active stage. Results are kept per clip for the open session only. Storing results for drift starts in Phase 5.

## Phase 4 Profile Builder Decisions

- The builder lives in `packages/analysis_engine` (`ProfileBuilder`), so the phone and the workbench share it. DECISIONS says coaches can do everything on the phone, so the Build a profile screen is on every platform.
- Fitting:
  - center = mean.
  - spread = sample SD, floored at the metric's `min_spread` (and never 0).
  - weight = pack default weight × the metric's mean confidence, rescaled so weights average 1.
- Self-consistency is leave-one-out, as described in INTERFACES.md Quality Gates. Because spreads are fitted from the clips themselves, held-out scores without a `min_spread` tolerance sit around 0.6–0.7 for most footage, so the gate only discriminates once a pack sets a `min_spread` tolerance. This is covered by tests: one synthetic coach passes and mixed footage fails at threshold 0.8 with `min_spread` 1.0.
- Defaults are provisional until the human confirms them (see STATUS Blockers):
  - `min_clips` 15 (from INTERFACES.md)
  - `min_critical_pose_confidence` 0.6
  - `self_consistency_threshold` 0.5
- A ready profile is stored as a zip under app support (`profiles/<id>_v<version>.zip`), re-read through the importer, and listed in the Library. "Save a copy" exports the same zip anywhere.
- Rebuilding from a previous profile keeps `profile_id` and increments `version`.
- Clip duration and frame rate come from a headless media_kit player. With no video controller attached, media_kit sets `vid=no` and mpv never reports the frame rate, so the probe sets `vid=auto` with `vo=null`.
- Synthetic clips come from the stub pose with a style seed and up to 3% jitter per clip. The Phase 4 acceptance allows synthetic clips.

## Phase 5 Style Comparison Decisions

- `compare()` in `packages/analysis_engine` implements the INTERFACES.md "Comparison rules". A delta's contribution is its weighted share of the score lost, so the ranking is the largest weighted measured differences. Ties are broken by metric key, which keeps the result deterministic.
- Low confidence (below 0.6, for phases, metrics or the pose summary) adds warnings and never changes the score. The stub phase detector reports 0.5, so every result carries a "phase timing is uncertain" warning until a real detector lands. This is intended.
- In the Analysis panel, "Compare with" lists ready profiles for the active pack's event, and the newest is selected by default. "Nobody" shows measurements only. Changing the profile re-analyzes the clip so that profile's patches apply.
- Patches: when a profile is selected, its package's `specialist_patches/` are parsed against the base heads, and the highest valid version per head is applied inside the analysis isolate. Rejected patches are skipped and named in the result's warnings. `applied_patches` lists what was applied.
- Every successful comparison is stored in the `comparison_rows` table (exact Comparison Result JSON, plus project id and time) for drift tracking in Phase 9. Measurement-only runs are not stored.
- Expanded deltas show the metric definition, generated generically from the pack entry (kind, joints, phase label), plus this clip's value, the coach's center ± spread, and the phase. Wording is a direct translation of the measured delta ("Higher than coach · 1.8 spreads") and never invents coaching cues (Style-Matching.md).

## Phase 6 Pack and Specialist Net Decisions

- **Packs are data.** `apps/strathvision/assets/packs/*.json` files are loaded at startup through the asset manifest. The neutral placeholder pack is built in, as the fallback. The active event is picked in the Library (top bar) and saved in the `settings` table. The default is the first event of the first domain pack.
- **No domain words in the engine.**
  - The engine has no head names, sport terms or event logic. A test scans `packages/analysis_engine/lib` for timber words.
  - Heads, their targets and probes are declared per event in the pack.
  - App code has no domain words either. The timber vocabulary lives only in `timber.json`.
- **Timber pack v1** (initial catalog, for coach review):
  - Events: underhand and standing block.
  - Phases: setup → backswing → downswing → entry → recovery. The critical phases are downswing and entry.
  - Metrics are implement slope at entry (the end of the downswing), mean downswing slope, slope at the top of the backswing, hinge at entry (neck–pelvis–knee), knee and elbow angles, shoulder lift range, and phase times.
  - `entry_slope` carries weight 2 and is the `slope_residual` target.
  - Attributes: Slope, Spacing, Hinge, Path, plus Footwork, Rhythm, Balance and Recovery.
- **The real `slope_residual`** is measured error plus a learned MLP correction. The measured error is entry slope minus the coach's center. A fresh head reports exactly the measured error, and harness patches (Phase 7) learn the correction. When no profile is selected the residual is 0, because there is no reference.
- **Probes** (DECISIONS.md "Specialist Net Harness"). Interpretation, for human review:
  - `slope_error_deg` and `slope_bias` are the mean |r| and the mean r over the probe clip set. On the coach's own reference clips both should be near 0.
  - `priority_agreement` uses red/green marks on "Slope": green should mean |r| < 2°, red should mean |r| ≥ 2°.
  - `phase_stability` is the variance of r.
  - `track_confidence_correlation` is the correlation of |r| with implement-track confidence.
  - The stub tracker reports constant confidence, so that correlation stays null until a real tracker exists.

## Phase 7 Workbench Decisions

- **Harness** (`SpecialistHarness`, engine).
  - The probe clips are analyzed once against the profile's metric centers, and the harness keeps each clip's feature vector and measured error, so trying a patch costs one MLP pass per clip.
  - The search is a deterministic black-box coordinate search over the output layer (`b2`, `w2[i]`). It reads only the five probe values, and every step must keep the side rules (no regression, within 5%) intact.
  - The result is judged by the pack's acceptance rules.
  - Patches are cumulative and versioned: v2 includes v1's edits.
- **Workbench screen** (desktop only: Linux, macOS, Windows). It opens from a ready profile in the Library.
  - Add the coach's clips, then **Run harness**. The screen shows a probe table (now vs with patch) and the decision with every rule's reason.
  - **Compile** each adapter spec.
  - **Save as vN+1** writes the next package version (published versions are never edited) and adds it to the Library. Phones load it and never edit.
  - The priority-agreement probe needs red/green marks. Clips added on the workbench carry none, so that probe reads n/a there.
- **Compile-once adapters.**
  - The compiler is Claude through the Messages API, using model `claude-opus-5-5`.
  - Dart has no official SDK, so the call is raw HTTP with `anthropic-version: 2026-10-21`.
  - The request uses structured output (`output_config.format` `json_schema`, with input names and outputs restricted by enum) and server-side fallbacks (`fallbacks: "default"`).
  - The API key comes from `ANTHROPIC_API_KEY` on the workbench computer. Without it, Compile is disabled and the screen says why.
  - Each compile is validated against the spec's examples, with up to 3 attempts. Each retry sends the mismatches back.
  - The resulting `.paw` is a logistic model run locally on the phone and desktop. Inference never calls an LLM.
- **Adapters at inference.** When the selected profile's package has adapters:
  - `usable_footage` adds "This clip is below the usable threshold." to the comparison warnings (DECISIONS.md status message).
  - `priority_scorer` shows "Focus next: <attribute>".
  - Stale or foreign adapters are skipped and named in the warnings.

## Phase 8 CARNE ASADA Decisions

- **Placement.** The playground is reached from the desktop Workbench (**CARNE ASADA** in its top bar). It is one window with one drop zone ("Feed CARNE ASADA", via `desktop_drop`), plus "or choose files". It never appears on phones.
- **Mixture.** v1 treats the profile's per-metric center/spread/weight (each tagged with its phase) as the phase-conditioned mixture, with one diagonal component per phase.
  - All five proposal types from CARNE_ASADA.md are implemented:
    - shift a mean
    - tighten one spread
    - raise a metric weight (×1.25, capped at 3)
    - add a residual exemplar (from the green stroke the mixture explains worst, at weight 0.5), or raise an existing one (+0.25, capped at 1)
    - drop a low-confidence exemplar (confidence below 0.6)
  - Exemplars are extra mixture components. A stroke's match on each metric is the better of the mean component and the best weighted exemplar.
  - Exemplars must lie inside the coach hull. They are saved in `profile.json` `reference_clips` with `exemplar: true`, weight, confidence and source.
- **The loop** (engine `CarneSession`):
  - **Diagnose.** Find the largest gap, in spreads, between green-marked strokes and the mixture on the priority attribute's metrics.
  - **Propose** one edit:
    - shift that mean halfway toward the greens, capped at one spread; or
    - tighten a spread ×0.85 when one stroke carries three or more red marks.
  - **Evaluate** only on the priority attribute. The objective is agreement with the winning marks: green strokes should match, red ones should not. A small held-out set (every 4th coach reference stroke) must keep at least 95% of its style score.
  - **Accept** only if the objective improves by at least 0.005 and the new mean stays inside the coach hull. The hull is the range of the coach's reference strokes; chaos widens it by one spread for the session.
- **Bounds.**
  - The session limit is 5 accepted edits by default (configurable 5–10).
  - No edits happen until usable footage reaches Good (2 min).
  - Winning marks: coach overrides athlete, and the newest coach mark wins.
  - Only the priority attribute's metrics are touched.
  - Priority and chaos can change only before the first accepted edit.
- **Status copy** is exactly the DECISIONS.md lines, templated from pack words (attribute, phase label, units, "steeper"/"flatter"). A test checks every template against this file verbatim.
  - Lines with no exact copy are written in the same style: priority changes from notes, "Ignoring <clip>.", voice notes without a transcriber, package drops, chaos on/off, and files that can't be used.
- **Ingestion.**
  - Videos are probed, split into strokes, and analyzed per stroke. Red/green marks come from any project that has the same clip file, bound to the stroke containing each mark's time.
  - Text notes understand `priority: <attribute>` and `ignore this clip`.
  - Voice notes are saved, but spoken labels need a local transcriber. None is chosen yet (see Blockers).
  - A dropped package for the same event merges its coach strokes into the hull and the held-out set ("Added N coach strokes from <coach> · vN to the coach hull."). Packages for another event are ignored.
- **Undo and save.**
  - Undo removes the last accepted edit and restores its metric exactly.
  - **Save as vN+1** writes one new package version per session: the edited mixture in `profile.json`, plus `carne_asada/mixture_edits_vN.json`.
  - **Save experiment** separately exports `carne_asada_run/1` JSON after any input attempt, even when there are no strokes or accepted edits. It never writes a profile version or changes the source package. Canceling or failing export leaves the run available to retry.
- **Input identity and run status.** Video SHA-256 is the stable source identity within the pack/event session. Copies/renames cannot inflate the pile; same-named different files have independent Ignore/Use anyway controls. Repeat drops refresh genuine marks without recounting footage. Drops are serialized and individual input failures are retained without aborting the batch. The prominent status and run log expose every loop stop reason. Source-keyed pose caching prevents stale results when bytes change at an existing path. These additions follow [CARNE_RUN_REPORT.md](CARNE_RUN_REPORT.md).

## Phase 9 Drift, Health, Distribution Decisions

Research accuracy follow-up: image-space axe observations and source-disjoint genuine-feedback evaluation use [AXE_OBSERVATIONS.md](AXE_OBSERVATIONS.md). A trained axe prototype is evaluated independently of the forearm proxy and remains research-only unless its measured performance supports promotion. Body pose, anonymous competitor selection, object localization, contact timing and technique feedback have separate validation claims. See [Gurr round 2](experiments/Gurr-Round2.md).

- **Drift view** (Library → a profile's chart icon). It shows stored comparisons for that profile across all its versions. With one user per install, the athlete is implicit. Comparisons are grouped by local day into sessions.
  - The view shows the latest session's style match, the change since the first session, and the trend. "Getting closer" or "Drifting away" applies when the least-squares change exceeds 1 point per session; otherwise it reads "Holding steady".
  - The chart has one line, plus a table view and per-measurement distance sparklines.
- **Profile health** (shown on each Library tile): ready, clips against the pack minimum, schema up to date (otherwise "Needs rebuild"), patches applied or rejected, adapters current or out of date, pack not installed, and how often the profile has been used.
- **Moving packages, with no cloud:**
  - **Export** writes the coaching profile only (the default export choice): profile, patches and adapters. `carne_asada/` stays on the computer.
  - **Import** works from a file.
  - A **shared inbox folder** (for example Syncthing, or a folder you copy into) is scanned at startup and when chosen. New `(profile_id, version)` packages are copied into the app and listed.
  - The "+ my marks" and "full local overlay" export choices, replace/keep/merge on import, QR codes, and P2P transfer are not built in v1.
- **Builds:**
  - `.github/workflows/builds.yml` (public repo) builds the APK, the Linux, Windows and macOS zips, and an unsigned iOS app on every app change, after the tests pass.
  - `docs/DISTRIBUTION.md` covers sideloading, ad-hoc IPA signing, and running the zips.

## Real Pose Decisions (replacing the Phase 3 stand-ins)

- **Pose model:** MediaPipe BlazePose GHUM 3D, the "full" landmark model, Apache-2.0.
  - It gives full-body metric 3D world landmarks centred on the hips, which is what "Core Engine" requires: root-relative and camera-agnostic.
  - It is converted to ONNX (`assets/models/pose_landmark_full.onnx`, 12.8 MB) and runs through the `onnxruntime` Flutter plugin, which bundles the native runtime for Android, iOS, macOS, Windows and Linux.
  - The conversion matches the original within 1e-3 on landmarks.
  - Chosen by the agent when the human said to proceed without stopping. Listed for confirmation in STATUS.
- **Person finding:** YOLOX-Nano (Apache-2.0, official ONNX, `assets/models/yolox_nano.onnx`, 3.7 MB) on the same ONNX Runtime. Its preprocessing matches the reference (OpenCV) implementation used in `tools/carne_asada` to integer rounding.
  - **Why:** whole-frame tracking failed on the Gurr competition, underhand-heat and springboard footage. The person was found in 0–40 of 300 frames.
  - **Auto-pick, then correct (human decision, 2026-11-04):** "offer an autodetect AND a way to correct it."
    - For the first 4 s, everyone detected (top 5) is followed. Each person's pose comes from their own landmark region, and the detector only identifies them.
    - The athlete is the person whose wrists travel furthest relative to their hips (torso lengths per sample), weighted by how much of the window they were seen. This beats spectators, judges, walkers and false detections such as a camp chair.
    - When the runner-up is at least 75% as active (two choppers in a heat), or nobody moves enough, the pick is marked unsure. The Analysis panel then asks the user to pick the athlete.
    - Otherwise the panel shows "Wrong person?". The picker shows one frame with every detected person boxed, lets the user turn a sideways picture, and offers "Pick automatically".
    - The choice is saved on the clip (INTERFACES "Project", `athlete`) and reused on every re-analysis.
  - **Following:** BlazePose follows the athlete from their own landmarks (MediaPipe's rule). The detector re-checks every second. When the pose is lost, the athlete is re-found only near where they were last seen (similar height, overlapping or close). It never jumps between two near-equal candidates. Frames where the athlete is lost get no pose.
    - Between detector checks the athlete's last box moves with their pose, so a lost athlete is looked for where they went.
    - Only people of the athlete's usual size (0.6–1.8× the median of their recent detections) can be the athlete. On springboard footage a judge standing below the board was taken over when the chopper climbed past the pole (IMG_3925: the top-block chopping was missed and the judge's arm made a stroke).
    - Lost for over a second: someone of the athlete's usual size roughly above or below where they were (within 1.5 box widths sideways) is the athlete again, unless two fit about equally. A springboard chopper climbs a pole.
    - Clothing colour was tried as an identity cue and rejected: on IMG_3925 the white trousers matched background people better than the athlete matched themselves.
  - **Orientation:** phones filmed sideways without rotation metadata show people lying down.
    - On five frames spread across the clip, each quarter-turn is scored as detector score × pose presence × cos⁴ of the hips→shoulders angle from vertical. The pose model is reliable on upright people and unsure or wrong on lying ones.
    - The picture stays unturned unless a turn scores more than twice as high. The user can correct it in the picker.
    - Scoring with the pose model alone, on whole frames, picked wrong turns on upright crowded clips, so it was dropped.
    - On 17 Gurr frames (sideways both ways, upright training, crowded competition) the rule chose correctly every time.
- **Frames:** a headless media_kit player (no window, no sound) decodes exact frames as raw BGRA. Clips are sampled at up to 15 fps, at most 1,800 samples per clip. On this laptop that runs at about 39 ms per frame.
  - **HDR:** 45 of the 48 Gurr Academy videos are iPhone HDR (HLG / Dolby Vision, BT.2020, 10-bit). The headless decoder returns them washed out; on a bright scene the detector found nobody.
    - HDR clips (mpv `video-params/gamma` `pq` or `hlg`) are tone-mapped to standard video before analysis with zscale + Hable (as fast as no filter), falling back to mpv's own colour conversion (about 4× slower) where zimg is missing. Standard clips are untouched.
    - The display player is not affected; it renders HDR on the GPU.
  - Frame stepping detects each new frame by a change of position. mpv's `estimated-frame-number` counts milliseconds on WebM, which made every step wait out its timeout and broke determinism.
- **Joint confidence:** presence × (0.4 + 0.6 × visibility), so a joint that is hidden but in frame still counts at 0.4. BlazePose infers hidden joints well, and visibility alone made every far-side wrist look missing.
- **Implement:** `GripImplementTracker` infers the implement from the grip: a 0.75 m segment from between the hands along the forearms, with the better-seen wrist's confidence. This is not a vision detector for the implement itself; one can replace it behind `ImplementTracker` once a trained detector exists.
- **Phases:** `EventPhaseDetector` places boundaries from pack-declared events on the implement tip:
  - `low_before_top` (rise)
  - `top`
  - `low` (contact, where the descent slows to 20% of its peak)
  - `settle` (speed below 25% of peak)
  - `fastest`
  
  The first and last phases may be cut short by the recording; they are allowed at half confidence.
- **Strokes:**
  - `stroke_signal: tops` (timber underhand) gives one stroke per backswing top. A top whose rise is cut off by the clip start counts, because real clips often start mid-backswing.
  - `stops` (timber standing block) gives one stroke per contact, where a fast swing stops sharply. Standing block contacts are sideways into the block, often from flat hip-height swings, so height-based "top/low" rules do not apply. Phases use `rise`, `reach` (the turnaround before the swing), `stop` (contact) and `release` (pull-out).
  - In fast competition rhythm there is no pause between strokes, and the midpoint between contacts falls inside the next backswing (the backswing then landed in the previous stroke: "backswing too short" on 68 of 122 competition strokes). The cut moves back to where the stroke starts moving, at most 0.4 s (INTERFACES). On the saved Gurr tracks: competition 21 → 34 of 55 usable, training 61 → 65 of 80, contacts unchanged; checked frame by frame on IMG_3869 and IMG_3867.
  - `speed_peaks` remains the default.
- **Springboard (human decision, 2026-11-05: "yes" to adding the event):** the timber pack's third event, `springboard`. The chopping at each board and at the top is a sideways swing into the pole, like standing block, so it uses `stops` and the standing-block phases and metrics, plus both knees at contact (stance on the board, under Spacing). The metric choice is the agent's placeholder for coach review. Climbing and board work make no contacts and so no strokes.
- **Filming tip (human decision, 2026-11-05: filming guidance "would help"):** when at least 3 strokes were found, under 60% could be measured, and the clip is under 50 fps, the Analysis panel says how many swings could be measured and suggests filming at 60 frames per second. The Gurr competition swings are motion-blurred at 30 fps. That 60 fps helps is an expectation (shorter exposure, twice the samples), not yet measured: none of the footage is 60 fps.
  - Validated against Gurr training footage frame by frame. An independent pre-registered check (Codex, docs/experiments/Gurr-Accuracy.md) found 3/3 fresh contacts against 0/3 for the height rules, about 0.2 s late.
- **Clip measurements:** a clip's Metric Vector is the median over its usable strokes; phases come from the stroke nearest the median.
- **Validation** on openly licensed real footage:
  - Wood cleaving: two overhead strokes found, contact within the hand-checked range, plausible angles. Dart and Python runs agree to a 3.7 cm median.
  - A standing-block competition clip shot through a fence was not usable: arms are lost to the fence and motion blur. Standing block (horizontal swing) is not yet validated on clean footage.

## Thresholds and Gating (timber defaults)

- Usable action = confident 3D pose + confident implement + assigned phase + actual stroke.
- Good: 2 min usable. Great: 6 min. Excellent: 15 min.
- Below Good: store everything, body tracking and basic dual-video tools work, suppress implement-specific ghosts, weighted rankings, and parameter updates. Persistent encouragement to add footage.
- At Good and above: advanced features unlock progressively.
- Explanatory coach speech during swings receives boosted binding weight.

## Coaching Packages and Remote

- Athlete-derived and coach-authored packages. Coach-authored built in this iteration: coach uploads own footage, runs reinforcement, exports.
- Package contains densities, w, exemplars, phase/segmenter state, implement-class templates, specialist patches, compile-once adapters. No raw video, no base layer.
- Additional objects: `specialist_patches/`, `adapters/`, `carne_asada/` (research logs, desktop-only).
- Stable IDs: coach:<name>:<event>:<origin>. Monotonic versions + content hash. Non-mutating. Import offers replace / keep / merge.
- Export choices: Coaching profile only (default), + my marks, or Full local overlay. Explicit summary before write. Contribution to shared/merged requires opt-in.
- Soft revoke: blocks new imports, flags existing copies, no remote deletion. Opt-in update notices only.
- Phone-first for all coach flows (create, reinforce, export, merge, revoke). Athletes may use laptop for heavier comparative work.
- Remote exchange paths (all produce identical bindings):
  1. One-time clip code / QR (primary)
  2. Shared local inbox folder (Syncthing etc.)
  3. Message-attachment round-trip
- Incoming coach marks: immediate light update (w + exemplars + re-rank + ghost) then queued for next full fit. Coach overrides athlete on same stroke+attribute.

## Sync, Tiers, Recovery

- Profile package is the fitted result (parameters, w, exemplars, bindings index, patches, adapters, etc.). Raw video stays local.
- Primary: automatic workbench loop (laptop ingests, fits, pushes when phone reachable).
- Secondary: manual transfer when convenient (AirDrop, local network, P2P code).
- Opportunistic local Wi-Fi + one-time peer-to-peer. No required cloud.
- Phone base / laptop-trained package / desktop full. Phone never required to do heavy fit for personal use; coaches can do everything on phone.
- Single writer queue per overlay. Fits run on snapshot; mid-fit arrivals apply after.
- Automatic rollback (keep last two versions). Soft reset (parameters only). Full export-and-rebuild archive.
- Format versioning: newer readers accept older packages; older readers refuse or read-only.

## Distribution

- Android: APK/AAB sideload for testing.
- iOS: ad-hoc provisioning (UDIDs, signed IPA + profile). 100-device cap.
- Desktop (Windows/macOS/Linux): zip of Flutter build.
- Packages are ordinary files.

## Edge Cases

- One phone + one laptop.
- Deleted source clips: invalidate tied marks/exemplars and rebuild without them.
- Extreme mismatch: auto-scale imported ranges to athlete mobility.
- Clock sync / logical timestamps for recency.
- Partial fit crash: previous version remains intact.
- Transcript failure: drop language binding after retry; keep audio. Robust local transcriber is priority.
- Single user per install.
- Design target 20–30 min sessions.

## UI/UX Principles (see also docs/UI_UX_PRINCIPLES.md)

- Backend may be arbitrarily complex. Frontend must be usable by someone reluctant to use a phone.
- Coach and athlete feel they are only coaching/reviewing the human. Blissfully unaware of the model.
- Progressive enhancement: footage alone → per-stroke red/green → voice → coach notes. Each layer independent. Model improves from clean footage alone.
- Instant obvious undo. Unmistakable current stroke/attribute. Aggressively good defaults. Physical-feeling control latency. Finished-looking empty/partial states. One primary action per screen. Spatial memory over menu paths.
- Aha standard: surface subtle unnamed patterns (spacing, opening/closing, etc.) cleanly so the user recognizes them. No invented coaching language.

## CARNE ASADA Ingestion (exact)

Drop zone accepts videos, packages, voice notes, text notes. Instant status:

- “Found 8 strokes. 5 are clean enough for slope. Adding them.”
- “Coach is talking through the swing. Pulling the spoken labels and binding them to the timeline.”
- “Implement drops out for 1.2 s. Clip saved, but it won’t move the model.”
- “You already have 7 minutes of good slope footage. This is pure gravy.”
- “Priority is slope. Only slope updates will be considered this session.”
- “This clip is below the usable threshold. Click ‘use anyway’ if you want it in the pile.”
- “CARNE ASADA accepted an update. Slope mean shifted 1.1° steeper on the downswing.”
- “No update. The proposed change would have left the coach hull.”
- “Session tally: 4 accepted edits. Undo is one click.”

One-sentence edit explanations (exact style):

- “Shifted slope mean 1.4° steeper on the downswing phase because 7 of your last 9 green marks agreed.”
- “Tightened slope variance in the entry phase after three consecutive red marks on the same stroke.”
- “Raised the weight of the residual exemplar from the 14-second mark of the Gurr clip; it matched the current priority better than the existing mean.”
- “Dropped one low-confidence exemplar that was pulling the mean flat.”
- “No geometric change. Only re-weighted existing coach strokes after the new voice note.”
