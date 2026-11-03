# STRATHVISION

**Local-first athletic video analysis with inspectable style matching.**

STRATHVISION is a dual-video workstation and pack-driven analysis engine for technique sports. It is designed so the visual review tools are excellent on their own, and the AI layer is constrained, versioned, and fully inspectable.

This repository is structured to make architectural decisions visible. The contracts, failure modes, and quality gates are explicit so the system can be evaluated as engineering work, not as a black-box demo.

## What it is

- **Dual-video workspace** — independent scrub, set-sync-point, locked playback, mirror, variable speed, frame-accurate step. Usable without any analysis.
- **Private coach/mentor profiles** — built from an athlete’s own reference footage on a laptop, consumed on phone. No public marketplace, no required accounts.
- **Pack-driven style matching** — timber first, Olympic lifting second. The engine contains no domain-specific logic; packs supply phases, metrics, and weights.
- **Inspectable AI** — every match score produces ranked deltas with metric values, coach ranges, and phase context. Low confidence is surfaced, never hidden.

## Why the architecture looks like this

Most sports video tools are either consumer social products or opaque scoring black boxes. STRATHVISION is intentionally neither.

- Video is the product. The analysis engine is additive.
- Style match is not the same as “good technique.” The score is explicitly a distance to a chosen profile.
- Profiles are versioned artifacts with quality gates. A weak reference set cannot produce a confident score.
- The system is local-first. Heavy work happens on the laptop; the phone consumes finished packages. Cloud is optional and not required for the core loop.

These choices are documented in [ARCHITECTURE.md](docs/ARCHITECTURE.md) and enforced by the contracts in [INTERFACES.md](docs/INTERFACES.md).

## Repository map

| Document | Purpose |
|----------|---------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Boundaries, invariants, device roles, pack model |
| [docs/INTERFACES.md](docs/INTERFACES.md) | Exact schemas and contracts |
| [docs/EXECUTION_PLAN.md](docs/EXECUTION_PLAN.md) | Gated implementation plan |
| [docs/wiki/](docs/wiki/) | Longer-form explanations suitable for a GitHub wiki |

## Current status

Architecture and contracts are defined. Implementation has not started. The execution plan is written so that the dual-video workspace is completed and usable before any style-matching code is added.

## For reviewers

If you are evaluating this as a portfolio or engineering sample:

1. Read the invariants in ARCHITECTURE.md.
2. Check that INTERFACES.md defines failure modes and quality gates rather than only happy paths.
3. Note that the first implementation phase that produces a usable product is the dual-video workspace, not the AI layer.
4. The wiki pages under `docs/wiki/` expand on the design rationale for the visual AI and the local-first constraints.

## Non-goals (v1)

- Required accounts or cloud storage
- Public coach marketplace or social features
- Free-form generative coaching chat
- Generic multi-sport engine without packs
- Live multi-cam cloud streaming
