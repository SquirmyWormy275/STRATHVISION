# Validation and acceptance

Software regression checks, compilation, device behavior and coaching validity are separate evidence categories. See [ROADMAP](ROADMAP.md) for unresolved acceptance and the [research reports](RESEARCH_STATUS.md) for measurement results.

## Audit run, 2026-11-06

Local verification before publication: 116 engine tests, 151 app unit/widget tests, 74 Python tests and five isolated handoff tests passed. Analyzer checks were clean. Native Linux playback passed 4/4, the full desktop workflow passed 1/1, and native pose passed 1/1, including 2.1 cm median agreement with the same-model reference (not motion ground truth). Line coverage: engine 91.4%, app 81.0%, excluding generated Dart. CI artifacts provide subsequent per-commit measurements.

Review regressions also cover missing-frame dropout, late athlete entry after an empty preview, profile-scoped comparison caches, immutable generated versions (including concurrent saves), save-error recovery, and playback settings retained through undo. CI runs on pull requests and main-branch pushes; duplicate implementation-push runs are excluded so cancelled duplicates cannot block required checks.

## Release preparation, 2026-11-06

The inventory branch incorporates the merged audit baseline, including the Ubuntu 24.04 native CI configuration and headless probing fix. Local checks on the combined tree pass: 116 engine tests, 151 app tests, 30 dataset tests, 74 research tests and five handoff tests; both analyzers are clean. Native pose passes again locally.

The optional research training environment replaces vulnerable setuptools/Torch pins with setuptools 84.1.0, Torch 2.13.0 and matching TorchVision 0.28.0. A fresh Python 3.12 installation resolves cleanly. `tools/carne_asada/check_training_env.py` exercises all three research builders with synthetic inputs on CPU and CUDA: finite forward/backward passes, an optimizer step, detection output and weights-only save/load. No footage is read, no pretrained weights downloaded and no historical accuracy result is re-scored. CI additionally gates all platform builds on CPU training-dependency compatibility. Historical environment pins remain in Git for auditing.

Release artifacts must come from one successful eight-job run. Production signing and physical-device acceptance remain open as described in [distribution](DISTRIBUTION.md); a passing build is not a signed iOS IPA or a validated coaching product.

## Automated checks

From the repository root:

```sh
(cd packages/analysis_engine && dart pub get && dart analyze --fatal-infos && dart test --coverage=coverage && dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib)
(cd apps/strathvision && flutter pub get && flutter analyze && flutter test --coverage)
python -m pip install -r tools/carne_asada/requirements.txt
python -m pytest -q tools/carne_asada
python -m unittest discover -s tools/datasets -v
python -m unittest discover -s scripts/tests -v
python scripts/check_links.py
python scripts/coverage_summary.py packages/analysis_engine/coverage/lcov.info apps/strathvision/coverage/lcov.info
```

The dataset suite needs Linux/POSIX and ffprobe/findmnt; install ffmpeg to run its real audiovisual test. It has no Python package dependencies.

Use a separate Python environment for research requirements. Coverage is an executable-line baseline, excluding generated Dart; CI uploads LCOV and a summary. It is not a claim that every native path or model failure is tested. The link check covers relative file destinations, not web availability or heading anchors.

The audit regressions exercise unsafe profile IDs, atomic failure, private import copies, event/source-bound marks, legacy unbound marks, repeated merge, 15 renamed duplicates, failed input recovery, uncertain selection and confidence ordering. Handoff tests use temporary Git repositories to prove unrelated staged/unstaged work stays untouched.

## Native Linux smoke

With GTK development libraries, libmpv and a display available:

```sh
cd apps/strathvision
flutter test integration_test/real_player_test.dart -d linux --dart-define=CLIP_DIR="$PWD/integration_test/assets"
flutter test integration_test/real_pose_test.dart -d linux --dart-define=CLIP_DIR="$PWD/integration_test/assets" --dart-define=REF="$PWD/../../packages/analysis_engine/test/fixtures/cleave_pose.json"
```

CI uses Ubuntu 24.04, Xvfb and software rendering for a fixed GTK/libmpv baseline. Ubuntu 26.04 (`ubuntu-latest` during this audit) showed intermittent native decoder/pose timeouts; support for that combination remains unverified. Native steps have explicit time limits. The first suite checks actual decoder positions, sync, stepping, slow playback, probing and lazy video initialization. The second checks native pose determinism, orientation, reference agreement and the analysis path. [Fixture attribution](../apps/strathvision/integration_test/assets/ATTRIBUTION.md) applies. Agreement with the same model's reference is not ground-truth motion accuracy.

`app_e2e_test.dart` deliberately rejects copied reference footage, then installs the **synthetic** laptop package for comparison/trend/export screens. It no longer presents duplicated footage as a valid independent profile. CI runs it alongside the focused native checks; it also remains useful as a local desktop acceptance run.

## Physical-device acceptance record

Track outstanding devices in [issue #2](https://github.com/SquirmyWormy275/STRATHVISION/issues/2). Fill this record only from observed results:

```text
Commit / build run / artifact SHA-256:
Tester, date, device model, OS and installation method:
Cold launch and native file picker: pass | fail | not tested
Profile import, restart, metadata persistence:
Two clips, sync, 0.25x playback, frame step, mirror:
Marks, undo, reopen:
Desktop package -> phone, compare offline, patches/adapters present:
Renamed identical source matches imported marks:
Same-name different source and legacy marks stay unbound:
Repeat merge leaves mark counts unchanged:
Desktop-only fitting/editing absent on phone:
Evidence links and failures:
```

Windows/macOS builds and unsigned iOS compilation cannot close these checks. Apple signing and actual target hardware are required. Live adapter compilation additionally needs an authorized provider credential ([issue #5](https://github.com/SquirmyWormy275/STRATHVISION/issues/5)); fixture tests do not establish provider availability.
