# Local-First Constraints

STRATHVISION treats local storage as the default and the source of truth for the core product.

## What stays local

- Video library
- Projects and sync relationships
- Annotations
- Profile packages
- Analysis results used for drift

## What may optionally leave the device

- Nothing in v1 is required to leave the device.
- Future optional compute (heavier pose models, batch reprocessing) may use a backend, but the contracts are written so the same profile and result schemas work whether the work happened locally or remotely.

## Transfer model

Laptop ↔ phone movement of profiles is an explicit export/import or local-network copy. There is no silent sync and no account requirement.

## Why this is an architectural choice rather than a missing feature

Many athletes and coaches are unwilling to upload large libraries of training video to a third-party service. A tool that works fully offline for review and scoring against personally built profiles has a clearer trust model and a smaller operational surface. The architecture documents this as a constraint so later implementation does not accidentally introduce a hard cloud dependency.
