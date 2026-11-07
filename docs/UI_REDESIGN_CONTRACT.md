# Additive review-presentation contract

Authorized November 7, 2026. Existing Project JSON, feedback hashes, package exports, scoring and engine schemas retain their meanings. This record is local view state, not coaching evidence.

## Storage

Settings key `review.presentation.v1:<project_id>` holds an envelope with `lease`, `revision`, and `state`. State format:

```json
{
  "format": "review-presentation/1",
  "event": "pack/event",
  "schema": "metric-schema-version",
  "active_stage": "a",
  "attribute": "pack-defined attribute",
  "profile": "profile-id@version",
  "profile_chosen": true,
  "positions_ms": {"clip-id": 5860},
  "source_signatures": {"clip-id": "presentation-revision"},
  "viewed_at": "2026-11-07T00:00:00.000Z"
}
```

This is illustrative, not observed athlete data. Event/schema/attribute/profile/date can be null. A chosen null profile explicitly means measurements only. Positions are nonnegative. Missing records default to manual video review; unknown/corrupt records cannot be silently overwritten. No SQL schema migration is needed; older versions ignore these settings keys.

Transactions, monotonic revisions and route leases reject old-session writes. Resume checkpoints never rewrite Project JSON, marks, sync, annotations, edited dates or undo history. Domain writes stay ordered. Failures remain retryable; leaving after a failed save needs an explicit choice.

## Restoration

Saved event plus exact schema governs its review. The library preference applies only to new reviews. Legacy context is not guessed; select an event before new marks/analysis. Changing event does not relabel historical feedback. Restore exact profile ID/version; a missing version cannot silently become newest.

Timestamps work without segmentation or inference. Paused native seek targets must be checked against decoder-reported position before marking/saving. Restore linked playback from one clock and the original offset. A changed/unverifiable source does not inherit an old position.

Presentation signatures use resolved path, size, modification/change metadata: ordinary stale-view detection, not proof against adversarial content restoration. They NEVER replace source SHA-256 for coaching marks, research or exports. Thumbnails are derived private cache files, not originals or package content.

## Unchanged boundaries

No model promotion, invented labels, scoring changes, transcription, named-person recognition, fabricated overlays or cloud/account dependency. Device, signing and independent coaching-evidence gates remain open unless separately observed.
