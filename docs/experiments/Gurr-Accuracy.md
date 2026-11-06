# Gurr Academy tracking and stroke-timing pilot

This pilot tests whether the system follows a spatially selected competitor within one shot and locates visible axe contacts. It uses a small visually reviewed subset of the five-part export. The reference annotations are produced by Codex from source frames without viewing model predictions; they are single-reviewer annotations, not independent expert ground truth. Coach review and a larger evaluation remain necessary.

## Protocol fixed before scoring

- Split by source video SHA-256. A source and all duplicate copies belong to one partition. Development clips may inform fixes; test predictions remain unopened until the revised pipeline is frozen.
- Include clear standing-block training, crowded competition, sideways capture, an underhand heat, and pauses without strikes. The single underhand source is reserved for test; this pilot cannot establish broad underhand generalization.
- Each window supplies only the source hash/path, start/duration, chosen event and one initial point selecting a competitor. No names, appearance embeddings, future target positions, reference rotation or contact annotations enter inference.
- Review source frames sampled at 10 fps. Record visible contact-time intervals, sparse torso points, orientation correction and uncertain intervals. Freeze annotations and their SHA-256 before generating predictions. Do not invent technique feedback from these timing annotations.
- Score target containment at five sparse checkpoints, requiring a selected person box to contain the reference torso point. Also report missing selections and changes of selected track segment. This is a sparse target-selection check, not full multi-object tracking accuracy or named-person recognition.
- Match contact predictions one-to-one to reference intervals with 0.20 seconds tolerance outside each interval. Report precision, recall, F1, false positives on idle windows and midpoint timing error. Ignore predictions and references outside the scoring interval or within explicitly uncertain intervals; report their excluded duration.
- Preserve the committed 5 fps engine as the baseline. Evaluate improved sampling, orientation handling and spatial target continuity without overwriting historical corpus results. Record source/model/configuration hashes for both variants.
- Freeze the revised pipeline before opening test scores. Report development and test separately, including failures. Do not claim coaching or learning improvement from better tracking/timing scores.

## Coach-learning follow-up

A genuine-feedback experiment requires actual coach red/green judgments or reviewed spoken comments bound to strokes and attributes. Timing references are not coach judgments. Keep source recordings grouped between fitting and held-out evaluation, retain the default readiness gates, and publish accepted edits, objective changes and hull checks only when measured.

Status: the first pilot is complete. The revised inference was committed as `1dba7b9` before test inference; references and code were not changed after opening test scores.

## Frozen references

The pilot has ten eight-second windows from ten distinct source recordings: five development and five test. There are 49 visible torso checkpoints, one explicitly occluded checkpoint, and 22 annotated contact intervals across five action windows. Three handling/pause windows have explicitly empty contact lists. Two crowded windows are tracking-only because the contact point is hidden; their `null` contact lists are never interpreted as zero strikes.

[Inference inputs](evaluation/gurr-inputs.json) contain initial spatial selections and event settings. [Scoring references](evaluation/gurr-reference.json) contain future checkpoints, rotation and contacts and are supplied only to the evaluator. Contact scoring excludes the first/last 0.3 seconds; the development competition case stops scoring contacts at +4.2 seconds while the operator moves behind the log. All source files appeared in the earlier unlabelled ingestion run; the test labels and pilot scores have not been used to select improvements.

Frozen reference SHA-256: `fbd2205f6983fdbd15743a7a441df005ebdd51caa36ab124554783de975f3712`.

Frozen inference-input SHA-256: `6108021c5e7aa685628c3ea94e2d005bc7cb70dd3910e033e67004f786d9476b`.

## Development findings and frozen revision

The 5 fps baseline retains the initial anonymous IoU track ID. The revision samples at 15 fps, compares person confidence at the selected initial point under four quarter-turns, and follows box geometry within the shot. Loss of continuity or a camera cut requires explicit reselection; it never silently binds a returning detection to the previous competitor. This prevents the development failure where a bystander occupied the original selection position after the operator moved out of view.

Development target containment improved from 16/24 to 22/24 checkpoints. The remaining two checkpoints are missing selections; neither is counted as a success. The revision corrected both sideways development windows. The committed engine still produced no contacts matching the seven reviewed development strikes, even with improved pose input.

A separate experimental wrist-extension proxy matched four of seven development contacts, with no extra predictions in the scored intervals. It uses image-space wrists relative to hips, normalized by person-box height, a 0.12 extension prominence, 0.6 s candidate separation and a three-second prominence search. Arrival at 85% of extension estimates contact. Standing-block direction comes only from initial wrists relative to hips; underhand uses downward extension. This is a motion proxy: it neither detects the axe head nor proves wood contact. It remains research-only and does not manufacture engine phases or mark its candidates usable for coaching.

[Pipeline freeze](evaluation/gurr-pipeline-freeze.json) records inference, scoring, replay, model, input, reference and committed-engine hashes. Development results: [baseline](evaluation/gurr-development-baseline.json), [revised input through the same engine](evaluation/gurr-development-revised.json), and [experimental wrist proxy](evaluation/gurr-development-proxy.json). No source or parameter changes are permitted after opening this pilot's test scores.

Verification before test: 22 Python research tests pass, including duplicate-proof one-to-one contact matching, source-disjoint splitting, stale-result rejection, rotation transforms, ambiguity/loss handling and a test-inference freeze guard. The Dart replay tool passes analysis and runs on the saved engine snapshot.

## First pilot test results

The five source-disjoint test windows contain 25 visible target checkpoints and 15 annotated contacts. This is a small within-corpus pilot with one visual reviewer.

| Measurement | Baseline, 5 fps | Revised selection/orientation, 15 fps |
|---|---:|---:|
| Target checkpoints containing the reference torso point | 20/25 | 24/25 |
| Missing target selections at checkpoints | 5 | 1 |
| Selected boxes missing the reference point | 0 | 0 |
| Correct orientation | 4/5 windows | 5/5 windows |
| Committed-engine contact matches | 0/15 | 0/15 |
| Extra committed-engine contact predictions | 0 | 1 |

The tracking/orientation revision improves this sparse target test; it does not establish full tracking accuracy, named identity recognition, pose-angle accuracy or coaching correctness. Its one missed checkpoint remains a failure.

The wrist-extension proxy matched **3 of 15** contacts, produced **5 false predictions**, and missed **12 contacts**: precision 37.5%, recall 20%, F1 0.261. Two false predictions occurred in handling/pause windows. Its mean midpoint error on the three matched contacts was 0.078 s; that number excludes missed and false predictions and is not overall timing accuracy. **The proxy fails this pilot and remains research-only.** No parameters were changed after this result.

Test evidence: [baseline](evaluation/gurr-test-baseline.json), [revised input through the committed engine](evaluation/gurr-test-revised.json), and [wrist proxy](evaluation/gurr-test-proxy.json). These failures are published alongside the tracking improvement. No coach judgments or learning gains were generated.

## Existing phase-code follow-up

A separately captured copy of Claude's pre-existing, uncommitted engine changes replaces standing-block height events with reach/stop/release and segments at speed stops. It passes 108 engine tests and matches 3/7 contacts on the original development set, versus zero for the committed engine. Its code and parameters were not changed during this study.

The follow-up uses three additional source recordings, excluded from both partitions of the first pilot. Its inputs, references and candidate source hashes were committed in `1d8058e` before follow-up inference. The 24-second set contains three annotated contacts in one clear training window, one pause window with zero contacts, and one rear-view tracking-only window with unknown contact timing. This is a narrow standing-block check, not broad validation on competition contacts.

| Fresh follow-up, identical revised pose inputs | Committed engine | Existing phase candidate |
|---|---:|---:|
| Contact matches | 0/3 | 3/3 |
| False contact predictions | 1 | 1 |
| False predictions in the scored pause | 0 | 0 |
| Sparse target checkpoints covered | 14/15 | 14/15 |
| Mean midpoint error on matched contacts | unavailable | 0.206 s |

The candidate helps this small training example, but it has one extra contact and a roughly 0.2-second delay on the matches. It remains a candidate; no coaching accuracy or learning gain is established. The proxy rejected by the first pilot is not silently substituted for the engine.

Follow-up evidence: [inputs](evaluation/gurr-phase-inputs.json), [visual references](evaluation/gurr-phase-reference.json), [source freeze](evaluation/gurr-phase-freeze.json), [committed-engine results](evaluation/gurr-phase-baseline-results.json), and [candidate results](evaluation/gurr-phase-candidate-results.json).

The [experimental candidate patch](evaluation/standing-block-phase-candidate.patch) preserves the existing engine changes and their tests without staging or overwriting the shared engine/app files. Applying it to an isolated checkout of `5861e2f` was checked to reproduce every recorded candidate library/pack hash. The follow-up freeze records the original pipeline freeze time separately from the follow-up commit time; inference configuration and references were fixed before scoring.


## Reproduce and review

Use the pinned Python environment and model hashes from [the corpus setup](Gurr-Academy.md#reproduce-the-run). Use an isolated checkout of engine commit `5861e2f`; copy the current repository's `packages/analysis_engine/tool/accuracy_contacts.dart` into that checkout's `packages/analysis_engine/tool/` directory. Do not replace its engine library or timber pack for the baseline.

From the current repository root, set the local paths and generate predictions:

```sh
SV_REPO="$PWD"
SV_ENGINE_ROOT='/path/to/isolated-checkout-at-5861e2f'
SV_DATA='/path/to/private-analysis'
SV_FOOTAGE_ROOT='/path/to/Gurr Academy '
SV_PY="$SV_DATA/venv/bin/python"
for SV_VARIANT in baseline revised; do
  for SV_PARTITION in development test; do
    "$SV_PY" tools/carne_asada/predict_accuracy.py \
      --inputs docs/experiments/evaluation/gurr-inputs.json \
      --root "$SV_FOOTAGE_ROOT" --output "$SV_DATA/predictions/$SV_VARIANT" \
      --detector "$SV_DATA/yolox_nano.onnx" \
      --pose "$SV_ENGINE_ROOT/apps/strathvision/assets/models/pose_landmark_full.onnx" \
      --variant "$SV_VARIANT" --partition "$SV_PARTITION" \
      --freeze docs/experiments/evaluation/gurr-pipeline-freeze.json
  done
done
```

From the isolated engine's `packages/analysis_engine` directory, replay each prediction directory:

```sh
dart pub get
dart run tool/accuracy_contacts.dart "$SV_DATA/predictions/baseline" "$SV_DATA/baseline-contacts.json"
dart run tool/accuracy_contacts.dart "$SV_DATA/predictions/revised" "$SV_DATA/revised-contacts.json"
```

Return to the current repository root to score a partition and run the experimental proxy:

```sh
"$SV_PY" tools/carne_asada/score_accuracy.py \
  --reference docs/experiments/evaluation/gurr-reference.json \
  --predictions "$SV_DATA/predictions/revised" --contacts "$SV_DATA/revised-contacts.json" \
  --partition test --output "$SV_DATA/revised-test-results.json"
"$SV_PY" tools/carne_asada/motion_contacts.py \
  "$SV_DATA/predictions/revised" "$SV_DATA/proxy-contacts.json"
```

Score the proxy with the same scorer and its contact file. For the fresh phase follow-up, substitute `gurr-phase-inputs.json`, `gurr-phase-reference.json`, and `gurr-phase-freeze.json`, use a separate prediction directory, and replay against both the unchanged baseline and a separate engine checkout with the recorded candidate patch applied. Keep baseline and candidate replay files separate.

The next evidence needed is coach review of these timing references, broader fresh source clips, and actual implement/contact validation. Genuine attribute-specific coach marks are required for CARNE ASADA learning. All timing references remain distinct from red/green technique judgments. This work adds research commands and measured evidence; it does not complete app integration or known-athlete recognition.
