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

### iPhone analysis and expanded regression audit, 2026-11-24

Inspection of the actual signed TestFlight **1.63.1 IPA** confirmed that archive
stripping removed the `_OrtGetApiBase` dynamic export. The previous pre-archive
symbol check and synthetic simulator model test missed this delivery defect.
[Binary evidence](verification/iphone-analysis-20261124.json) records the old
artifact hashes and independent export-table checks. The release now preserves
external symbols, and the unsigned archive, signed archive and final exported IPA
must all pass the dynamic-export verifier before upload.

The expanded audit also reproduced and corrected these failures:

| Failure | Regression evidence |
| --- | --- |
| Native startup failures left empty/stale analysis | Phone error display, retry, and core playback remain usable |
| Photos picker exports could disappear with temporary cleanup | Every new iOS pick is copied before saving; native test deletes the original export |
| An iOS update could invalidate owned absolute clip/profile paths | Actual directory relocation and database reopen preserve bytes, profile version, marks, notes, athlete choice and history |
| Replacing footage at the same path reused old tracking | A failing-before/passing-after test verifies the changed athlete; production cache keys use current content and each explicit Analyze action refreshes the result |
| Cancel during transcript persistence still left a draft | A failing-before/passing-after test verifies both memory and disk are cancelled; retained audio can retry |

The final local app suite passed **222 tests**, with the opt-in live compiler
excluded from the default run; the engine passed **116** and scripts passed **35**.
The separately attempted live compiler check could not execute: installed Claude
Code 2.1.331 reported `loggedIn: false`, and no adapter was produced. The historical
2026-11-11 live success is not presented as a current authenticated check.
Both analyzers were clean. The native phone-layout check used the real decoder,
shipped models and production analysis runner: **10 finite measurements and one
usable stroke**, then imported a synthetic coach fixture, compared all ten
measurements using its patch and adapters, and reopened saved comparison history.
The fixture checks software operation, not a validated coaching profile.

Additional native Linux checks passed for HDR/SDR decoding, sideways detection,
no-person rejection, corrupt-video rejection and the CARNE experiment export/cache
flow. The iOS simulator gate now includes real-video analysis, package comparison,
history persistence and those media/error cases. The licensed test assets are
staged only for the test and excluded from release bundles. A failed grouped Linux
test launch was repeated as separate invocations; all individual checks passed.
Run Flutter unit and native commands sequentially in a checkout: overlapping
builds can overwrite their shared shader/native-asset test manifests.

The corrected unsigned archive passed its export gate in interim run `45486844873`; that run was deliberately cancelled before upload so the broader audit fixes could ship together. The final cloud run and signed replacement IPA are pending. Physical iPhone
acceptance is still required: simulator operation and package inspection do not
establish actual-device behavior. Already-deleted temporary clips require reimport.


### Local voice review, 2026-11-24

Issue #4 adds optional local transcription with pinned runtime/model integrity,
bounded processes, cancellation, timeout and retry. The complete app suite passed
**204 tests with one existing opt-in live-compiler skip**. The analyzer was clean,
the Linux release built successfully, and three setup-integrity tests passed.
Synthetic tests separately cover
explicit review, persisted consent before learning, idempotence, draft rejection,
source/audio changes, late cancellation, failed saves and conservative rollback
of dependent edits. Sufficient synthetic footage plus explicitly accepted feedback
can enter the existing bounded loop; unreviewed text cannot create marks or issue
commands.

Real 11-second historical speech passed through the adapter on Linux, Windows and
Intel macOS. The packaged app integration supports **Linux and Windows**; macOS
app setup fails closed pending a signed bundled helper compatible with its sandbox.
The native Linux UI test on source `5380ff2dcc3696789a6f8a4b70b8a252f6b68f1b`
also transcribed that recording, opened the editable review dialog, kept acceptance
disabled without a source/swing, and persisted a draft correction. It used a
synthetic profile, no video measurements and no accepted feedback. See
[voice setup, platform evidence and limitations](VOICE_NOTES.md). These checks do
not establish coaching accuracy, multilingual accuracy or physical Windows UI
acceptance, and do not change the iPhone beta.

### Reproduce regression checks

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

Windows/macOS builds and unsigned iOS compilation cannot close these checks. Apple signing and actual target hardware are required. Live adapter compilation ([issue #5](https://github.com/SquirmyWormy275/STRATHVISION/issues/5)) was observed on 2026-11-11 through the Claude Code CLI path (`claude-code:claude-opus-5-5`, Claude Code 2.1.322, no API key). Both timber/underhand specs compiled on the first attempt and passed every pack example: `usable_footage` (5 examples) and `priority_scorer` (4). The `.paw` files then reloaded through `loadAdapters` with no compiler present and passed every example offline. Evidence: [live-adapter-compile-20261111.json](verification/live-adapter-compile-20261111.json); rerun with `LIVE_COMPILER=1 LIVE_OUT=<file> flutter test test/live_compiler_test.dart`. The raw-HTTP API-key path is still covered only by request/response fixtures. Timeout, sign-in, unreadable-output and missing-CLI failures are covered by fixture tests. A successful compile is not coaching accuracy.
