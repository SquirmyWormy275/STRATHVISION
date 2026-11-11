# STRATHVISION app

Local-first athletic video review for Android, iOS, Windows, macOS and Linux. The primary surface is a footage filmstrip and a single/dual-video review canvas. Analysis is optional; it is not a prerequisite for playback, comparison, frame stepping or notes.

The UI redesign is specified in [the visual system](../../docs/VISUAL_SYSTEM.md), [local view-state contract](../../docs/UI_REDESIGN_CONTRACT.md) and [acceptance checklist](../../docs/UI_REDESIGN_ACCEPTANCE.md). [Handoff](../../docs/handoff/UI_REDESIGN.md) records implementation evidence separately from unresolved acceptance.

## Requirements

- Flutter 3.47.9 / its bundled Dart SDK.
- Python 3 to provision exact pinned UI font/license assets during setup.
- Android: Android SDK platform 36, build-tools 36.0.0, JDK 17.
- Windows: Visual Studio with Desktop development with C++.
- macOS/iOS: Mac, Xcode and CocoaPods.
- Linux: clang, CMake, Ninja, pkg-config, GTK 3 headers and libmpv.

## Setup

From the repository root:

```sh
python scripts/fetch_ui_fonts.py
cd apps/strathvision
flutter pub get
dart run build_runner build -d
flutter run -d linux
```

The font provisioner verifies pinned upstream Git blob identities and retains both SIL Open Font License notices. It refuses unexpected local files rather than replacing them. Fonts and notices are bundled into the app; there is no runtime font download. The network is needed for initial dependencies/fonts, not for the core review loop.

## Your first review

**Add clip** opens the native picker immediately. Canceling leaves no empty project. One successful clip gets the canvas; **Compare** adds a second. Review keeps original frames contained rather than cropping the athlete to fit the layout.

Scrub the clips to a common visible moment and choose **Sync here**. Linked playback maintains their offset. Speed, frame stepping, Mirror B, Swap, notes and Undo remain available. **Single view** hides the second stage without deleting its source or feedback; Undo restores the pair.

A new unconfigured review is **Just video**. Choose its event when marks or analysis are needed. The library's event preference only applies to new reviews. A saved review retains its own event/schema rather than adopting whichever event is selected in the library later. A legacy review with unknown context asks for an explicit choice.

Attribute labels come from the chosen pack. **Good** and **Needs work** are human judgments on that attribute at the displayed frame. They are not automatic model grades, universal technique judgments, or start/contact timing markers. A note is attached to the current frame. Keyboard shortcuts are suppressed while entering text or using modal dialogs.

Desktop keys: Space play/pause; arrows frame step; S sync; L link/unlink; M mirror B; G/R human marks; Ctrl/Cmd+Z Undo; A analyze. Touch targets and labeled primary actions remain available without shortcuts.

## Reopening and recovery

Local presentation records retain active stage/attribute, playheads, event/schema and exact profile version. They live separately from Project JSON, so a playback-position checkpoint cannot overwrite newer marks or annotations. The library orders recent visits rather than moving tiles on every playback tick.

Missing or changed sources keep their saved review and feedback. A changed source is not resumed at an unverifiable old timestamp. Replace an unavailable stage explicitly. Presentation signatures are lightweight file-revision checks, not research provenance or a substitute for feedback SHA-256.

Unrecognized/corrupt future context is not silently erased. A missing exact profile version is not silently replaced with the latest one: choose another version explicitly or select **Measurements only**. A failed save remains retryable; leaving without the latest saved changes requires an explicit decision.

## Profiles, packages and desktop work

**Profiles & tools** is secondary navigation from the library. It retains profile import/export, health, trend, the shared inbox, desktop profile building, the specialist workbench and CARNE ASADA. Phones review and use imported packages; fitting and weight editing remain desktop-only.

Export preserves the existing explicit choice of profile only, profile plus marks, or full overlay. Import keeps existing replace/keep/merge behavior and source/event-bound feedback safeguards. This redesign does not change package schemas, historical scores or feedback provenance.

A video on comparison stage B and a fitted coaching profile are different things. The former is a visual reference; the latter is a versioned measurement reference for optional analysis. Neither is implicitly inferred from a filename or another person on screen.

## Analysis and limits

The default app uses local person detection and BlazePose, followed by pack-driven phases and metrics. Implement position is inferred from hands/forearms; it is not a directly detected tool. A style-match score measures similarity to the selected reference, not universally good technique. Every result keeps its measured deltas, coverage and warnings.

Long inference does not hold the transport's short-operation lock. Analysis failure leaves review usable. The redesign does not promote research detectors, invent coaching instructions, add transcription or claim named-athlete recognition. See [architecture](../../docs/ARCHITECTURE.md), [research status](../../docs/RESEARCH_STATUS.md) and [validation](../../docs/VALIDATION.md).

## Tests

After font provisioning:

```sh
flutter analyze
flutter test --coverage

# Focused visual, persistence and recovery checks.
flutter test test/ui_redesign_test.dart test/review_presentation_test.dart \
  test/thumbnail_service_test.dart test/ui_restore_test.dart --reporter expanded

# Generate screenshot candidates for inspection, not approved golden baselines.
flutter test test/ui_redesign_test.dart --update-goldens --dart-define=CAPTURE_UI=true
```

Widget screenshots use deterministic test players. Black test video surfaces are not a native-decoder failure or a claim to show real athlete footage. Material icons and the selected fonts are explicitly loaded. CI publishes the screenshot source/scope manifest. Physical-device and native-video checks are separate.

Pure-Dart engine checks, from the repository root:

```sh
(cd packages/analysis_engine && dart pub get && dart analyze && dart test)
```

Native Linux checks, from this app directory with a display and libmpv:

```sh
flutter test integration_test/real_player_test.dart -d linux \
  --dart-define=CLIP_DIR="$PWD/integration_test/assets"
flutter test integration_test/real_pose_test.dart -d linux \
  --dart-define=CLIP_DIR="$PWD/integration_test/assets" \
  --dart-define=REF="$PWD/../../packages/analysis_engine/test/fixtures/cleave_pose.json"
flutter test integration_test/app_e2e_test.dart -d linux \
  --dart-define=CLIP_DIR="$PWD/integration_test/assets" \
  --dart-define=SHOTS="$PWD/build/ui-native-shots"
```

The native workflow uses real licensed/generated media and an explicitly synthetic profile for comparison/package plumbing. Those fixtures do not validate coaching accuracy. Native texture capture can differ from visible device presentation. See [media attribution](integration_test/assets/ATTRIBUTION.md).

For Android decoder/package checks, the existing `scripts/run_android_player_test.sh` remains available. Physical Windows/macOS/iPhone/Android acceptance, production signing and measured profile-mode frame times must be recorded from actual devices; a passing build does not close them.

## Run and build per platform

| Target | Run | Build |
|---|---|---|
| Linux | `flutter run -d linux` | `flutter build linux --release` |
| Android | `flutter run -d <device>` | `flutter build apk --release` |
| Windows | `flutter run -d windows` | `flutter build windows --release` |
| iOS simulator | `flutter run -d ios` | `flutter build ios --simulator` |
| macOS | `flutter run -d macos` | `flutter build macos --release` |

Build Windows on Windows and Apple targets on a Mac. [Distribution](../../docs/DISTRIBUTION.md) distinguishes test packages, signing and actual device acceptance. No release or main-branch merge is implied by the redesign draft PR.

## Data location

The existing SQLite/Drift database remains in platform app support. No SQL schema bump is needed for the additive presentation records in Settings. On Linux the existing location is `~/.local/share/com.strathvision.strathvision/strathvision.sqlite`; Windows uses the application's roaming app-data directory, and Apple/mobile targets use their app-support sandbox.

Original videos remain where selected. Generated thumbnails live in the private `review-previews-v1` app-support cache, bounded by an LRU disk budget. Generation is lazy and single-worker; failures produce finished, tappable fallback tiles. Neither thumbnails nor local view-state records become exported coaching evidence.
