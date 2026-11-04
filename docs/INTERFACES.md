# STRATHVISION Interfaces

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
  "marks": []
}
```

## Quality Gates (profile builder)

A profile may not be marked ready unless:

- `source_clip_count` >= pack-defined minimum (default target 15)
- Average pose confidence on critical phases meets threshold
- Self-consistency check passes: held-out clips from the same coach score above a defined match threshold against the profile built from the remaining clips

Failure of any gate produces a structured rejection, not a weak profile with a high score.

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
