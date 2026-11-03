# Design Decisions

## Video workstation before AI

The dual-video tools are specified and accepted before style-matching work begins. This prevents the common failure mode in which an analysis feature is built on top of a video experience that users will not tolerate.

## Explicit metrics before learned embeddings

The first comparison engine uses versioned, inspectable metrics and statistical profiles. This makes incorrect results diagnosable. A learned representation can be added later, but it must not be the only path to a score.

## Local-first with optional heavier compute

The core loop does not require accounts or cloud. Profile building is expected to happen on a laptop. This matches the data reality (athletes already have mentor footage) and the privacy preference. A backend can be added later for convenience; it is not required for the architecture to function.

## Pack-driven domain model

Hard-coding timber events into the engine would make the Olympic lifting pack a rewrite. Packs keep domain knowledge as data.

## Scores are style matches, not quality judgments

The system is explicit that it measures distance to a chosen technical signature. This avoids the false claim that the highest-scoring movement is universally best, and it makes the tool useful for athletes who are deliberately trying to adopt a specific coach’s style.
