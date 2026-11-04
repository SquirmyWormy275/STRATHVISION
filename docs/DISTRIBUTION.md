# Distribution for Testing

The locked test-distribution paths (DECISIONS.md "Distribution"). No store, no accounts, no cloud.

Every push to `implementation` that touches the app runs `.github/workflows/builds.yml`. It runs the tests, then builds an Android APK, Linux, Windows and macOS zips, and an unsigned iOS app. Download them from the run's **Artifacts** on the Actions tab.

## Android: APK sideload

```sh
cd apps/strathvision
flutter build apk --release        # build/app/outputs/flutter-apk/app-release.apk
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Or copy the APK to the phone and open it. The phone must allow installs from that app (Settings → Apps → Special access → Install unknown apps). Test builds use Flutter's default signing. For a build that keeps updating across machines, add a release keystore in `android/key.properties` (Flutter "Build and release an Android app" guide).

## iOS: ad-hoc IPA (up to 100 devices)

Needs a Mac with Xcode and a paid Apple Developer account.

1. In the Apple Developer portal, register each tester's device UDID (Finder → the phone → click the serial number to reveal the UDID).
2. Create an **Ad Hoc** provisioning profile for the app id `com.strathvision.strathvision` that includes those devices. Download it.
3. Open `apps/strathvision/ios/Runner.xcworkspace` in Xcode. Under Runner → Signing & Capabilities, choose your team and the Ad Hoc profile.
4. Build the IPA:
   ```sh
   cd apps/strathvision
   flutter build ipa --release --export-method ad-hoc
   # build/ios/ipa/strathvision.ipa
   ```
5. Install it from Finder (drag the IPA onto the connected phone) or with Apple Configurator. A device not in the profile will refuse it.

The CI `ios` artifact is an unsigned `Runner.app`. It proves the build compiles, but it still has to be signed with steps 2–4.

## Desktop: zip of the Flutter build

| Platform | Build on | Command | Run |
|----------|----------|---------|-----|
| Linux | Linux | `apps/strathvision/scripts/package_desktop.sh` | unzip, then `./strathvision` (needs `libmpv` installed: `apt install libmpv2` / `pacman -S mpv`) |
| macOS | macOS | `apps/strathvision/scripts/package_desktop.sh` | unzip, then right-click → Open the first time (unsigned) |
| Windows | Windows | `flutter build windows --release` then `Compress-Archive build\windows\x64\runner\Release\* strathvision-windows-x64.zip` | unzip, then run `strathvision.exe` |

## Moving profile packages between devices

Packages are ordinary `.zip` files, and the app never needs a cloud.

- **Export:** Library → a profile's share icon saves `<Coach>_vN.zip`. It contains the coaching profile, specialist patches and adapters. CARNE ASADA research records stay on the computer.
- **Carry it** any local way: AirDrop, USB, a message attachment, a local network share.
- **Import:** Library → open icon → pick the zip.
- **Shared inbox folder:** Library → ⋮ → **Inbox folder…**, then pick a folder that syncs between your devices (for example Syncthing) or that you copy into. New packages in it are imported when the app starts and when the folder is chosen. Each one is copied into the app first, so the folder can be cleaned up afterwards.
