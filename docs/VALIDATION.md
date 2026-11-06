# Validation and acceptance

Software regression checks, compilation, device behavior and coaching validity are separate evidence categories. See [ROADMAP](ROADMAP.md) for unresolved acceptance and the [research reports](RESEARCH_STATUS.md) for measurement results.

## Audit run, 2026-11-06

Local verification before publication: 112 engine tests, 144 app unit/widget tests, 74 Python tests and five isolated handoff tests passed. Analyzer checks were clean. Native Linux playback passed 4/4, the full desktop workflow passed 1/1, and native pose passed 1/1, including 2.1 cm median agreement with the same-model reference (not motion ground truth). Line coverage: engine 91.4%, app 80.7%, excluding generated Dart. CI artifacts provide subsequent per-commit measurements.

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

CI uses Xvfb and software rendering. The first suite checks actual decoder positions, sync, stepping, slow playback, probing and lazy video initialization. The second checks native pose determinism, orientation, reference agreement and the analysis path. [Fixture attribution](../apps/strathvision/integration_test/assets/ATTRIBUTION.md) applies. Agreement with the same model's reference is not ground-truth motion accuracy.

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
