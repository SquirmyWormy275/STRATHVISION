# Style Matching and Inspectable AI

STRATHVISION uses computer vision and structured comparison to answer a narrow question:

> How closely does this movement match the technical signature of a specific coach or mentor on this event?

It does not claim to measure universal “good technique.”

## Pipeline

1. Pose estimation produces keypoints over time.
2. Pack-defined phase detection segments the movement.
3. Pack-defined metrics are extracted (timing, geometry, coordination proxies).
4. The resulting metric vector is compared to a coach profile (distributions or prototypes with weights).
5. The comparison returns an overall style-match score and a ranked list of deltas.

## Why the AI is constrained

Unconstrained generative coaching ("here is how to fix your swing") is easy to demo and hard to trust. STRATHVISION limits the AI layer to:

- Measurement (pose, phases, metrics)
- Comparison against an explicit profile
- Ranking of measured differences

Any natural-language summary must be a direct translation of those measured deltas. The system is not permitted to invent cues that are not grounded in the metric results.

## Inspectability requirements

Every result must expose:

- The metrics that contributed most to the distance
- User value, coach center, and coach spread for each
- The phase in which the difference occurred
- Coverage and confidence warnings

A reviewer should be able to disagree with a score by pointing at a specific measurement. If that is not possible, the implementation has failed the contract.

## What is deliberately deferred

Learned style embeddings and end-to-end scoring models are out of scope for v1. They may be added later as an additional signal that runs alongside the explicit system, not as a replacement. The explicit path must remain available so results stay debuggable.
