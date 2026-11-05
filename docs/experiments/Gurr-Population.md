# Full-population native Gurr experiment

Completed **2026-11-05**: the native person/pose and phase experiment covered all **47 unique recordings, 7,787.428656 seconds (2 h 9 min 47 s)**, in the verified five-part export. It processed **195 bounded windows**, reached every scored core and every original source tail, and retained **207,987 pose samples inside scored cores**. No bounded window failed or needed a retry. Athlete selection restarts per window; this is a full-duration scan rather than continuous identity tracking.

The earlier full-corpus pass used an older research pipeline at 5 Hz. The later native pilot used thirteen short windows and the first review packet contained twelve eight-second excerpts. Those results remain intact. This study includes the full 28 min 39 s `IMG_3747.MOV`, not only its opening.

## Results and what they establish

| Coverage measure | Completed result |
|---|---:|
| Unique original videos | 47 of 47 |
| Completed native windows / scored cores reached | 195 / 195 |
| Original source tails reaching the native final-sample flag | 47 of 47 |
| Pose samples inside scored cores, excluding overlapping context | 207,987 |
| Failed windows / retries | 0 / 0 |
| Windows deferred by the production selection preflight | 30 of 195 |

The stricter final-sample flag was reached in **183/195 context windows**. The other twelve ended 44–67 ms before their requested context endpoint, still 3.93–3.96 seconds beyond their scored core. None omitted a scored tail. The [native results and interval ledger](evaluation/population/gurr-full-windowed-results.json) retain completion, core coverage, progress timestamps and final-sample flags separately.

The matching base engine (`501466a`) reproduced all **195 native measurement maps exactly**, including phase boundaries and quality decisions. The revised engine/pack (`d0d6f46`) then ran on those same cached native poses. Its later tracking changes were **not** re-inferred.

| Event stress-test pass | Candidates, base → revised | Passing phase gates, base → revised | Union seconds passing gates, base → revised | Selection + catalog gates, base → revised |
|---|---:|---:|---:|---:|
| Underhand | 2,122 → 2,122 | 1,498 → 1,498 | 4,536.7 → 4,536.7 | 14 → 14 |
| Standing block | 2,104 → 2,101 | 922 → 952 | 2,880.1 → 2,917.7 | 739 → 756 |
| Springboard, added event | n/a → 2,101 | n/a → 952 | n/a → 2,917.7 | n/a → 67 |

Each event configuration was stress-tested on all 47 recordings. These overlapping passes cannot be added as unique footage or real event counts. The last column additionally requires nondeferred, orientation-sure selection and a matching **unreviewed** catalog hint: 42 standing-block, one underhand and four springboard sources. It does not establish the correct athlete or a ready profile. Springboard currently shares standing-block phases with added knee metrics; its identical phase-gate totals are not independent validation of springboard technique.

The revised standing-block pass accepted 30 more candidates overall, with higher gate counts on **18 sources**, lower counts on **five**, and unchanged counts on 24. This is a modest change in phase acceptance, not demonstrated contact accuracy or coaching improvement. Inspect the [controlled comparison](evaluation/population/gurr-full-engine-comparison.json), [base replay](evaluation/population/gurr-full-engine-base.json) and [revised replay](evaluation/population/gurr-full-engine-current.json).

### Existing timing references: no measured gain

| Already-opened reference subset | Base matches / extra detections | Revised matches / extra detections |
|---|---:|---:|
| Original test: 15 contacts | 2 of 15; 1 extra | 2 of 15; 1 extra |
| Follow-up test: 3 contacts | 2 of 3; 2 extras | 2 of 3; 2 extras |

Phase-gate-only and selection-eligible modes produced the same counts in these scored intervals. [The diagnostic artifact](evaluation/population/gurr-full-opened-reference-diagnostic.json) also contains development results, source/reference hashes and individual predictions. These references were previously inspected, and selection/context differ from the eight-second pilots. This is neither a new holdout nor evidence that more accepted phases are more accurate. The earlier pilot artifacts are unchanged.

### Ready for the first real reviews

All 47 complete playback copies are available in the local review packet, with **960 unreviewed candidate spans across 46 recordings**. `IMG_8069.MOV` has no suggested spans; its complete video can still be reviewed at any time. Suggestions include phase-gated selection diagnostics, so reviewers must check the athlete, event and actual stroke bounds. No red/green judgment is prefilled.

At the [recorded review-status check](evaluation/population/gurr-full-review-status.json), **zero judgments were saved and all 47 initial tasks were pending**. No learning loop was run and no coach-specific improvement is claimed. Known wrong-person and blurred-contact failures, the grip-derived implement proxy, and placeholder springboard metrics remain limitations; see [the separate pipeline findings](Gurr-Pipeline-Findings.md) and [failed axe-detector studies](Gurr-Round2.md).

Verification: **49 Python research tests passed**, the pinned native app passed **128 unit/widget tests and clean analysis**, the real-decoder late-entrant regression passed, and a read-only browser check verified full-length seeking and upright playback. Synthetic UI checks verified event confirmation, save/export, narrow layout and candidate refresh while preserving saved judgments and unsaved edits. Synthetic fixtures are excluded from coaching evidence.

## Method and current execution

The model run and full review packet are complete. All 47 complete browser playback copies have verified durations, audio and upright/HDR-corrected presentation. A read-only Chromium check sought beyond 90 seconds in a real recording, checked a sideways source, and left all judgments unlabelled.

Continuous full-source workers repeatedly received SIGKILL. The sender remains unidentified; cgroup/kernel diagnostics did not establish an OOM cause, and separate transient user services did not eliminate the failures. Those outputs, failed attempts and binary are retained as a separate baseline. Unfinished continuous jobs were deliberately stopped when the bounded execution variant replaced them.

The bounded scan schedules **195 windows covering every source second**: nonoverlapping 45-second scored cores, plus four seconds of context on each side where available. FFV1 inputs losslessly store resized frames with a maximum image edge of 960 pixels and retain HDR transfer metadata, matching the earlier native diagnostic's resolution. The original files remain unchanged. Native sampling is capped at 30 Hz with the 90,000-sample budget. Each window uses the same pinned release-native binary; no older pose prediction is reused.

Prepared windows run in frozen batches while later windows are encoded. Actual prepared-file hashes, executable/model/code hashes and settings are recorded before each batch starts. The batch driver asserts that every batch shares the same native executable and source/model fingerprints. Independent transient services, source locks and saved results make interrupted windows retryable without redoing successful windows.

Automatic athlete/orientation selection restarts per window. This differs from following one person continuously through a whole recording, and it does not add named-athlete identity recognition. The four-second production selection preflight runs first; deferred diagnostics remain quarantined. Both original event configurations are candidate stress-test passes; catalog event hints are unreviewed, and springboard is unsupported by the pinned native pack. Its later engine-only replay is reported separately above.

Only strokes whose midpoints lie within a scored core are retained. Cross-window predictions with interval IoU of at least 0.5 are deduplicated, preferring usable phases and more surrounding context. Source intervals must cover each original recording without a gap or overlapping scored cores. Core endpoint checks allow two sampling intervals for frame-grid differences; final-sample flags are retained separately. Pose counts inside scored cores and counts including context are reported separately. Candidate quality gates are not human-confirmed contacts, correct-person identity, a ready coaching profile or learning evidence.

## A bug found by expanding the population

The baseline returned no athlete for the 725.6-second `Gurr 30DEC25.mov` after examining only its first twelve seconds. An empty opening was treated as an empty recording. The fix continues searching fresh windows across the recording, keeping candidate history bounded so later entrants are not diluted by earlier empty frames. Explicit user targets retain their failure behavior rather than silently switching to someone later.

A real-decoder regression uses fourteen seconds of blank video followed by five seconds of the licensed cleave fixture. The old binary produced zero poses and stopped after 12/19 seconds. The patched binary reached the end and retained 149 pose samples from the later action. It still deferred production selection, as expected from its blank four-second preflight. [Regression artifact](evaluation/population/late-entrant-regression.json). The automated [regression script](../../tools/carne_asada/check_late_entrant.py) accepts before/after runner binaries, the licensed fixture and a private output directory. This checks application behavior, with no synthetic coaching judgments counted as evidence.

In the completed bounded scan, the real 725.635-second recording reached all 17 scored cores and retained **16,163 core pose samples**. The controlled blank-intro regression establishes the early-exit fix; the real recording also uses the different bounded execution method described above.

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

The publisher rejects missing windows, mismatched native runtimes, gaps and duplicate scored cores. It records failed calls and unreached core endpoints; the final comparison refuses incomplete coverage. Completed native calls, final-sample progress and core coverage are distinct fields. Full-population coverage without independent annotations is not a new held-out accuracy result. No reviewed coaching profile/feedback is supplied to this inference run, so no learning loop is executed.


## Controlled engine replay

Saved native poses also run through two separate compiled pure-Dart engines: the matching base at `501466a` and the later fast-rhythm/springboard engine/pack at `d0d6f46`. The [replay tool](../../packages/analysis_engine/tool/population_replay.dart) checks pose provenance; the [driver](../../tools/carne_asada/replay_population.py) requires the base replay to reproduce native stroke spans and quality decisions before accepting its cache. Both executables and source/pack files have separate fingerprints.

This comparison changes the engine/pack while retaining the same native pose observations. It does not re-run the later tracking changes. Candidate counts and interval-union coverage remain diagnostic measures, with genuine coaching effectiveness unvalidated. [Progress reader](../../tools/carne_asada/window_status.py) reports completed model windows and complete original sources without counting context as additional recordings.

After both pinned replay executables have been built in `engine-replay-base/` and `engine-replay-current/`, with their original revisions recorded in `source-revision.txt`:

```sh
"$SV_PY" tools/carne_asada/replay_population.py --parent "$SV_POP" --follow
"$SV_PY" tools/carne_asada/window_population.py publish --parent "$SV_POP" \
  --engine-replay base --output '/path/to/private-analysis/base-results.json'
"$SV_PY" tools/carne_asada/window_population.py publish --parent "$SV_POP" \
  --engine-replay current --output '/path/to/private-analysis/current-results.json'
"$SV_PY" tools/carne_asada/compare_population.py \
  --native '/path/to/private-analysis/population-results.json' \
  --base '/path/to/private-analysis/base-results.json' \
  --current '/path/to/private-analysis/current-results.json' \
  --output '/path/to/private-analysis/engine-comparison.json'
```

The comparison refuses incomplete population coverage, differing native inputs, or a base replay that does not reproduce the native source results. Its per-event durations use the union of retained intervals. Separate event stress-test passes overlap, so their durations cannot be added as unique footage.

The [timing diagnostic](../../tools/carne_asada/score_population.py) can also reuse the original pilot/follow-up references, without editing or adding labels:

```sh
"$SV_PY" tools/carne_asada/score_population.py --parent "$SV_POP" \
  --native '/path/to/private-analysis/population-results.json' \
  --base '/path/to/private-analysis/base-results.json' \
  --current '/path/to/private-analysis/current-results.json' \
  --evaluation docs/experiments/evaluation \
  --output '/path/to/private-analysis/opened-reference-diagnostic.json'
```

It converts entry-phase boundaries back to original-source time, applies the existing ignored intervals/tolerance and one-to-one matcher, and keeps unrated windows distinct from idle windows. It reports both phase-gate-only predictions and the subset passing selection gates. These already-opened references are diagnostic; longer-window context and athlete selection differ from the eight-second pilots.
