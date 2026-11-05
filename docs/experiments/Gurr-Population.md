# Full-population native Gurr experiment

This run covers every one of the **47 unique recordings, 7,787.428656 seconds**, in the verified five-part export. The earlier full-corpus pass used an older research pipeline at 5 Hz. The later native study used thirteen short windows and the first review packet contained twelve eight-second excerpts. Those are historical results; this experiment requests complete source durations through the native person/pose and phase pipeline.

## Method and current execution

The model run is in progress. The full review packet is ready: all 47 complete browser playback copies have verified durations, audio and upright/HDR-corrected presentation. A read-only Chromium check sought beyond 90 seconds in a real recording, checked a sideways source, and left all judgments unlabelled.

Continuous full-source workers repeatedly received SIGKILL. The sender remains unidentified; cgroup/kernel diagnostics did not establish an OOM cause, and separate transient user services did not eliminate the failures. Those outputs, failed attempts and binary are retained as a separate baseline. Unfinished continuous jobs were deliberately stopped when the bounded execution variant replaced them.

The bounded scan schedules **195 windows covering every source second**: nonoverlapping 45-second scored cores, plus four seconds of context on each side where available. FFV1 inputs losslessly store resized frames with a maximum image edge of 960 pixels and retain HDR transfer metadata, matching the earlier native diagnostic's resolution. The original files remain unchanged. Native sampling is capped at 30 Hz with the 90,000-sample budget. Each window uses the same pinned release-native binary; no older pose prediction is reused.

Prepared windows run in frozen batches while later windows are encoded. Actual prepared-file hashes, executable/model/code hashes and settings are recorded before each batch starts. The batch driver asserts that every batch shares the same native executable and source/model fingerprints. Independent transient services, source locks and saved results make interrupted windows retryable without redoing successful windows.

Automatic athlete/orientation selection restarts per window. This differs from following one person continuously through a whole recording, and it does not add named-athlete identity recognition. The four-second production selection preflight runs first; deferred diagnostics remain quarantined. Both original event packs are candidate stress-test passes; catalog event hints are unreviewed, and springboard is unsupported by this pinned pack. Later application changes are separate from this frozen runtime.

Only strokes whose midpoints lie within a scored core are retained. Cross-window predictions with interval IoU of at least 0.5 are deduplicated, preferring usable phases and more surrounding context. Source intervals must cover each original recording without a gap or overlapping scored cores. Pose counts inside scored cores and counts including context are reported separately. Candidate quality gates are not human-confirmed contacts, correct-person identity, a ready coaching profile or learning evidence.

## A bug found by expanding the population

The baseline returned no athlete for the 725.6-second `Gurr 30DEC25.mov` after examining only its first twelve seconds. An empty opening was treated as an empty recording. The fix continues searching fresh windows across the recording, keeping candidate history bounded so later entrants are not diluted by earlier empty frames. Explicit user targets retain their failure behavior rather than silently switching to someone later.

A real-decoder regression uses fourteen seconds of blank video followed by five seconds of the licensed cleave fixture. The old binary produced zero poses and stopped after 12/19 seconds. The patched binary reached the end and retained 149 pose samples from the later action. It still deferred production selection, as expected from its blank four-second preflight. [Regression artifact](evaluation/population/late-entrant-regression.json). The automated [regression script](../../tools/carne_asada/check_late_entrant.py) accepts before/after runner binaries, the licensed fixture and a private output directory. This checks application behavior, with no synthetic coaching judgments counted as evidence.

Baseline outputs, binary and freeze are retained privately. The population run restarted under the patched runtime; partial baseline results are not mixed into it. Earlier published references, axe-model freezes and results remain unchanged.

## Review all recordings

The separate full-population review packet contains one complete browser playback copy per unique source, preserving audio and making HDR/sideways footage viewable. Start/end controls can select any stroke in a long recording. Unreviewed phase candidates can provide navigation shortcuts; they never prefill a red/green judgment. Reviewers confirm the actual event and stroke bounds. Source identities and fitting/evaluation groups remain fixed, and springboard judgments can be collected while its analysis support is pending in the pinned runtime.

Packet preparation and model inference are separate. Original recordings are unchanged, all raw pixels and per-frame poses stay private, and the existing twelve-task packet is preserved. See [the feedback guide](../FEEDBACK_REVIEW.md) for judgment/export and learning evaluation.

## Reproduce or resume

Use the Python 3.12 environment from [Gurr Academy](Gurr-Academy.md#reproduce-the-run), Flutter/Linux build dependencies, and the deduplicated private `carne-footage/1` manifest. From a checkout containing the committed runner:

```sh
SV_PY='/path/to/private-analysis/venv/bin/python'
SV_POP='/path/to/private-analysis/population'
"$SV_PY" tools/carne_asada/population.py prepare --directory "$SV_POP" \
  --repo "$PWD" --manifest '/path/to/all-five-parts/manifest.json' \
  --root '/path/to/Gurr Academy '
cd "$SV_POP/runtime/apps/strathvision"
flutter pub get
dart run build_runner build -d
flutter build linux --release --target tool/population_runner.dart
```

Back in the original repository, freeze the native model/runtime and start bounded preparation and inference. `:93` denotes the private Xvfb display used here. The batch command can run in another terminal while preparation proceeds; it waits for complete prepared windows.

```sh
"$SV_PY" tools/carne_asada/population.py freeze --directory "$SV_POP"
"$SV_PY" tools/carne_asada/window_population.py prepare --parent "$SV_POP" --workers 2
# May run while preparation above is still active:
"$SV_PY" tools/carne_asada/window_batches.py --parent "$SV_POP" --workers 6 --batch-size 12
"$SV_PY" tools/carne_asada/window_population.py publish --parent "$SV_POP" \
  --output '/path/to/private-analysis/population-results.json'
"$SV_PY" tools/carne_asada/population_review.py prepare --directory "$SV_POP" \
  --references docs/experiments/evaluation --workers 2
"$SV_PY" tools/carne_asada/feedback_review.py serve --directory "$SV_POP/review-all47"
```

Completed-source candidate navigation can be uploaded to the live review server through its candidate API. It atomically preserves saved judgments; browser refresh changes candidate metadata without clearing unsaved fields. The initial twelve-task packet remains intact.

The publisher rejects missing windows, mismatched native runtimes, gaps, duplicate scored cores and incomplete source tails. Completed native calls, final-sample progress and core coverage are distinct fields. Full-population coverage without independent annotations is not a new held-out accuracy result. No reviewed coaching profile/feedback is supplied to this inference run, so no learning loop is executed.
