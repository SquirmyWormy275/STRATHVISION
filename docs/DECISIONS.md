# STRATHVISION Architectural Decisions

All decisions below are binding. Later implementation must conform.

## Core Engine

- Full-body 3D, root-relative, camera-agnostic pose before any metrics or manifold work.
- Implement track is required. Lightweight tracker supplies 3D point or short rigid segment in the same root-relative frame. Low-confidence implement frames drop implement dimensions, skip importance updates on them, and suppress dependent overlays/ghosts. Body-only comparison continues.
- Per-profile online-adapted rigid attachment for implements. Optional one-time photo/video seed for length, offset, and tracking prior. Class-level templates (axe, crosscut, chainsaw, hot saw, barbell, etc.) are required; per-instance refinement is optional. Untagged clips infer class; implement-specific updates only on match.
- Phase labeling is hybrid by default. Athlete/coach can switch between Automatic, Seeded, and Hybrid via dropdown. Corrections are soft bindings that gradually update the detector.
- Stroke boundaries detected from pack-supplied signals (implement-speed peaks + phase transitions). Manual drag/split/merge stored as soft corrections that can update the segmenter.
- Style manifold + counterfactual layer on top of phase-conditioned density. Sparse minimal-change ghost re-projected into the athlete’s camera.
- Shared base layer (body, general ranges, implement classes, cross-event mobility) + per-event overlays (density, importance weights, exemplars, reinforcement history).

## Continuous Learning (parameter updates, not context)

- Density is a phase-conditioned mixture. New clean frames perform discounted online updates to μ and Σ.
- Importance vector w is updated from feedback embeddings. Corrective language raises weights; dismissive language lowers them.
- Residual exemplars store (feature delta, feedback embedding, weight).
- Inference sorts by w-scaled deviation and solves weighted sparse counterfactual. Parameters actually change; behavior changes.
- Recency bias on all bindings. Visual demonstration is ground truth; speech/tags only re-weight or add exemplars.
- Attribute-priority hybrid: session priority isolates learning rate to chosen dimension(s). Green/red marks are per-stroke, per-attribute reinforcement. Coach mark overrides athlete mark; newest coach mark wins. Only the winning label updates parameters.
- Soft personal pull: athlete accepted swings can slightly shift the target inside the coach-supported region at reduced learning rate.
- Multi-coach footage tightens shared directions and leaves style differences as higher variance.

## Thresholds and Gating (timber defaults)

- Usable action = confident 3D pose + confident implement + assigned phase + actual stroke.
- Good: 2 min usable. Great: 6 min. Excellent: 15 min.
- Below Good: store everything, body tracking and basic dual-video tools work, suppress implement-specific ghosts, weighted rankings, and parameter updates. Persistent encouragement to add footage.
- At Good and above: advanced features unlock progressively.
- Explanatory coach speech during swings receives boosted binding weight.

## Coaching Packages and Remote

- Athlete-derived and coach-authored packages. Coach-authored built in this iteration: coach uploads own footage, runs reinforcement, exports.
- Package contains densities, w, exemplars, phase/segmenter state, implement-class templates. No raw video, no base layer.
- Stable IDs: coach:<name>:<event>:<origin>. Monotonic versions + content hash. Non-mutating. Import offers replace / keep / merge.
- Export choices: Coaching profile only (default), + my marks, or Full local overlay. Explicit summary before write. Contribution to shared/merged requires opt-in.
- Soft revoke: blocks new imports, flags existing copies, no remote deletion. Opt-in update notices only.
- Phone-first for all coach flows (create, reinforce, export, merge, revoke). Athletes may use laptop for heavier comparative work.
- Remote exchange paths (all produce identical bindings):
  1. One-time clip code / QR (primary)
  2. Shared local inbox folder (Syncthing etc.)
  3. Message-attachment round-trip
- Incoming coach marks: immediate light update (w + exemplars + re-rank + ghost) then queued for next full fit. Coach overrides athlete on same stroke+attribute.

## Sync, Tiers, Recovery

- Profile package is the fitted result (parameters, w, exemplars, bindings index, etc.). Raw video stays local.
- Primary: automatic workbench loop (laptop ingests, fits, pushes when phone reachable).
- Secondary: manual transfer when convenient (AirDrop, local network, P2P code).
- Opportunistic local Wi-Fi + one-time peer-to-peer. No required cloud.
- Phone base / laptop-trained package / desktop full. Phone never required to do heavy fit for personal use; coaches can do everything on phone.
- Single writer queue per overlay. Fits run on snapshot; mid-fit arrivals apply after.
- Automatic rollback (keep last two versions). Soft reset (parameters only). Full export-and-rebuild archive.
- Format versioning: newer readers accept older packages; older readers refuse or read-only.

## Edge Cases

- One phone + one laptop.
- Deleted source clips: invalidate tied marks/exemplars and rebuild without them.
- Extreme mismatch: auto-scale imported ranges to athlete mobility.
- Clock sync / logical timestamps for recency.
- Partial fit crash: previous version remains intact.
- Transcript failure: drop language binding after retry; keep audio. Robust local transcriber is priority.
- Single user per install.
- Design target 20–30 min sessions.

## UI/UX Principles (see also docs/UI_UX_PRINCIPLES.md)

- Backend may be arbitrarily complex. Frontend must be usable by someone reluctant to use a phone.
- Coach and athlete feel they are only coaching/reviewing the human. Blissfully unaware of the model.
- Progressive enhancement: footage alone → per-stroke red/green → voice → coach notes. Each layer independent. Model improves from clean footage alone.
- Instant obvious undo. Unmistakable current stroke/attribute. Aggressively good defaults. Physical-feeling control latency. Finished-looking empty/partial states. One primary action per screen. Spatial memory over menu paths.
- Aha standard: surface subtle unnamed patterns (spacing, opening/closing, etc.) cleanly so the user recognizes them. No invented coaching language.
