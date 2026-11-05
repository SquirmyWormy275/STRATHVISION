# Seagate footage: axe follow-up and weightlifting research

This study uses the private Seagate library to expand engineering supervision and evaluate implement localization. Raw video, frames, contact sheets and voice recordings stay private. The earlier [55-video experiment](New-Footage.md) and [47-video Gurr population run](Gurr-Population.md) remain unchanged.

## Protocol frozen before fitting

The library inventory hashes completed video files to EOF, probes media streams, records aliases and compares content hashes with both previous corpora. Downloader fragments, temporary merge outputs and archives are not counted as additional completed videos. A file changed during verification is deferred. This is a dated snapshot while another downloader may continue adding footage; it is not a full-duration decode claim.

The axe follow-up retains the previous 36/13/6 capture-day source split, 144 baseline training frames, 52 validation frames, and all original broad athlete regions. All 216 previously prepared training-only burst candidates are now visually reviewed. These add 49 visible-head boxes (including the 11 previously retained), yielding **73 positive training frames and three clear negatives**. Uncertain, obscured, blurred and out-of-frame candidates are recorded but excluded from fitting. All added positive boxes were checked in enlarged overlays before fitting. References remain coarse single-reviewer engineering labels, not independent expert measurements or judgments of technique.

The follow-up uses exactly the previous Faster R-CNN architecture, 1,000-step schedule, seed, COCO initialization, checkpoint selection and validation threshold procedure. The question is whether expanded training references improve the **same validation** localization score. This is an exploratory validation comparison after the first study's test was opened; the six old test sources are not a fresh holdout and will not be re-scored here. Training and validation image hashes, references and model metadata will accompany the result.

Weightlifting is a separate task and corpus. It will use source-grouped partitions fixed before fitting. Video titles are descriptive metadata, not coach judgments. Commentary has not been transcribed or bound to repetitions. Barbell localization must be evaluated separately from body pose, lift classification, bar-path accuracy and coaching quality; no production lifting capability is implied by a research fit.

## Reproduction entry points

- [`ingest_library.py`](../../tools/carne_asada/ingest_library.py): stable library snapshot, SHA-256 deduplication and download-component exclusions.
- [`axe_faster.py`](../../tools/carne_asada/axe_faster.py): unchanged source-guarded training and validation selection.
- [Expanded axe fit references](evaluation/seagate/axe/fit-reference.json) and [prepared-image hashes](evaluation/seagate/axe/fit-image-hashes.json).

## Expanded axe result

The real CUDA fit completed 1,000 steps; validation selected step 600 and score threshold 0.1577141136. The original validation references, pixels, architecture and training schedule were unchanged.

| Same validation set: 26 visible heads, 26 unrated frames | Correct | Incorrect boxes | Misses | Precision | Recall | F1 |
|---|---:|---:|---:|---:|---:|---:|
| Earlier 35-positive fit | 8 | 2 | 18 | 80.0% | 30.8% | 44.4% |
| Expanded 73-positive fit | 11 | 11 | 15 | 50.0% | 42.3% | 45.8% |

Expanded supervision increased recall while introducing many more incorrect boxes at the independently selected validation thresholds. The 1.4 percentage-point F1 increase is exploratory, not an independently tested improvement. Correlated neighboring frames do not equal new recording sessions. No old-test re-score or app promotion was performed. The conditional athlete ROI and lack of clear empty validation frames still limit the claim.

The [weights](evaluation/seagate/axe/axe-faster.pt), [training metadata and checkpoint history](evaluation/seagate/axe/axe-faster.json), [validation predictions](evaluation/seagate/axe/validation.json), and [fit log](evaluation/seagate/axe/fit.log) preserve the result. Weightlifting results and the final library audit are in progress.
