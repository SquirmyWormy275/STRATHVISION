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

Status: source-frame annotation in progress; no pilot accuracy result has been claimed.

## Frozen references

The pilot has ten eight-second windows from ten distinct source recordings: five development and five test. There are 49 visible torso checkpoints, one explicitly occluded checkpoint, and 22 annotated contact intervals across five action windows. Three handling/pause windows have explicitly empty contact lists. Two crowded windows are tracking-only because the contact point is hidden; their `null` contact lists are never interpreted as zero strikes.

[Inference inputs](evaluation/gurr-inputs.json) contain initial spatial selections and event settings. [Scoring references](evaluation/gurr-reference.json) contain future checkpoints, rotation and contacts and are supplied only to the evaluator. Contact scoring excludes the first/last 0.3 seconds; the development competition case stops scoring contacts at +4.2 seconds while the operator moves behind the log. All source files appeared in the earlier unlabelled ingestion run; the test labels and pilot scores have not been used to select improvements.

Frozen reference SHA-256: `fbd2205f6983fdbd15743a7a441df005ebdd51caa36ab124554783de975f3712`.

Frozen inference-input SHA-256: `6108021c5e7aa685628c3ea94e2d005bc7cb70dd3910e033e67004f786d9476b`.
