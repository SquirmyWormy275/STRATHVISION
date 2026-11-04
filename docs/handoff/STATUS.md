# Handoff Status

<!-- Machine-updated by scripts/handoff.sh. The fields between the markers are parsed; edit them by hand only if the script can't. -->
<!-- STATE:BEGIN -->
owner: claude
heartbeat: 2026-11-04T14:27:43Z
branch: implementation
phase: 2 — Dual-Video Workspace
task: Acceptance: Android real-decoder verification pending
next: Phase 4 task 1: clip import + quality evaluation for the profile builder (workbench). Start in packages/analysis_engine/lib/src/builder/ with quality evaluation over Metric Vectors; acceptance uses 15+ synthetic clips.
<!-- STATE:END -->

## Phase progress

| Phase | State |
|-------|-------|
| 0 Contracts | done |
| 1 Project Skeleton | done on Linux + Android emulator (launch, real file-picker import, persistence, navigation). **Open: Windows launch check (human, on a Windows PC)** |
| 2 Dual-Video Workspace | tasks 1–9 implemented. 49 unit/widget tests plus a real-decoder test passing 3/3 on Linux. **Open: real video on Android** (see Blockers) |
| 3 Analysis Runtime Skeleton | **done**. `packages/analysis_engine` (18 tests), Analyze button and panel (6 app tests), real-decoder Analyze test passes on Linux. Pose, implement and phase stages are stubs behind real interfaces |
| 4–9 | not started |

## Blockers / questions for the human

- **Which 3D pose model?** (needed before real footage gives real metrics, not before Phase 4's synthetic-clip acceptance.) DECISIONS.md requires full-body 3D root-relative pose and a lightweight implement tracker, but doesn't name the models. The engine has `PoseEstimator` / `ImplementTracker` interfaces ready. The human must pick the models and confirm their licences.

- **Phase 2 on Android is not verified.** On this machine's emulator (software GPU) mpv doesn't load or seek video: `time-pos` and `hwdec-current` stay empty. The host-GPU emulator mode hung during boot, and that qemu process (`-gpu host`) is still running, which blocks starting a new emulator. It needs `pkill qemu-system-x86_64` (the agent isn't permitted to kill it). Best fix: connect a physical Android phone with USB debugging and run `apps/strathvision/scripts/run_android_player_test.sh`.

- **Phase 1 Windows acceptance is open.** On a Windows PC: `cd apps/strathvision && flutter run -d windows`, then follow the "Phase 1 manual check" in apps/strathvision/README.md. iOS/macOS builds need a Mac.

## Environment notes

- Toolchain installed via mise (global): flutter 3.47.9, java temurin-17, rust 1.99.1, cmake, ninja. In scripts, `eval "$(mise env -s bash -C ~)"` puts them on PATH.
- Android SDK: `~/Android/Sdk` (`flutter config --android-sdk` is already set). AVDs live in `~/.config/.android/avd`, so export `ANDROID_AVD_HOME=$HOME/.config/.android/avd` before `emulator -avd sv_phone`.
- GitHub: push over HTTPS through gh (`gh auth setup-git` is done). SSH keys are not set up.
- libmpv and ffmpeg are installed system-wide (needed for Phase 2 media_kit and test clips).

## Log

<!-- newest first; scripts/handoff.sh prepends entries below this line -->
- 2026-11-04T14:27:43Z **claude** — Phase 3 done: Analyze button + raw-metrics panel (wide: side, narrow: below video), engine on background isolate, Error Contract shown on failure. Pack analysis section + error mapping added to INTERFACES.md, Phase 3 decisions in DECISIONS.md. 55 app tests + 18 engine tests + 2 real-decoder tests (Linux) pass. Linux release builds. → next: Phase 4 task 1: clip import + quality evaluation for the profile builder (workbench). Start in packages/analysis_engine/lib/src/builder/ with quality evaluation over Metric Vectors; acceptance uses 15+ synthetic clips.
- 2026-11-04T14:21:30Z **claude** — Phase 3 tasks 1,2,4: packages/analysis_engine (pure Dart) with INTERFACES.md contracts + validators, stub pose/implement/phase pipeline, generic pack-driven metrics, stub slope_residual head (64→32 MLP, 2113 params). 18 tests pass. → next: Phase 3 task 3: add analysis_engine path dep to apps/strathvision, Analyze button in workspace top bar, raw-metrics panel
- 2026-11-04T14:18:24Z **claude** — Claimed: Phase 3 — Analysis Runtime Skeleton
- 2026-11-04T07:54:45Z **claude** — Note: README Phase 1 steps updated for the New review flow.
- 2026-11-04T07:54:33Z **claude** — Phase 2 dual-video workspace implemented (all Workspace Events, persistence, undo, red/green). 49 tests + real-decoder test pass on Linux 3/3. Fixed async-seek and drift-correction bugs found on libmpv. → next: Android real-video check: kill the stuck emulator or connect a phone, then run apps/strathvision/scripts/run_android_player_test.sh. If it passes, Phase 2 is done and Phase 3 (analysis runtime skeleton) starts.
- 2026-11-04T07:14:08Z **claude** — Phase 1 verified on Linux + Android emulator (launch, file-picker import of dummy profile, persistence across restart, Library↔Workspace) → next: Phase 2 task 1: add media_kit and load clips into stage A/B in apps/strathvision/lib/screens/workspace_screen.dart
- 2026-11-04T06:50:51Z **claude** — Set up the handoff protocol. Phase 1 tasks 1–4 are implemented, 14 tests pass, and the Linux release build launches.
