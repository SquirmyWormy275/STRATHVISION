# STRATHVISION Architectural Decisions

All decisions below are binding. Later implementation must conform. Do not invent alternatives.

## Core Engine

- Full-body 3D, root-relative, camera-agnostic pose before any metrics or manifold work.
- Implement track is required. Lightweight tracker supplies 3D point or short rigid segment in the same root-relative frame. Low-confidence implement frames drop implement dimensions, skip importance updates on them, and suppress dependent overlays/ghosts. Body-only comparison continues.
- Per-profile online-adapted rigid attachment for implements. Optional one-time photo/video seed for length, offset, and tracking prior. Class-level templates (axe, crosscut, chainsaw, hot saw, barbell, etc.) are required; per-instance refinement is optional. Untagged clips infer class; implement-specific updates only on match.
- Phase labeling is hybrid by default. Athlete/coach can switch between Automatic, Seeded, and Hybrid via dropdown. Corrections are soft bindings that gradually update the detector.
- Stroke boundaries detected from pack-supplied signals (implement-speed peaks + phase transitions). Manual drag/split/merge stored as soft corrections that can update the segmenter.
- Style manifold + counterfactual layer on top of phase-conditioned density. Sparse minimal-change ghost re-projected into the athlete’s camera.
- Shared base layer (body, general ranges, implement classes, cross-event mobility) + per-event overlays (density, importance weights, exemplars, reinforcement history).

## Weight-Space Programming Layers (first-class)

Three layers exist from day one. They are not optional extras.

### 1. Specialist Net Harness (always available on workbench)

- Target day-one net: `slope_residual`.
  - Tiny residual head (2-layer MLP, 64→32, <10k params) on top of base 3D pose + implement tracker.
  - Predicts entry-angle (slope) error relative to coach reference for the current phase.
- Probes (only feedback the harness sees):
  1. `slope_error_deg` — mean absolute slope error vs coach reference.
  2. `slope_bias` — signed mean error (primary target).
  3. `priority_agreement` — fraction of red/green marks on slope that match residual direction.
  4. `phase_stability` — slope variance inside phase (must not increase).
  5. `track_confidence_correlation` — correlation with implement-track confidence.
- Acceptance: slope_bias improves ≥0.8°, slope_error_deg does not regress, phase_stability and track_confidence_correlation within 5%, edit touches <2% of weights.
- Accepted patches stored as versioned residuals in the coaching package. Phone loads them; never edits.

### 2. Compile-Once Adapters

- Fuzzy decisions (usable-footage gates, attribute-priority scoring, event classification) expressed as short English specs in the pack.
- Workbench compiles once into tiny local adapters that ride inside the coaching package.
- Runtime is small on-device model + adapter. Zero ongoing LLM cost.
- Recompiled and pushed when pack or spec changes.

### 3. CARNE ASADA (desktop-only research)

- Recursive weight-space editor for the phase-conditioned Gaussian mixture + residual exemplars.
- Desktop workbench only. Nested research project. Athlete-facing product never depends on it.
- Hard constraints: max 5–10 accepted edits/session, priority-attribute only, stay inside coach hull or soft personal pull, ignore below-threshold clips, full versioning + soft revoke.
- Every accepted edit logged with one-sentence explanation.

See docs/CARNE_ASADA.md for full specification.

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
- Package contains densities, w, exemplars, phase/segmenter state, implement-class templates, specialist patches, compile-once adapters. No raw video, no base layer.
- Additional objects: `specialist_patches/`, `adapters/`, `carne_asada/` (research logs, desktop-only).
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

- Profile package is the fitted result (parameters, w, exemplars, bindings index, patches, adapters, etc.). Raw video stays local.
- Primary: automatic workbench loop (laptop ingests, fits, pushes when phone reachable).
- Secondary: manual transfer when convenient (AirDrop, local network, P2P code).
- Opportunistic local Wi-Fi + one-time peer-to-peer. No required cloud.
- Phone base / laptop-trained package / desktop full. Phone never required to do heavy fit for personal use; coaches can do everything on phone.
- Single writer queue per overlay. Fits run on snapshot; mid-fit arrivals apply after.
- Automatic rollback (keep last two versions). Soft reset (parameters only). Full export-and-rebuild archive.
- Format versioning: newer readers accept older packages; older readers refuse or read-only.

## Distribution

- Android: APK/AAB sideload for testing.
- iOS: ad-hoc provisioning (UDIDs, signed IPA + profile). 100-device cap.
- Desktop (Windows/macOS/Linux): zip of Flutter build.
- Packages are ordinary files.

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

## CARNE ASADA Ingestion (exact)

Drop zone accepts videos, packages, voice notes, text notes. Instant status:

- “Found 8 strokes. 5 are clean enough for slope. Adding them.”
- “Coach is talking through the swing. Pulling the spoken labels and binding them to the timeline.”
- “Implement drops out for 1.2 s. Clip saved, but it won’t move the model.”
- “You already have 7 minutes of good slope footage. This is pure gravy.”
- “Priority is slope. Only slope updates will be considered this session.”
- “This clip is below the usable threshold. Click ‘use anyway’ if you want it in the pile.”
- “CARNE ASADA accepted an update. Slope mean shifted 1.1° steeper on the downswing.”
- “No update. The proposed change would have left the coach hull.”
- “Session tally: 4 accepted edits. Undo is one click.”

One-sentence edit explanations (exact style):

- “Shifted slope mean 1.4° steeper on the downswing phase because 7 of your last 9 green marks agreed.”
- “Tightened slope variance in the entry phase after three consecutive red marks on the same stroke.”
- “Raised the weight of the residual exemplar from the 14-second mark of the Gurr clip; it matched the current priority better than the existing mean.”
- “Dropped one low-confidence exemplar that was pulling the mean flat.”
- “No geometric change. Only re-weighted existing coach strokes after the new voice note.”
