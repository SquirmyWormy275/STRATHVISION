# STRATHVISION Architecture

See docs/DECISIONS.md for the full binding list. This file summarizes the runtime shape.

## Pipeline

Video → 3D full-body pose (root-relative) + implement track → phase and stroke segmentation → feature vector → profile density / manifold / importance weights → ranked deltas + counterfactual ghost (re-projected).

## Profile Structure

- Shared base layer: body model, general ranges, implement-class attachments, cross-event mobility.
- Per-event overlays: phase-conditioned mixture (μ, Σ), importance vector w, residual exemplars, reinforcement history, phase/segmenter state.
- Coaching packages are exportable overlays (athlete-derived or coach-authored) with stable IDs and versions.

## Learning Loop

Clean frames and winning red/green/voice bindings produce discounted updates to mixture parameters and w. Inference always reads the current parameters. Light updates (w + exemplars) can apply on-phone immediately; full fits update μ/Σ.

## Device Roles

- Phone: full coach flows, inference, light updates, basic-to-advanced review, remote exchange.
- Laptop/desktop: automatic workbench ingest/fit/push, heavier merges, archive. Optional for athletes; not required for coaches.

## Sync

Local/P2P profile packages only. No required cloud. Workbench mode is primary; manual transfer is secondary.

## Gating

Usable-action thresholds (Good/Great/Excellent) control when implement-specific and weighted features activate. Below Good the app remains a capable dual-video reviewer.

All detailed rules, conflict handling, retention, recovery, and edge cases are in DECISIONS.md.
