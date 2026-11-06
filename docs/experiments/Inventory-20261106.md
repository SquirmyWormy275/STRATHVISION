# Sport-agnostic inventory workstream — November 6, 2026

**The mounted Seagate inventory completed: 438 video files, 436 unique payloads, 17 h 21 min 40.2 s.** No source files were written. All 468 observed path signatures remained unchanged through the closing verification. This work adds reusable private manifests and reviewed provenance/split gates; it does not change production analysis or historical experiment results.

## What was actually accessible

The scanner verified the expected Seagate volume UUID on its existing `fuseblk` mount before reading `CARNE ASADA` and checked the same mount again afterward. It did not mount, repair or reconfigure the drive. The scan ran from **2026-11-06 08:14:47 to 08:26:43 UTC**. A further signature check at **08:27:33 UTC** used the final hardened directory traversal.

The drive was mounted read/write; the pipeline opened originals read-only and wrote its artifacts to the repository's ignored `research-data/` directory on the workstation. Read access can update filesystem access times. Size, modification/change times, inode, device and mode were unchanged; access time is deliberately excluded. This is evidence of this scan's preservation behavior, not a backup-integrity or disk-health claim.

| Observation | Result |
|---|---:|
| Observed leaf paths | 468 |
| Video files hashed to EOF and successfully probed | 438 |
| Unique video payloads | 436 |
| Exact duplicate aliases beyond unique sources | 2 |
| Unique video duration | 62,500.223842 s |
| Unique video bytes | 53,754,657,634 |
| Original archives preserved and excluded | 9 |
| Download intermediates preserved and excluded | 21 |
| Failed probes, changed sources, late arrivals or scan errors | 0 |
| Closing signatures unchanged | 468 / 468 |
| Previously published unique payloads still present | 424 / 424 |
| Newly inventoried payloads versus the published snapshot | 12 |

The six additional files beyond the previous report's 12 later video candidates are downloader intermediates. No archive was extracted, no source was copied or transcoded, and no video frames were sampled. All candidates were videos; standalone audio was supported by the tool but none qualified in this snapshot. Container probing does not validate full decoding, athlete selection, action quality, constant frame rate or session independence.

The [aggregate machine-readable record](evaluation/inventory-20261106-summary.json) binds the private inventory, exposure/provenance file and split plan by SHA-256. It contains no source filenames or local paths. The complete inventory ran the code recorded in commit `d420743`; the subsequent directory-race hardening and closing verification have their own code hash in that record. The real-media integration test exercises the final implementation.

## Provenance and split result

All 424 payloads from the [previous Seagate studies](Seagate-Footage.md) are conservatively recorded as **opened**. The 12 newly inventoried payloads retain **unknown** exposure; new to this manifest does not mean never inspected. No recording/session labels or coach judgments were invented.

There are **zero reviewed session sources** under the new contract. Consequently the validated initial plan contains **436 quarantined sources, zero train, zero validation and zero test sources**. The initial 436 grouping components reflect only known content/upload relationships; they are not evidence of 436 independent sessions. Reviewed multi-recording compilations, excerpts and re-encodes can merge components later.

The tool joins recording/session IDs, derivative parent hashes and upload hints transitively. Unknown provenance or a quarantine request contains the whole connected component. A fresh test component requires explicit unseen exposure. Supplying prior frozen plans preserves their assignments and identity relationships even across renamed/re-encoded inputs. No legacy holdout was relabeled or reused by this run. The original experiment-specific plans remain unchanged.

## Post-inventory representation assessment

The inventory establishes media availability and byte identity. It does not resolve reference measurements, independent sessions or genuine coaching feedback. The following assessment uses existing repository evidence; **no new representation benchmark or training run was performed**.

| Candidate | Existing evidence | Decision after inventory |
|---|---|---|
| Current pose + geometric phase/metric + grip-proxy baseline | Native software checks pass, but the [full-duration Gurr diagnostic](Gurr-Population.md) matched only 2/15 annotated contacts | Retain as an explicit comparison baseline; no accuracy promotion |
| Learned implement localization | The [Seagate axe follow-up](Seagate-Footage.md) traded increased recall for more false positives; the frozen barbell pilot matched 9/15 visible bars, with two false positives | Research-only, task-specific evidence; does not demonstrate a sport-agnostic movement representation |
| Learned movement representation or hybrid representation using pose plus learned features | No matched, session-disjoint benchmark against the current baseline exists in the inventoried evidence | Keep the stage interfaces sport-agnostic; freeze a common task, dataset, labels, metrics and compute budget before selecting a representation |
| CARNE ASADA bounded adaptation | [Existing population controls](Gurr-Population.md) and the [feedback workflow](../FEEDBACK_REVIEW.md) do not establish coaching improvement | Evaluate separately against no-update controls only after measurement accuracy, a ready source-disjoint profile, genuine feedback and an independent-session holdout exist |

A richer representation remains an allowed research direction, not an assumed improvement. The next evidence-producing step is to review source/session/derivative relationships and exposure, collect independent target labels with uncertainty, and freeze numeric acceptance criteria and the test-opening policy. All compared candidates must use the same eligible sessions and report coverage, abstentions, timing/localization errors and latency. CARNE ASADA additionally retains priority isolation, the coach hull, edit limits, zero-edit records and adverse-change checks.

## Reproduce and inspect

Follow the [dataset walkthrough and complete field contracts](../DATASETS.md). For this run, the local artifacts are:

- `research-data/inventory-20261106/inventory.json`: complete private inventory.
- `research-data/inventory-20261106-study/provenance.json`: unreviewed groups with conservative historical exposure.
- `research-data/inventory-20261106-study/split.json`: bound, quarantined plan.

To reproduce the conservative exposure step, copy the generated provenance template to a new private review file. For each SHA-256 present in the published `evaluation/seagate/library-inventory.json` `videos` list, set only `exposure` to `opened` and record that manifest's hash and the historical report as evidence. Leave `reviewed` false, recording/session IDs empty, and `requested_split` as `quarantine`. Leave all other exposure unknown. This is an explicit historical-evidence policy, not a sport classification or automatic judgment from filenames.

Then create a new plan with `splits.py plan` and verify it with `splits.py validate` against those exact inputs. The validation on the actual local artifacts returned `quarantine: 436`, with every fitting/evaluation partition empty. Use a new output directory for any repeat inventory and preserve these files.

## Verification

- **30 dataset tests passed locally**, including a generated real audiovisual clip, preservation checks, output containment, symlinks/FIFOs, directory-replacement races, per-file failures, mount changes, duplicate aliases, transitive leakage, prior-plan guards and command-line tamper rejection.
- **74 historical research tests and five handoff tests passed locally**. Relative documentation links and whitespace checks passed.
- [CI run 42187345385](https://github.com/SquirmyWormy275/STRATHVISION/actions/runs/42187345385) passed the research job (including the new suite) and engine/app test job on implementation commit `324dfb9`. Platform builds are separate acceptance checks; subsequent documentation/result commits receive their own CI runs.

No new model accuracy, coaching benefit, sports coverage or production readiness is claimed by these checks.
