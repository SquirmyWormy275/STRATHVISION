# Dual-Video Workspace

The dual-video workspace is the primary product surface.

## Required behaviors

- Load two clips into stages A and B.
- Scrub each timeline independently.
- Set a sync point that records the offset between the current frames.
- Play both locked together at the stored offset.
- Control playback rate, including slow-motion values.
- Frame-step the locked pair or the active stage.
- Mirror stage B without breaking sync.
- Persist the sync relationship and annotations inside a project.

## Why this is specified so tightly

Most coaching apps treat side-by-side video as a secondary feature. In practice, the ability to align two movements quickly and scrub them in lockstep is the daily tool. If this layer is weak, the style-matching scores are irrelevant because users will not stay in the app.

The interaction model is therefore treated as a contract (see INTERFACES.md) rather than an implementation detail. Acceptance criteria for this phase require that a user can align two clips and play them locked at slow speed in under 15 seconds, and that the relationship survives reopening the project.

## Design notes for implementation

- Video occupies the majority of the screen. Chrome is minimal.
- Sync state is always visible.
- Low pose/phase confidence on a clip is indicated before the user is encouraged to analyze it.
- The workspace remains fully functional when the analysis engine is disabled or fails.
