# STRATHVISION app

Flutter client for every platform: Android, iOS, Windows, macOS, Linux.

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

The analysis engine is a pure-Dart package with its own tests:

```sh
cd ../../packages/analysis_engine
dart pub get && dart analyze && dart test
```

### Real-decoder test (Phase 2)

`integration_test/real_player_test.dart` drives media_kit/libmpv on a device with two generated clips (`integration_test/assets/clip30.mp4`, 30 fps; `clip25.mp4`, 25 fps). It checks positions as mpv reports them.

```sh
# Linux desktop
flutter test integration_test -d linux --dart-define=CLIP_DIR=$PWD/integration_test/assets
# Android device (pushes clips once the app has created its files folder)
scripts/run_android_player_test.sh [device-id]
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

## Phase 4 manual check

1. In **Library**, tap the person-plus icon (**Build a profile**).
2. Type a name, tap **Add clips**, and pick 15 or more clips of one person. Each clip shows a spinner, then **Clean** or the reason it can't be used. The bar counts clean clips toward 15.
3. Tap **Build profile**.
   - **Ready:** "<Name> · v1 is ready", with the held-out match. The profile is added to the Library. **Save a copy** writes `<Name>_v1.zip`, which holds `profile.json`, `specialist_patches/` and `adapters/`.
   - **Rejected:** a plain message and the error code, for example "Add 6 more clean clips…" (`INSUFFICIENT_CLIPS`). Nothing is stored.
4. Go back. The Library lists the new profile as Ready.

With the stand-in pose model, any 15 clips build. Real gating needs the real pose model.

## Phase 3 manual check

1. Open a review and add a clip on A.
2. Tap **Analyze** in the top bar, or press A. On phones the button shows only its icon.
3. The Analysis panel opens: beside the video on wide screens, under it on narrow ones. It lists body-tracking confidence, the three placeholder phases (times and frames), four metrics with units and confidence, and `slope_residual`.
4. Add a clip on B. B becomes the active stage and the panel reads "Not analyzed yet". Analyze it.
5. Scrub, step and play while the panel is open. Review controls are unaffected.

In this build the pose model is a stand-in, so the values are placeholders.

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
