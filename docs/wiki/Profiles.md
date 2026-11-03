# Profiles and Quality Gates

A coach or mentor profile is a versioned artifact produced from reference clips.

It stores:

- Metric centers and spreads
- Weights
- Source clip count
- Quality-gate results
- Schema version

## Quality gates

A profile cannot be marked ready unless:

- It meets the minimum clip count for the pack
- Pose and phase confidence on critical sections meets threshold
- A self-consistency check passes (held-out clips from the same coach match the profile built from the remaining clips)

These gates exist so the system cannot emit a confident style-match score from inadequate or inconsistent reference data.

## Lifecycle

Profiles are built on the laptop, exported as packages, and imported on the phone. They are immutable once published; updates create a new version. Old versions remain readable so historical scores stay interpretable.

## Privacy posture

Profiles and the clips used to build them stay under user control. There is no requirement to upload them to a shared service.
