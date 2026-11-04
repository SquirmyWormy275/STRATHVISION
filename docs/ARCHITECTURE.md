# STRATHVISION Architecture

See docs/DECISIONS.md for the full binding list. This file summarizes the runtime shape.

## Pipeline

Video → 3D full-body pose (root-relative) + implement track → phase and stroke segmentation → feature vector → profile density / manifold / importance weights → ranked deltas + counterfactual ghost (re-projected).

Specialist residual heads (e.g. slope_residual) sit on the feature vector and accept versioned patches from the workbench harness.

## Profile Structure

- Shared base layer: body model, general ranges, implement-class attachments, cross-event mobility.
- Per-event overlays: phase-conditioned mixture (μ, Σ), importance vector w, residual exemplars, reinforcement history, phase/segmenter state, specialist patches, compile-once adapters.
- Coaching packages are exportable overlays (athlete-derived or coach-authored) with stable IDs and versions.
- CARNE ASADA logs live in packages but are desktop-research only and never required for inference.

## Weight-Space Layers

1. Specialist net harness (workbench): sparse patches on tiny residual heads. Probes defined in DECISIONS.md.
2. Compile-once adapters: English specs in packs become local adapters inside packages.
3. CARNE ASADA (desktop only): recursive sparse edits to the mixture under hard bounds. See docs/CARNE_ASADA.md.

## Learning Loop

Clean frames and winning red/green/voice bindings produce discounted updates to mixture parameters and w. Inference always reads the current parameters. Light updates (w + exemplars) can apply on-phone immediately; full fits update μ/Σ. Specialist patches and adapters load with the package.

## Device Roles

- Phone (iOS/Android): full coach flows, inference, light updates, basic-to-advanced review, remote exchange. Loads patches and adapters. No weight editing, no CARNE ASADA.
- Laptop/desktop workbench: automatic ingest/fit/push, specialist harness, adapter compilation, full CARNE ASADA research loop, heavier merges, archive.

## Sync

Local/P2P profile packages only. No required cloud. Workbench mode is primary; manual transfer is secondary. Packages include patches and adapters.

## Gating

Usable-action thresholds (Good/Great/Excellent) control when implement-specific and weighted features activate. Below Good the app remains a capable dual-video reviewer.

All detailed rules, conflict handling, retention, recovery, edge cases, status messages, and CARNE ASADA constraints are in DECISIONS.md and CARNE_ASADA.md.
