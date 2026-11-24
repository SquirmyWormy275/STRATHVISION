# Distribution for Testing

Test-distribution paths are defined in [DECISIONS](DECISIONS.md#distribution). The app's review and analysis runtime remains local-first. Optional TestFlight distribution uses the maintainer's Apple Developer membership and GitHub-hosted macOS builds; it does not upload user footage or add an app login.

Every pull request to `main` or `implementation`, and every push to `main` runs `.github/workflows/builds.yml`. It runs Dart/Flutter and Python tests, reports line coverage, checks documentation links and handoff isolation, runs native decoder/pose smoke on Linux, and builds an Android APK, Linux, Windows and macOS zips, and an unsigned iOS app. Download them from the run's **Artifacts** on the Actions tab.

## Release preparation

A distributable release must identify one source commit and one successful `builds` run containing all eight successful jobs: unit checks, research checks, training-dependency compatibility and the five platforms. Download all five platform artifacts from that same run, check their archive contents, and record SHA-256 checksums alongside the run URL and source commit. Never mix artifacts from different commits or call an unsigned iOS app an installable IPA.

The normal workflow provides test distribution: Android uses a debug signing key, macOS is unsigned, and the default iOS artifact is unsigned. An explicitly requested TestFlight run adds a ninth job that signs and uploads iOS after all eight existing jobs pass. A release candidate must state which artifacts are signed. General availability additionally requires stable production signing and the physical-device acceptance record in [VALIDATION.md](VALIDATION.md). Independent coaching/model validation remains a separate research gate.

## iOS: TestFlight from Linux through GitHub Actions

The maintainer can prepare and trigger the build from Linux. GitHub runs Xcode on its hosted Mac; testers install through Apple's TestFlight app. No Codemagic account is needed: the workflow uses its open-source CLI tools, as documented in [Flutter's iOS release guide](https://docs.flutter.dev/deployment/ios).

**Current readiness:** the workflow and local validation helpers are implemented. Apple membership and the app registration have been verified; API access and private signing material remain to be configured. A signed upload and real iPhone acceptance are still unverified. A successful unsigned build does not close those gates.

All eight validation jobs passed for source `e073b73` in [cloud run 45340735890](https://github.com/SquirmyWormy275/STRATHVISION/actions/runs/45340735890) on 2026-11-24. This includes the unsigned iOS release build, its native runtime symbol check, and both shipped models executing on synthetic input in an iPhone Simulator. The optional signed-upload job was deliberately skipped (`upload_testflight=false`).

### One-time Apple setup

1. The Apple Account must have an active **Apple Developer Program** membership and access to [App Store Connect](https://appstoreconnect.apple.com/). A free developer login or a pending enrollment is insufficient. Resolve enrollment/payment status with [Apple Developer Support](https://developer.apple.com/contact/) before creating signing credentials.
2. Register the explicit bundle ID `com.strathvision.strathvision` under the intended Apple team. Create an iOS app record named **STRATHVISION**, using that bundle ID, English as the primary language and an internal SKU such as `strathvision-ios`. Record its numeric **Apple ID** and the membership's **Team ID**. The name must be available in that account.
3. In **Users and Access → Integrations → App Store Connect API**, the Account Holder requests API access if needed, reviews Apple's terms and submits the request. After approval, create a dedicated **team API key** named `STRATHVISION GitHub`. The [signing tool's guide](https://docs.codemagic.io/yaml-code-signing/alternative-code-signing-methods/) recommends the **App Manager** role. [Apple's API guide](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/) explains that a team key's role applies across all apps in the account; it cannot be restricted to this app alone. Save its Issuer ID, Key ID and one-time `.p8` download outside the checkout. The account owner completes agreement, authentication and API-access approval steps.
4. Reuse a compatible distribution-certificate private key if one already exists. Otherwise generate one persistent 2048-bit RSA private key outside the checkout with restrictive file permissions, and retain it for later builds. The workflow finds or creates the corresponding distribution certificate and App Store profile. It does not revoke certificates or delete stale profiles. If Apple reports a certificate limit, stop and reconcile existing signing material.

### GitHub environment

Use the repository environment **`testflight`**, with deployment branches restricted to the branch **`implementation`**. The signing job is also restricted to that branch and to an explicit manual request. Ordinary pull requests and pushes cannot run it.

| Kind | Name | Value |
|---|---|---|
| Variable | `IOS_TEAM_ID` | Ten-character Apple team identifier |
| Variable | `APP_STORE_ID` | Numeric Apple ID from the STRATHVISION app record |
| Secret | `APP_STORE_CONNECT_ISSUER_ID` | Issuer UUID from the team API keys page |
| Secret | `APP_STORE_CONNECT_KEY_IDENTIFIER` | Ten-character Key ID |
| Secret | `APP_STORE_CONNECT_PRIVATE_KEY` | Entire downloaded `.p8` PEM, with its newlines |
| Secret | `CERTIFICATE_PRIVATE_KEY` | Persistent 2048-bit RSA PEM used for the distribution certificate |

Private material never belongs in commits, chat messages, app assets or build artifacts. An operator can import local key files through `gh secret set --env testflight` using standard input; the key contents need not be displayed. Store these values in this environment so signing access follows its branch restriction.

### Build and upload

From **Actions → builds → Run workflow**, choose **implementation** and enable **upload_testflight**. The existing workflow can also be dispatched against that branch without merging into `main`:

```sh
gh workflow run builds.yml --ref implementation -f upload_testflight=true
```

Keep the option false for ordinary validation. A TestFlight run:

1. Runs all eight existing checks/platform builds for one source commit.
2. Selects Xcode 26.3 on `macos-15-intel`, installs the pinned CLI, and checks the Apple app record against the committed bundle ID.
3. Uses the persistent signing key to fetch or create signing assets in a temporary keychain. It verifies the selected team and App Store export method before building.
4. Chooses a build number above both Apple's latest beta and the workflow run/attempt floor. Uploads are serialized; retries retain distinct build numbers even if Apple has not indexed an earlier upload yet.
5. Builds the IPA and checks its bundle ID, build number, SDK and embedded distribution profile before Apple package validation and upload.
6. Adds beta test notes and retains the IPA plus `testflight-manifest.json` for 14 days. The manifest records the source commit, run URL, app version/build, SDK, IPA SHA-256 and upload status. A candidate manifest is not proof of upload; `uploaded-test-notes-added` is written only after the upload command and test-note update succeed. Apple processing and review remain separate.

The workflow does **not** submit a public App Store release, submit external beta review, assign groups or send invitations. Create an internal TestFlight group for the first real iPhone check. Record cold launch, file picking, two-video sync, slow motion, stepping, notes/reopen, package import and offline inference in [VALIDATION](VALIDATION.md#physical-device-acceptance-record).

After that check, supply the beta description, feedback/review contact and any requested encryption information. Create an external group, submit the first build for Apple's beta review, and invite the intended testers after approval. Builds expire after 90 days. See [Apple's TestFlight workflow](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

### Validation and troubleshooting

```sh
python -m unittest discover -s scripts/tests -v
bash -n scripts/upload_testflight.sh
python scripts/check_links.py
```

The local tests exercise wrong-app/team rejection, expired/development/ad hoc profiles, wrong IPA identity/SDK, missing credentials without secret disclosure, and build-number retries. They do not simulate Apple enrollment, native codesigning or a phone installation.

The iOS Podfile replaces only the ONNX Runtime plugin's native pod. Its old Microsoft CocoaPods archive returned HTTP 404 during the 2026-11-24 cloud build. The replacement uses the same **1.15.1** C API and official device/simulator XCFramework from [Microsoft's NuGet package](https://www.nuget.org/packages/Microsoft.ML.OnnxRuntime/1.15.1), pinned by SHA-256 in `apps/strathvision/ios/onnxruntime.podspec`. It retains Microsoft's MIT license, uses the plugin's existing Dart FFI bindings and leaves other platforms and the shared Pub cache unchanged. CI checks that the release executable contains `OrtGetApiBase` and runs both shipped models on synthetic input in an iOS Simulator. These checks do not establish physical-device behavior or coaching accuracy.

- **Account not enabled / pending enrollment:** resolve the membership with Apple; no workflow setting can activate it.
- **Missing signing inputs:** populate the `testflight` environment; never substitute placeholder credentials.
- **API authorization failure:** verify the team key's role, active membership and accepted agreements. The script stops before creating signing assets when the app-record check fails.
- **Upload succeeded but test-note update failed:** inspect TestFlight for that version/build before retrying. The manifest stays a candidate because full confirmation failed. A rerun uses a new build number.
- **Apple rejects package validation:** keep the failed run and fix the reported bundle/profile/privacy/SDK issue before uploading again. Do not bypass package validation.

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
