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

## Run and build per platform

| Target | Run | Build |
|--------|-----|-------|
| Linux | `flutter run -d linux` | `flutter build linux --release` |
| Android | `flutter run -d <emulator-id>` | `flutter build apk --release` |
| Windows (on Windows) | `flutter run -d windows` | `flutter build windows --release` |
| iOS simulator (on a Mac) | `open -a Simulator && flutter run -d ios` | `flutter build ios --simulator` |
| macOS (on a Mac) | `flutter run -d macos` | `flutter build macos --release` |

Flutter only builds Windows apps on Windows, and only builds iOS and macOS apps on macOS.

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
