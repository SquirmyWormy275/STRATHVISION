# Full-population native Gurr experiment

This run covers every one of the **47 unique recordings, 7,787.428656 seconds**, in the verified five-part export. The earlier full-corpus pass used an older research pipeline at 5 Hz. The later native study used thirteen short windows and the first review packet contained twelve eight-second excerpts. Those are historical results; this experiment requests complete source durations through the native person/pose and phase pipeline.

## Method and current execution

The run is in progress. Its isolated runtime contains the committed native pipeline plus `36d02c8`, the empty-opening search fix described below. Full original recordings are read directly, with a maximum sampling rate of 30 Hz and a 90,000-sample budget per source. No earlier pose cache counts as new output. Each recording runs in a separate release-mode Flutter process; five workers save independent source-keyed results, poses and measured stroke vectors. Source bytes, native executable, model/code hashes and settings are frozen before the run. Interrupted work can resume only under the same runtime key.

The production four-second selection preflight is exercised first. If it requests a competitor, diagnostic processing continues through the full source and its measurements remain quarantined from production eligibility. Both existing event packs are candidate stress-test passes. Catalog event hints are unreviewed, and the four springboard sources remain explicitly unsupported by this pinned pack. Candidate counts are not human-confirmed strokes, correct-athlete identity or technique accuracy. No reviewed coaching profile/feedback is supplied, so a learning loop is not executed.

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

Back in the original repository, freeze and run. `--display` is an existing X display; the recorded run used a private Xvfb server. It does not require changing desktop settings.

```sh
"$SV_PY" tools/carne_asada/population.py freeze --directory "$SV_POP"
"$SV_PY" tools/carne_asada/population.py run --directory "$SV_POP" --workers 5 --display :93
"$SV_PY" tools/carne_asada/population.py publish --directory "$SV_POP" \
  --output '/path/to/private-analysis/population-results.json'
"$SV_PY" tools/carne_asada/population_review.py prepare --directory "$SV_POP" \
  --references docs/experiments/evaluation --workers 2
# Once inference completes, before starting the review server:
"$SV_PY" tools/carne_asada/population_review.py candidates --directory "$SV_POP"
"$SV_PY" tools/carne_asada/feedback_review.py serve --directory "$SV_POP/review-all47"
```

The publisher refuses missing, duplicate, changed-runtime or truncated-source records, and rejects production eligibility for quarantined/unsupported candidates. A completed native call and evidence reaching the final planned sample are reported separately. Full-population coverage without independent annotations is not a new held-out accuracy result.
