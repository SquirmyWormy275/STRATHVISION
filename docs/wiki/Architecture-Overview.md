# Architecture Overview

STRATHVISION separates three concerns:

1. **Video workstation** — capture, library, dual-video review, annotation, projects.
2. **Analysis runtime** — pose → phase detection → metric extraction → comparison.
3. **Packs** — domain definitions (phases, metrics, weights, filming guidance) for specific sports or events.

The Flutter application is the shell for all platforms (iOS, Android, macOS, Windows, Linux). The analysis runtime exposes a strict interface. Packs are data.

## Device split

- Laptop/desktop builds profiles and performs heavier inspection.
- Phone captures, reviews, and scores against installed profile packages.
- Profile transfer is explicit and user-controlled.

## Why this split

Phone hardware and battery are poor places to run repeated high-quality pose estimation and profile fitting on large reference sets. The laptop is the natural place for that work. Once a profile exists as a small, versioned artifact, the phone only needs to run inference and comparison against it.

This also keeps the system local-first. No account is required to complete the core loop of “import mentor footage → build profile → score my clips.”

## Invariants

See [ARCHITECTURE.md](../ARCHITECTURE.md) for the full list. The most important for evaluation are:

- The dual-video workspace must be excellent even if analysis is unavailable.
- The engine contains no timber- or lifting-specific logic.
- Every score is accompanied by ranked, inspectable deltas.
- Quality gates can reject a profile; they cannot be bypassed to produce a confident number.
