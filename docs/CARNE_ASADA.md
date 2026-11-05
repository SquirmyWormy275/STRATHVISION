# CARNE ASADA

Desktop-only nested research project. Recursive weight-space editor for the phase-conditioned Gaussian mixture + residual exemplars.

**Not part of the normal app surface.** The athlete-facing product never depends on CARNE ASADA succeeding.

## Research Question (this subsystem)

Can a constrained, evidence-bounded weight-space loop improve a phase-conditioned style mixture from coach marks and per-stroke red/green feedback without full retraining or leaving the coach hull?

## Ingestion Playground

One folder + one window on the desktop workbench.

**Drop zone** labeled “Feed CARNE ASADA”. Accepts:
- Raw video clips
- Already-trimmed stroke segments
- Existing coaching packages
- Voice notes (or videos containing them)
- Simple text notes (“priority: slope”, “ignore this clip”)

Instant plain-language status (see DECISIONS.md for exact copy). Running tally of Good/Great/Excellent meters + accepted updates this session.

No YAML. No manual tagging required. Bad drops are ignored until baseline is met. “Use anyway” is one click. Undo is one click and local.

Optional “chaos” toggle (off by default) loosens the hull constraint for one session; auto-resets and warns.

## Loop (strict)

1. Diagnose largest residual on the current priority attribute from current mixture vs recent marks.
2. Propose one sparse update: shift μ, scale one covariance direction, adjust w, or add/remove one residual exemplar.
3. Evaluate only on the priority attribute + small held-out set of coach strokes.
4. Accept only if the attribute improves and the rest of the mixture stays inside the coach hull (or soft personal pull).
5. Log the delta as a new package version with the one-sentence explanation.

Max 5–10 accepted edits per session. Low-confidence or below-threshold clips ignored until baseline met.

## Package Objects

- `carne_asada/mixture_edits_vN.json` — research log + deltas (never required for inference).
- Full versioning + soft revoke already defined for packages.

## Input identity, stop states and experiment capture

- Identify video content by streaming SHA-256. Renamed/copy duplicates share one source ID and add usable footage only once per session. Display names remain presentation only; Ignore and Use anyway address source IDs.
- Serialize overlapping drops. A failed input is recorded and does not prevent the remaining batch from being processed. A failed analysis can be retried.
- Re-dropping existing content refreshes marks from the observed source paths without re-analyzing or duplicating strokes. Mark IDs are deduplicated and stroke time intervals are half-open. Pose caching uses the content ID for CARNE so replacing a file cannot reuse the previous content's pose.
- Show the current activity and the actual reason the loop stops: insufficient usable footage, waiting for feedback, no supported/improving proposal, hull rejection, or edit limit. Preserve all accepted/rejected/idle attempts in the experiment record.
- Save experiment exports a standalone `carne_asada_run/1` JSON record after any input attempt, including failures and zero accepted edits. It never creates a coaching-profile version. Save as vN+1 remains a separate action requiring accepted edits.
- Record source hashes/aliases, input outcomes, quality exclusions, settings, marks, overrides, loop outcomes and accepted edits. See [run record contract](CARNE_RUN_REPORT.md). Reported quality gates are not ground-truth accuracy or evidence of coaching improvement.

## Experiment Integration

Desktop competitor tracking uses the app's person detector and orientation handling. An uncertain competitor/orientation pauses the loop and offers the existing spatial picker in the feed. Before accepted edits, a correction reanalyzes that content, replaces its old measurements and preserves aliases without recounting footage. Marks on a previously analyzed competitor require a fresh review after correction. Choices are scoped to source content and recorded in the experiment; they are anonymous spatial selections, not named-athlete recognition.

CARNE uses a separate desktop pose budget (30 Hz, up to 90,000 samples) to retain swing timing on the longest downloaded Gurr recording. This differs from the normal interactive review budget. Per-stroke measurements can be replayed with genuine feedback through the [local review/evaluation workflow](FEEDBACK_REVIEW.md); the readiness, quality, source-separation and learning bounds still apply.

After working desktop build: upload all race and training footage of Matthew Gurr and Daniel Gurr. Run with priority = slope (then optionally others). Publish results in README (usable strokes, accepted edits, before/after residuals, exact explanations, hull compliance, raw logs).

## Non-Goals

- Running on phone.
- Unbounded edits.
- Replacing the specialist-net harness or compile-once adapters.
- Being required for any athlete-facing feature.
