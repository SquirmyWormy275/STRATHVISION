# Packs and Domain Modeling

A pack is the unit of domain knowledge.

It contains:

- Phase definitions and detection guidance
- Metric catalog (what is measured, units, version)
- Default weights for style matching
- Filming and quality heuristics
- UI labels

The analysis engine loads a pack and operates on the schemas it provides. It does not contain strings or logic specific to timber sports or Olympic lifting.

## Why packs exist

Underhand, single buck, standing block, snatch, and clean are not the same movement. Treating them as configuration rather than code prevents the engine from accumulating special cases and makes it possible to add a new domain without rewriting comparison logic.

## First packs

- Timber (underhand and standing block as initial events)
- Olympic lifting (to validate that the abstraction holds)

A new pack is successful when it can be added and used for profile building and comparison without changes to the core comparison engine.
