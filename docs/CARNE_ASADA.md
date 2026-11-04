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

## Experiment Integration

After working desktop build: upload all race and training footage of Matthew Gurr and Daniel Gurr. Run with priority = slope (then optionally others). Publish results in README (usable strokes, accepted edits, before/after residuals, exact explanations, hull compliance, raw logs).

## Non-Goals

- Running on phone.
- Unbounded edits.
- Replacing the specialist-net harness or compile-once adapters.
- Being required for any athlete-facing feature.
