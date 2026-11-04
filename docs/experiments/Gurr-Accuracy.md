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

Status: references, development results and the revised pipeline are frozen before test inference. Test results are pending.

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
