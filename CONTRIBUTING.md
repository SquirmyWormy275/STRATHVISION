# Contributing

Read the [overview](README.md), [architecture](docs/ARCHITECTURE.md) and [current roadmap](docs/ROADMAP.md) first. Prefer a small change with a concrete failing example. Contract changes start in [INTERFACES](docs/INTERFACES.md) and [DECISIONS](docs/DECISIONS.md).

Use a pull request against `main`; keep `implementation` available for ongoing work. Run the relevant [validation commands](docs/VALIDATION.md) and state which devices were actually tested. CI builds are not physical-device acceptance. Keep private footage, credentials, per-person pose caches and unreviewed feedback out of Git. Use the licensed/generated fixtures or explicitly synthetic values in software tests.

Tests should reproduce a meaningful failure or acceptance criterion. Do not weaken gates or count copies as independent evidence to get a green run. Research contributions need frozen source provenance, an untouched session-disjoint holdout, and reports that retain misses, false positives and no-change controls.

For agent-assisted work, [AGENTS.md](AGENTS.md) documents scoped checkpoints. Status updates must never stage unrelated work; publishing comments is opt-in.
