# STRATHVISION app

Local-first video review client for Android, iOS, Windows, macOS, and Linux.
Start with two clips: align a visible event, review in slow motion, and save the
sync and marks in a local project. Analysis is an additional review tool; video
review does not require a profile or a successful analysis.

For a first contribution, follow Setup, run the focused Phase 1 checks below,
then try the Phase 2 manual check. The [architecture](../../docs/ARCHITECTURE.md),
[contracts](../../docs/INTERFACES.md), and [ordered execution plan](../../docs/EXECUTION_PLAN.md)
explain the boundaries. [Handoff status](../../docs/handoff/STATUS.md) separates
recorded test results from outstanding device acceptance.

The default app runs a local person detector and BlazePose pose estimation, then
pack-driven stroke, phase, and metric extraction. Implement position is inferred
from the hands and forearms; it is not a directly detected tool position. Synthetic
pose runners remain available for tests. See the [measured accuracy limitations](../../docs/experiments/Gurr-Pipeline-Findings.md)
before interpreting analysis output as evidence about technique.

## Requirements

- Flutter 3.47 (stable)
- Android: Android SDK (platform 36, build-tools 36.0.0) and JDK 17
- Windows: Visual Studio 2022 with "Desktop development with C++"
- iOS / macOS: a Mac with Xcode and CocoaPods
- Linux: `clang`, `cmake`, `ninja`, `pkg-config`, GTK 3 headers

## Setup

```sh
cd apps/strathvision
flutter pub get
dart run build_runner build -d   # regenerates lib/data/database.g.dart
```

## Tests

```sh
flutter analyze
flutter test
```

`test/fixtures/dummy_profile.json` is the dummy profile used to check the Phase 1 import.

For a focused check of navigation, profile import, invalid-package rejection, and
metadata persistence across database reopen:

```sh
flutter test --no-pub --concurrency=1 test/widget_test.dart test/profile_package_test.dart
```

These tests substitute the file picker and video players. They do not verify a
native file dialog or a Windows/mobile launch. The Phase 1 manual check below is
still required on the target devices; a successful build alone does not close it.

The analysis engine is a pure-Dart package with its own tests:

```sh
cd ../../packages/analysis_engine
dart pub get && dart analyze && dart test
```

### Real-decoder test (Phase 2)

`integration_test/real_player_test.dart` drives media_kit/libmpv on a device with two generated clips (`integration_test/assets/clip30.mp4`, 30 fps; `clip25.mp4`, 25 fps). It checks positions as mpv reports them.

```sh
# Linux desktop
flutter test integration_test/real_player_test.dart -d linux \
  --dart-define=CLIP_DIR=$PWD/integration_test/assets
# Android device or emulator (pushes clips once the app has created its files folder)
scripts/run_android_player_test.sh [device-id]
# Every screen, end to end, on the desktop (real video; optional screenshots)
flutter test integration_test/app_e2e_test.dart -d linux \
  --dart-define=CLIP_DIR=$PWD/integration_test/assets --dart-define=SHOTS=/tmp/sv_shots
# A laptop-built package imports and runs on the phone
scripts/run_android_player_test.sh "" integration_test/phone_package_test.dart
# (regenerate that package: flutter test tool/make_phone_fixture.dart)
# Emulator note: start it with the discrete GPU, e.g.
#   __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia emulator -avd sv_phone -gpu host
```

## Run and build per platform

| Target | Run | Build |
|--------|-----|-------|
| Linux | `flutter run -d linux` | `flutter build linux --release` |
| Android | `flutter run -d <emulator-id>` | `flutter build apk --release` |
| Windows (on Windows) | `flutter run -d windows` | `flutter build windows --release` |
| iOS simulator (on a Mac) | `open -a Simulator && flutter run -d ios` | `flutter build ios --simulator` |
| macOS (on a Mac) | `flutter run -d macos` | `flutter build macos --release` |

Flutter only builds Windows apps on Windows, and only builds iOS and macOS apps on macOS.

## Phase 9 manual check

1. After comparing clips with a profile on a few different days, tap that profile's chart icon in the Library. You see the latest match, the change since the first session, "Getting closer / Holding steady / Drifting away", a line by session (tap a point for its tooltip, or use the table toggle), and distance-from-coach sparklines.
2. Each profile tile shows health: Ready, N of 15 clips, Up to date or Needs rebuild, patches, adapters, and how much it has been used.
3. The share icon exports `<Coach>_vN.zip`. Move it to the phone by any local means and import it there. You can also set Library → ⋮ → **Inbox folder…** to a synced folder.
4. Build distributables as described in `docs/DISTRIBUTION.md`.

## Phase 8 manual check (desktop)

1. Open the Workbench for a ready Underhand profile and tap **CARNE ASADA**. The feed opens with "Priority is slope. Only slope updates will be considered this session."
2. Drag clips onto **Feed CARNE ASADA**, or use **or choose files**. Each clip reports "Found N strokes. K are clean enough for slope. Adding them.", the implement-dropout line, or the below-threshold line with **Use anyway**. Dropping a copy or renamed copy refreshes its marks and counts its footage once. Different recordings with the same filename remain independent. A failed file does not abort the remaining inputs.
   Uncertain automatic selection pauses at **Choose competitor**. Tap the athlete in the picker and confirm; **Change competitor** replaces that source’s measurements before accepted edits. Long recordings use a four-second selection preview and a desktop 30 Hz sampling budget. This is within-recording tracking, with no named identity recognition.
3. Once usable footage reaches Good (2 min), and the clips carry green/red Slope marks from reviews, accepted updates appear as "CARNE ASADA accepted an update. Slope mean shifted 1.1° steeper on the downswing.", followed by the session tally. **What did it just do?** lists each one-sentence explanation.
4. The current status explains why updates stopped, including insufficient usable footage and missing feedback. **Save experiment** writes a standalone JSON report even with zero edits or failed inputs. Canceling or failing the save permits a retry; changing the session makes the saved snapshot older. See [the record format](../../docs/CARNE_RUN_REPORT.md).
5. **Undo** reverts the last edit. **Save as vN+1** is enabled for accepted edits and writes the new version with `carne_asada/mixture_edits_vN.json`. Phones ignore that folder. Saving an experiment alone never creates a profile version.
6. A text note containing `priority: hinge` switches the priority (before any edit). `ignore this clip` drops the last clip. All notes in the batch finish before an update is tried.

For the first genuine judgments, use the [private video review workflow](../../docs/FEEDBACK_REVIEW.md). Its real tasks start unlabelled. **Save experiment** exports measured stroke vectors for source-disjoint learning evaluation. Field coaching effectiveness remains unvalidated.

Automated Linux verification: `flutter test integration_test/carne_run_flow_test.dart -d linux --dart-define=CLIP_DIR=<absolute integration_test/assets path> --dart-define=OUT=<absolute output directory>`. The UI/export case uses explicitly synthetic measurements and writes an inspectable JSON plus screenshot. A separate case decodes the licensed `cleave.webm` and checks that a changed content key invalidates the real pose cache. These checks establish application behavior, not coaching accuracy. The private Gurr diagnostic requires separate source footage and arguments; follow [the round-2 reproduction guide](../../docs/experiments/Gurr-Round2.md#reproduce-native-diagnostics).

## Phase 7 manual check (desktop)

1. Build or import a ready profile for **Underhand**. In the Library, tap its tune icon (**Workbench**).
2. **Add coach clips**: clips of that coach. The probe table shows `slope_error_deg`, `slope_bias`, `priority_agreement`, `phase_stability` and `track_confidence_correlation`.
3. **Run harness**. You get either "Accepted: slope_residual_v1" with the after column filled in, or "Not accepted" with the rule that failed (for example, `slope_bias must improve by at least 0.8`).
4. With `ANTHROPIC_API_KEY` set, **Compile** `usable_footage` and `priority_scorer`. Without the key, the card says compiling needs it.
5. **Save as v2**. The Library lists **<Coach> · v2**. Compare a clip with v2 in Analyze: the coverage line names the patch, "Focus next" shows the priority adapter's pick, and inference makes no AI call.

## Phase 6 manual check

1. Launch. The Library's top bar shows **Underhand ▾**, the first event of the bundled Timber pack.
2. Tap it and choose **Standing block**. The choice is kept after a restart.
3. Open a review and add a clip. The mark chips are Slope, Spacing, Hinge and Path. **Analyze** lists timber metrics such as Entry slope and Hinge at entry.
4. Build a profile for the event, then compare a clip with it. `slope_residual` is the entry-slope error against that coach.
5. To add or swap a pack, drop a pack file (INTERFACES.md "Pack File") into `assets/packs/` and rebuild the app. The engine doesn't change.

## Phase 5 manual check

1. Build a profile (Phase 4 check) or import one for the same pack/event.
2. Open a review, add a clip, and tap **Analyze**. The panel shows **Compare with: <Coach> · v1**, a big style-match percentage, any warnings, and **Biggest differences**, ranked.
3. Tap a difference. It expands to show the definition, this clip's value, the coach's value ± spread, and the phase.
4. If the package has `specialist_patches/slope_residual_vN.patch`, the coverage line reads "patches: slope_residual_vN". A broken patch is skipped and shown as a warning.
5. Choose **Nobody** to see measurements only. Each comparison is stored for drift.

## Phase 4 manual check (desktop)

1. In **Library**, tap the person-plus icon (**Build a profile**).
2. Type a name, tap **Add clips**, and pick 15 or more distinct recordings of one person. Exact copies count once. Resolve uncertain athlete/orientation choices in a review, then retry failed clips. Each clip shows a spinner, then **Clean** or the reason it can't be used. The bar counts clean clips toward 15.
3. Tap **Build profile**.
   - **Ready:** "<Name> · v1 is ready", with the held-out match. The profile is added to the Library. **Save a copy** writes `<Name>_v1.zip`, which holds `profile.json`, `specialist_patches/` and `adapters/`.
   - **Rejected:** a plain message and the error code, for example "Add 6 more clean clips…" (`INSUFFICIENT_CLIPS`). Nothing is stored.
4. Go back. The Library lists the new profile as Ready.

The default builder evaluates real video through the local pose pipeline. Fifteen
selected files do not guarantee a ready profile: enough clips must be usable and
the pack's confidence and self-consistency gates must pass. These checks do not prove independence between recording sessions. Synthetic fixtures
exercise the builder in tests; they do not validate accuracy on real footage.

## Phase 3 manual check

1. Open a review and add a clip on A.
2. Tap **Analyze** in the top bar, or press A. On phones the button shows only its icon.
3. The Analysis panel opens: beside the video on wide screens, under it on narrow ones. Successful analysis shows measurements and phases from the active pack, confidence, and any configured specialist residuals. Check the selected athlete and any warnings. Footage that cannot be measured should show a structured failure rather than the old placeholder values.
4. Add a clip on B. B becomes the active stage and the panel reads "Not analyzed yet". Analyze it.
5. Scrub, step and play while the panel is open. Review controls are unaffected.

The production workspace uses `visionRunner`; `isolateRunner` supplies synthetic
poses for tests. The default builder similarly uses `visionEvaluator`. Metric and
phase counts depend on the selected pack. A residual or style-match score does
not establish absolute movement quality.

## Phase 2 manual check

1. Tap **New review**, then **Add a clip** on A and **Add a clip to compare** on B.
2. Scrub each timeline to the same moment (for example, impact) and tap **Sync here**. The pill reads `Locked · B +x.xx s`.
3. Pick **.25×** and press Play (or Space). Both clips play together in slow motion.
4. Use ← / → (or the step buttons) to frame-step the locked pair.
5. Tap Mirror. B flips and the sync pill doesn't change.
6. Choose an attribute chip and tap green or red. A tick appears on the timeline. Undo (Ctrl+Z) removes it.
7. Go back, then reopen the review from **Reviews**. Both clips, the sync, the rate, mirror, and marks come back.

Desktop keys: A analyze · Space play/pause · ←/→ frame step · S sync here · L lock/unlock · M mirror B · G/R mark · Ctrl+Z undo.

## Phase 1 manual check

1. Launch the app. It opens on **Library**, which says "Add a clip to start".
2. Tap **New review**. You get two empty stages, A and B. Go back.
3. Tap the import icon (top right) and pick `test/fixtures/dummy_profile.json`.
4. The list now shows **Dummy Coach · v1**, `example_pack / example_event`, 15 clips · 1 metrics, Ready.
5. Close and reopen the app. The profile is still listed.

## Data location

The database is SQLite through Drift, stored in the platform app-support folder:

- Linux: `~/.local/share/com.strathvision.strathvision/strathvision.sqlite`
- Windows: `%APPDATA%\com.strathvision\strathvision\strathvision.sqlite`
- macOS, iOS and Android: the app's sandboxed support directory
