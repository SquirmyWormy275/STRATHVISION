# CARNE ASADA experiment record

`carne_asada_run/1` is a standalone JSON research export. It can describe an unchanged, failed, rejected or successful experiment. Export never creates a coaching-profile version, changes a profile, invents marks, or relaxes a learning gate. The existing `carne_asada/1` package edit log remains compatible.

The record includes:

- Session ID, start/export times, run revision, base profile ID/version and canonical-JSON SHA-256.
- Pack/event/schema IDs, phase/stroke settings, quality thresholds, session priority, edit limit and chaos setting.
- Every input attempt: local source path, kind, time, outcome, available content hash, duplicate source identity or error stage/message.
- Unique analyzed sources: SHA-256, stable clip ID, display name, observed path aliases, duration/fps, stroke and quality-pass counts, and rejection counts. Aliases are metadata; the source contributes strokes only once.
- Per-stroke source ID, span, quality issues, forced/ignored/counting flags and genuine bound marks. No per-frame pixels or pose coordinates are exported.
- Optional per-stroke `measurement` (the existing Metric Vector contract), `phase_pose_confidence`, and `implement_dropout_s` preserve the measured inputs for a separate feedback replay. A failed measurement is exported as an Error Contract, not a fabricated vector. Older reports without measurements remain readable but cannot replay learning.
- Current stop reason and message; all loop attempts, including rejected and idle outcomes; accepted edits and session hull from the existing edit-log contract; status feed and any saved profile path.

Input outcomes distinguish analyzed videos, duplicates, invalid/unreadable inputs, failed analysis, received notes, pending transcription, ignored packages and unsupported files. A duplicate can refresh marks but cannot create extra footage. A changed-content path uses a different source ID; old path-bound marks are not automatically treated as feedback on the replacement.

`awaiting_competitor` records ambiguous person/orientation selection before any strokes are added. Source `athlete` metadata records automatic/user selection, the spatial target, ambiguity/orientation flags and candidate count, without images or identity embeddings. Corrections before accepted edits replace the source's measurements, preserve aliases and invalidate old competitor-bound marks. Current stop reason `choose competitor` blocks learning until that selection is resolved.

A duplicate refreshes feedback from all observed aliases. Deleted marks disappear from the bound strokes; a failed feedback lookup discards that path's cached marks, records the error and permits a later retry.

The record captures actual runtime settings and model asset identifiers available to the controller. It does not claim a verified model/source-code checksum when one has not been supplied. Quality-pass counts and usable minutes describe the implementation's gates, not independently validated strokes or technique accuracy.

The controller tracks an export revision. Any new input, feedback refresh, setting change, override, loop attempt or undo makes a previous export an older snapshot. Export cancel/failure does not mark the run saved; successful export records its exact revision. Profile saving stays a separate, once-per-session action for accepted edits.
