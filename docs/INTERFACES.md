# STRATHVISION Interfaces

Research image-space implement observations and reviewed feedback follow [AXE_OBSERVATIONS.md](AXE_OBSERVATIONS.md). These records do not replace metric-space `ImplementTrack` with uncalibrated 2D coordinates. Draft judgments remain unlabelled; test-source feedback cannot fit or select a model.

## Reproducible Gurr Academy experiments

[Gurr Academy experiments](experiments/Gurr-Academy.md) defines the real-footage pipeline, anonymous track schema, quality gates and limits on interpreting the published results. Research exemplars use the same prototype scoring in evaluation and inference; gaps in a pose track never count as continuous action.

This document defines contracts only. Implementation must conform. Changes require updating this file first.

## Profile Package (versioned artifact)

A profile is a directory or zip containing at minimum:

```json
{
  "profile_id": "uuid",
  "version": 1,
  "coach_name": "string",
  "pack_id": "timber | olympic_lifting",
  "event_id": "string",
  "metric_schema_version": "string",
  "created_at": "iso8601",
  "source_clip_count": 0,
  "quality_gates": {
    "min_clips_met": true,
    "self_consistency_passed": true,
    "notes": "string"
  },
  "metrics": {
    "metric_key": {
      "center": 0.0,
      "spread": 0.0,
      "weight": 1.0,
      "unit": "string",
      "phase": "string"
    }
  }
}
```

Additional required/optional objects:
- `specialist_patches/` — versioned residual patches (e.g. slope_residual_vN.patch)
- `adapters/` — compile-once adapters (e.g. usable_footage.paw)
- `carne_asada/` — research logs and mixture edit deltas (desktop-only, never required for inference)
- Reference frame indices or thumbnail paths

The JSON above is the minimum required contract for inference.

Optional in `profile.json`:

```json
"reference_clips": [
  { "clip_id": "uuid", "metrics": { "metric_key": 0.0 } }
]
```

These are metric values of the clips the profile was built from, used for `nearest_reference_clip_ids`. They never contain video or file paths.

A reference clip can also be a residual exemplar added by CARNE ASADA: `"exemplar": true, "weight": 0..1, "confidence": 0..1, "source": "the 14-second mark of the X clip"`. Exemplars never define the coach hull.

A package written by the builder is a zip that holds `profile.json`, plus the empty directories `specialist_patches/` and `adapters/`.

## Metric Vector (per analyzed clip)

```json
{
  "clip_id": "uuid",
  "pack_id": "string",
  "event_id": "string",
  "metric_schema_version": "string",
  "phases": {
    "phase_id": {
      "start_frame": 0,
      "end_frame": 0,
      "confidence": 0.0
    }
  },
  "metrics": {
    "metric_key": {
      "value": 0.0,
      "confidence": 0.0,
      "phase": "string"
    }
  },
  "pose_confidence_summary": 0.0,
  "specialist_residuals": {
    "slope_residual": 0.0
  }
}
```

### Metric Vector rules

- `specialist_residuals` has one key per head the pack declares (Pack Analysis Section, `heads`). Every shipped pack declares `slope_residual`, the day-one head in DECISIONS.md. The engine itself has no head names.
- Every `metrics.<key>.phase` names a key in `phases`. Frames are 0-based clip frame indices; `end_frame >= start_frame`. Confidences are 0..1.
- The engine validates its own output. An output that fails validation is returned as `SCHEMA_MISMATCH`, never as a payload.

## Pack Analysis Section

The part of a pack the analysis runtime reads (one per event). Labels and domain words stay in the pack. The engine has no sport-specific logic.

```json
{
  "pack_id": "string",
  "event_id": "string",
  "metric_schema_version": "string",
  "phases": ["phase_id", "..."],
  "metrics": [
    {
      "key": "metric_key",
      "kind": "joint_angle | joint_range | implement_inclination | phase_duration",
      "phase": "phase_id",
      "unit": "string",
      "joints": ["joint", "joint", "joint"]
    }
  ],
  "min_phase_frames": 3,
  "min_pose_confidence": 0.5,
  "min_clips": 15,
  "critical_phases": ["phase_id"],
  "min_critical_pose_confidence": 0.6,
  "self_consistency_threshold": 0.5,
  "heads": [
    { "name": "slope_residual", "kind": "mlp_residual",
      "base": "slope_residual/<pack>-<event>/v1", "target_metric": "metric_key" }
  ],
  "probes": [
    { "name": "string", "head": "slope_residual",
      "kind": "mean_abs_residual | signed_mean_residual | mark_agreement | residual_variance | confidence_correlation",
      "attribute": "string (mark_agreement only)", "tolerance": 2.0 }
  ]
}
```

Per metric (optional): `"aggregate": "mean | start | end | min | max"` (default `mean`). It applies to `joint_angle` and `implement_inclination` and says how the phase's frames reduce to one value. For example, `end` of the downswing gives the value at the moment of entry.

**Heads.** `mlp_residual` = measured error + MLP(features).
- The measured error is the target metric minus the coach's center from the selected profile. It is 0 when no profile is selected.
- The MLP is the DECISIONS.md shape: 64→32 ReLU→1, 2,113 parameters.
- The base weights are seeded from `base`, with a zero output layer. An unpatched head therefore returns exactly the measured error, and accepted patches teach the correction.

**Probes** are evaluated over a set of clips, giving one sample per clip: the head residual, the mean implement-track confidence and the winning red/green mark on `attribute`. Probe values:
- `mean_abs_residual` = mean |r|.
- `signed_mean_residual` = mean r.
- `mark_agreement` = the fraction of marked clips where green ↔ |r| < tolerance and red ↔ |r| ≥ tolerance.
- `residual_variance` = the variance of r.
- `confidence_correlation` = Pearson correlation of |r| with track confidence.

A probe that is undefined for its samples (no marks, or no variation) is null.

**Acceptance rules** (optional per head; a head can be patched on the workbench only if it has them). They restate the DECISIONS.md harness rules in terms of the pack's probe names:

```json
"acceptance": {
  "primary_probe": "slope_bias", "min_improvement": 0.8,
  "no_regress": ["slope_error_deg"],
  "within_fraction": {"phase_stability": 0.05, "track_confidence_correlation": 0.05},
  "max_weight_fraction": 0.02
}
```

A patch is accepted only if all of these hold:
- |primary| shrinks by at least `min_improvement`.
- No `no_regress` probe's magnitude grows.
- Each `within_fraction` probe changes by no more than that fraction of its previous value. Null → null counts as unchanged.
- The cumulative patch touches fewer than `max_weight_fraction` of the head's weights.

**Adapters** (optional per event): short English specs compiled once on the workbench.

```json
"adapters": [
  { "name": "usable_footage", "spec": "English rule…", "outputs": ["usable"], "threshold": 0.5,
    "examples": [ { "inputs": {"pose_confidence": 0.85}, "expect": {"usable": true} } ] },
  { "name": "priority_scorer", "spec": "English rule…", "outputs": ["Slope", "Hinge"],
    "examples": [ { "inputs": {"abs_delta.entry_slope": 3.0}, "expect": {"top": "Slope"} } ] }
]
```

With `threshold`, each output is a yes/no decision. Without it, the outputs compete and the highest score wins. A compiled adapter must reproduce every example.

**Adapter inputs** come from one analysis and, when a profile is selected, its comparison:
- `pose_confidence` and `implement_confidence`
- `phase_confidence.PHASE` and `phase_seconds.PHASE`
- `metric.KEY` and `metric_confidence.KEY`
- `delta.KEY`, `abs_delta.KEY` (distance from the coach, in spreads) and `contribution.KEY`

Inputs that are absent count as 0.

## Compiled Adapter (`adapters/<name>.paw`)

A tiny local model, JSON despite the extension. Inference runs it with no LLM call.

```json
{
  "format": "paw/1", "adapter": "usable_footage", "kind": "logistic",
  "pack_id": "string", "event_id": "string", "spec_hash": "16 hex chars",
  "compiled_by": "model id", "compiled_at": "iso8601", "threshold": 0.5,
  "outputs": { "usable": { "bias": -20.0, "weights": { "pose_confidence": 10.0 } } }
}
```

- `score = sigmoid(bias + Σ weight·input)`.
- An adapter is skipped, with a warning, when:
  - its `spec_hash` no longer matches the pack's spec, so it is stale and must be recompiled
  - it belongs to another pack or event
  - the file is unreadable (`ADAPTER_COMPILE_FAILED`)
- Compiling fails with `ADAPTER_COMPILE_FAILED` (`details.problems`) when the result uses unknown inputs, has the wrong outputs, or still misses examples after the compiler has been given the mismatches.

At inference:
- When `usable_footage` says no, the comparison carries the warning "This clip is below the usable threshold."
- `priority_scorer`'s winner is shown as the suggested focus.

**Stroke and attribute fields** (optional per event):

```json
"stroke_signal": "tops | speed_peaks",
"phase_events": ["low_before_top", "top", "low", "settle"],
"max_implement_dropout_s": 0.3,
"attribute_metrics": { "Slope": ["entry_slope", "downswing_slope"] },
"direction_words": { "entry_slope": { "higher": ["flatter", "flat"], "lower": ["steeper", "steep"] } }
```

- How strokes are found depends on `stroke_signal`:
  - `speed_peaks` (default): one implement-speed peak per stroke, with boundaries midway between peaks. Edge partials and strokes outside 0.5–1.5× the median length are dropped.
  - `tops`: one backswing top per stroke, from the rise before it through contact. The cut after contact sits where the tip has risen 15% of the way back to the next top (at most halfway), so the pause and settle stay with the stroke. A top whose rise is cut off by the clip start counts if it stands out after it.
  - `stops`: one contact per stroke, where a fast swing (a speed peak of at least 40% of the clip's fastest and 4 m/s) stops sharply (below 30% of the peak within 0.6 s). Cuts sit midway between contacts. This works for high and flat swings alike.
- `phase_events` gives one motion event per phase boundary, in order, on the implement tip:
  - `low_before_top` (rise)
  - `top`
  - `fastest`
  - `low` (contact: the descent slows to 20% of its peak)
  - `settle` (speed below 25% of peak)
  - `rise` (start of the backswing: the slowest moment before the reach)
  - `reach` (end of the backswing: the turnaround, the speed minimum just before the fastest point; high or flat)
  - `stop` (contact by speed: after the fastest point, the first sample below 30% of it)
  - `release` (pulled free: back above 30% of the stroke's peak speed)

  Speeds for `stop`, `release` and `stops` use the tip with single-sample pose glitches removed, lightly smoothed.
  
  Without `phase_events`, phases split evenly at confidence 0.5. The first and last phases may be shorter than `min_phase_frames` (cut by the recording), at half confidence.
- A stroke is usable action when phases are assigned, critical-phase pose confidence meets `min_critical_pose_confidence`, and no implement dropout (confidence below 0.5) lasts longer than `max_implement_dropout_s`.
- `attribute_metrics` says which metrics a mark attribute speaks to. CARNE ASADA edits only the priority attribute's metrics.
- `direction_words` give the words used in status copy, as [comparative, plain].

## CARNE ASADA Record (`carne_asada/mixture_edits_vN.json`)

Desktop research record. It is never read for inference: phones and the importer ignore `carne_asada/` entirely. The edited mixture itself ships in `profile.json` (`metrics` center/spread/weight) of version N.

```json
{
  "format": "carne_asada/1", "version": 2, "session_id": "uuid",
  "pack_id": "string", "event_id": "string", "priority": "Slope",
  "limit": 5, "chaos": false, "usable_minutes": 2.9,
  "hull": { "entry_slope": [-81.5, -55.5] },
  "edits": [ { "type": "shift_mean | tighten_spread", "metric": "entry_slope", "phase": "downswing",
               "before": {"center": 0, "spread": 0, "weight": 1, "unit": "°", "phase": "downswing"},
               "after": {"…": "…"}, "explanation": "one sentence",
               "objective_before": 0.4, "objective_after": 0.6, "accepted_at": "iso8601" } ]
}
```

## Pack File

A pack ships as one JSON file. The app loads every bundled pack file at startup, and swapping a pack needs no change to the engine.

```json
{
  "format_version": 1,
  "pack_id": "string",
  "name": "string",
  "attributes": { "top": ["string"], "more": ["string"] },
  "phase_labels": { "phase_id": "Label" },
  "metric_labels": { "metric_key": "Label" },
  "events": [ { "event_id": "string", "label": "string", "...": "Pack Analysis Section without pack_id" } ]
}
```

An invalid pack file is rejected with `SCHEMA_MISMATCH` (`details.problems`) and skipped.

Per metric (optional): `"weight": 1.0` is the pack default weight for style matching. `"min_spread": 0.0` is a floor on the fitted spread, in the metric's unit.

`min_clips`, `critical_phases` (default: all phases), `min_critical_pose_confidence` and `self_consistency_threshold` drive the Quality Gates below.

- `phases` are in movement order.
- `joints` names exactly 3 joints for `joint_angle` and `joint_range` (the angle sits at the middle joint), and none for the other kinds. Joint names come from the generic body set: `pelvis, spine, neck, head, left_/right_shoulder, left_/right_elbow, left_/right_wrist, left_/right_hip, left_/right_knee, left_/right_ankle`.
- `joint_angle`: the mean angle over the phase, in degrees. `joint_range`: max minus min of that angle over the phase, in degrees. `implement_inclination`: the mean angle of the implement's grip-to-tip segment above horizontal, in degrees. `phase_duration`: seconds.
- An invalid section is rejected with `SCHEMA_MISMATCH`, and `details.problems` lists every problem.

## Analysis Errors

| Situation | error_code |
|-----------|------------|
| Clip has no frames, or is too short to give each phase `min_phase_frames` frames | `PHASE_DETECTION_FAILED` |
| Detector did not return every pack phase | `PHASE_DETECTION_FAILED` (`details.missing_phases`) |
| Mean pose confidence below `min_pose_confidence` | `LOW_POSE_CONFIDENCE` |
| Invalid pack section, or the engine produced an invalid Metric Vector | `SCHEMA_MISMATCH` |

## Comparison Result

```json
{
  "result_id": "uuid",
  "clip_id": "uuid",
  "profile_id": "uuid",
  "profile_version": 1,
  "overall_score": 0.0,
  "score_meaning": "style_match",
  "ranked_deltas": [
    {
      "metric_key": "string",
      "user_value": 0.0,
      "coach_center": 0.0,
      "coach_spread": 0.0,
      "distance_spreads": 0.0,
      "contribution": 0.0,
      "phase": "string",
      "direction": "higher | lower | neutral"
    }
  ],
  "coverage": {
    "metrics_used": 0,
    "metrics_missing": [],
    "low_confidence_phases": []
  },
  "nearest_reference_clip_ids": [],
  "warnings": [],
  "applied_patches": ["slope_residual_v3"]
}
```

`overall_score` is a style-match score against the selected profile, not a universal quality score.

### Comparison rules

- **Preconditions.**
  - The profile's `pack_id` and `event_id` must match the Metric Vector's, and `metric_schema_version` must be equal. There is no migration step yet. Otherwise → `SCHEMA_MISMATCH`.
  - A profile whose quality gates did not pass → `PROFILE_NOT_READY`.
  - No profile metric present in the vector → `SCHEMA_MISMATCH`.
- **Per metric** present in both:
  - `distance_spreads = |user_value - coach_center| / coach_spread`.
  - `contribution = weight * (1 - exp(-d²/2)) / Σweight`. This is the share of the score lost to this metric, so `overall_score + Σcontribution = 1` over the metrics used.
  - `direction` is `neutral` when d < 0.5. Otherwise it is `higher` or `lower`, according to the sign of `user_value - coach_center`.
- **Ranking.** `ranked_deltas` are sorted by `contribution`, descending. Ties are broken by `metric_key`.
- **Overall score.** `overall_score` is the style-match score (Quality Gates) over the metrics used.
- **Coverage.**
  - `metrics_missing` lists profile metrics absent from the vector.
  - `low_confidence_phases` lists phases with confidence below 0.6.
- **Warnings.** These are plain sentences, issued for:
  - low-confidence phases
  - any metric used with confidence below 0.6
  - `pose_confidence_summary` below 0.6
  - missing metrics
  - rejected patches
  
  Low confidence never raises the score. It is always surfaced as a warning.
- **Nearest references.** `nearest_reference_clip_ids` holds up to 3 profile `reference_clips`, nearest first, by weighted RMS distance in spreads over the metrics used.
- **Patches.** `applied_patches` names each patch applied to the specialist heads for this analysis, such as `slope_residual_v3`.
- **Determinism.** The same Metric Vector, profile and patches always give the same result, apart from `result_id`.

## Specialist Patch (`specialist_patches/<head>_v<N>.patch`)

A sparse additive edit to one specialist head's weights. It is JSON despite the extension.

```json
{
  "head": "slope_residual",
  "version": 3,
  "base": "slope_residual/stub/v0",
  "edits": [
    { "tensor": "w1", "index": [4, 17], "delta": 0.012 },
    { "tensor": "b2", "index": [], "delta": -0.003 }
  ],
  "notes": "string"
}
```

- `tensor` is one of `w1 [32][64]`, `b1 [32]`, `w2 [32]` or `b2 []`. `index` must be in range for that shape.
- `base` must equal the head's base-weights id. A patch made for other base weights is rejected.
- Patches are cumulative: version N includes every earlier edit. Only the highest valid version per head is applied.
- A patch is rejected (`PATCH_REJECTED`, `details.problems`) if any of these hold:
  - the head is unknown
  - the base differs
  - an index is out of range
  - the patch has duplicate edits
  - a delta is not finite
  - it touches 2% or more of the head's weights (the DECISIONS.md bound)
  - the file name doesn't match `head`/`version`
  
  A rejected patch is never applied. Analysis and comparison continue without it, and the result carries a warning.

## Workspace Events (internal, for dual-video)

The dual-video workspace must support these operations as first-class:

- Load clip into stage A or B
- Independent scrub of A or B
- Set sync point (records offset between current A and B timestamps)
- Clear sync
- Play locked (both advance with offset)
- Play independent
- Set playback rate (including values < 1.0)
- Frame step (forward/back) on active or locked pair
- Mirror stage B
- Swap stages
- Annotate on active stage
- Red/green mark on selected attribute for current stroke

Sync state, annotations, and marks must be persistable inside a Project.

## Project

```json
{
  "project_id": "uuid",
  "name": "string",
  "clips": [],
  "sync_relationships": [
    {
      "clip_a_id": "uuid",
      "clip_b_id": "uuid",
      "offset_ms": 0,
      "created_at": "iso8601"
    }
  ],
  "annotations": [],
  "linked_profile_ids": [],
  "marks": [],
  "workspace": {
    "stage_a_clip_id": "uuid | null",
    "stage_b_clip_id": "uuid | null",
    "mirror_b": false,
    "playback_rate": 1.0,
    "locked": false
  }
}
```

### Project entries

`clips[]`: video files are referenced by local path only. They never leave the device.

```json
{
  "clip_id": "uuid",
  "path": "string (local file path)",
  "display_name": "string",
  "added_at": "iso8601",
  "athlete": { "quarter_turns": 0, "frame": 0, "x": 0.5, "y": 0.5 }
}
```

`athlete` (optional) says who to analyse when the user chose. It is absent when the choice is automatic.
- `quarter_turns`: clockwise quarter-turns that make the picture upright, applied after the file's own rotation metadata.
- `frame`: the sampled frame the person was chosen on.
- `x`, `y`: a point on that person, 0–1 of the turned picture.

The person chosen is the detected person whose box contains the point on that frame (the smallest such box, otherwise the nearest). Tracking is deterministic, so the same entry always selects the same person.

`sync_relationships[]`: `offset_ms = position_b_ms - position_a_ms` at the moment Set Sync Point is pressed. Locked playback keeps `position_b = position_a + offset_ms`. At most one relationship exists per (clip_a_id, clip_b_id) pair. Setting it again replaces the old one, and Clear Sync removes it.

`marks[]`: red/green per attribute on the current stroke. Until stroke segmentation exists (Phase 3+), a mark is anchored to the clip timestamp and `stroke_index` is null.

```json
{
  "mark_id": "uuid",
  "clip_id": "uuid",
  "time_ms": 0,
  "stroke_index": null,
  "attribute": "string (from the active pack's attribute list)",
  "label": "red | green",
  "author": "athlete | coach",
  "created_at": "iso8601"
}
```

`annotations[]`: a note on the active stage at its current position.

```json
{
  "annotation_id": "uuid",
  "clip_id": "uuid",
  "time_ms": 0,
  "text": "string",
  "created_at": "iso8601"
}
```

`workspace`: which clip is on each stage, plus view state, so a reopened project restores the same pair and its sync.

## Quality Gates (profile builder)

A profile may not be marked ready unless:

- `source_clip_count` >= pack-defined minimum (default target 15)
- Average pose confidence on critical phases meets threshold
- Self-consistency check passes: held-out clips from the same coach score above a defined match threshold against the profile built from the remaining clips

Failure of any gate produces a structured rejection, not a weak profile with a high score.

How the builder applies the gates:

- A clip is usable when analysis succeeds and its mean pose confidence over the critical phases is at least `min_critical_pose_confidence`.
- Too few usable clips → `INSUFFICIENT_CLIPS`. `details` lists the gates and each unusable clip with its reasons.
- The average critical-phase pose confidence across usable clips is below the threshold → `LOW_POSE_CONFIDENCE`.
- Self-consistency is leave-one-out. Each usable clip is scored against the profile fitted from the others. If the mean score is below `self_consistency_threshold` → `PROFILE_NOT_READY`, with `details.held_out_scores`.
- A previous profile for another pack or event, or one built under another `metric_schema_version` → `SCHEMA_MISMATCH`.

Style-match score: weighted mean over profile metrics of `exp(-d²/2)`, where `d = |value - center| / spread`. It ranges from 0 to 1.

## Error Contract

All analysis operations return either a success payload matching the schemas above or an error object:

```json
{
  "error_code": "INSUFFICIENT_CLIPS | LOW_POSE_CONFIDENCE | PHASE_DETECTION_FAILED | SCHEMA_MISMATCH | PROFILE_NOT_READY | PATCH_REJECTED | ADAPTER_COMPILE_FAILED",
  "message": "string",
  "details": {}
}
```

## Versioning Rules

- Metric schema changes require a new `metric_schema_version`.
- Profiles built under an old schema may not be scored against clips using a new schema without an explicit migration step.
- Profile versions are strictly increasing. Old versions remain readable.
- Specialist patches and adapters version independently inside the package.
