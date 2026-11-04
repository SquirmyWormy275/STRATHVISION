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

## Phase 2 manual check

1. Tap **New review**, then **Add a clip** on A and **Add a clip to compare** on B.
2. Scrub each timeline to the same moment (for example, impact) and tap **Sync here**. The pill reads `Locked · B +x.xx s`.
3. Pick **.25×** and press Play (or Space). Both clips play together in slow motion.
4. Use ← / → (or the step buttons) to frame-step the locked pair.
5. Tap Mirror. B flips and the sync pill doesn't change.
6. Choose an attribute chip and tap green or red. A tick appears on the timeline. Undo (Ctrl+Z) removes it.
7. Go back, then reopen the review from **Reviews**. Both clips, the sync, the rate, mirror, and marks come back.

Desktop keys: Space play/pause · ←/→ frame step · S sync here · L lock/unlock · M mirror B · G/R mark · Ctrl+Z undo.

## Phase 1 manual check

1. Launch the app. It opens on **Library**, which says "No profiles yet".
2. Tap **Open workspace**. You get two empty stages, A and B. Go back.
3. Tap the import icon and pick `test/fixtures/dummy_profile.json`.
4. The list now shows **Dummy Coach · v1**, `example_pack / example_event`, 15 clips · 1 metrics, Ready.
5. Close and reopen the app. The profile is still listed.

## Data location

The database is SQLite through Drift, stored in the platform app-support folder:

- Linux: `~/.local/share/com.strathvision.strathvision/strathvision.sqlite`
- Windows: `%APPDATA%\com.strathvision\strathvision\strathvision.sqlite`
- macOS, iOS and Android: the app's sandboxed support directory
