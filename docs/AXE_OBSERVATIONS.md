# Research axe observations

This contract is separate from the engine's metric-space `ImplementTrack`. Single-camera image detections are not substituted for metre-valued 3D tip coordinates.

`axe-reference/1` contains source SHA-256, a train/validation/test partition, relative source name, window start/duration, event, orientation, an initial anonymous competitor point, visible axe-head boxes at reviewed times, optional grip points, contact intervals and explicit uncertainty. Boxes and points are normalized in the orientation-corrected image. A null box means the selected axe is not visibly localizable; it is not a negative claim about a hidden axe. Negative examples require a reviewed empty visible search region. Other axes can be ignored explicitly.

`axe-detection/1` records the source/window/time, image-space head box, raw classifier margin, model/configuration hashes and any spatial selection. Classifier margin is not a calibrated probability. Missing detections remain missing. Target continuity is limited to one shot; no appearance embeddings or named-identity matching are used.

`axe-model/1` records the feature geometry, linear coefficients/intercept, training source/annotation hashes, validation-selected threshold and code/dependency provenance. Test-source annotations cannot participate in fitting or threshold selection. The scorer uses one-to-one IoU matches and reports false positives/misses even when localization error on matched boxes is small.

`coach-feedback/1` keeps genuine author/reviewer provenance, source content, stroke span, attribute, red/green judgment and fit/evaluation partition. Draft review entries are unlabelled. No timing annotation, detector output or synthetic test fixture can create a genuine technique label. Empty/unreviewed feedback leaves learning evaluation pending.
