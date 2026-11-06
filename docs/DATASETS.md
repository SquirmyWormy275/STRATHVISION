# Inventory footage before choosing a model

STRATHVISION's dataset tools answer three questions: what local media exists, which files contain identical bytes, and which recordings can safely share a research split. They do not assign sports, identify athletes, grade technique, infer coach judgments or train models. The production Flutter/Dart runtime and pack interfaces remain unchanged.

Start with an inventory, inspect its summary and failures, then review provenance before freezing a study. [Current Seagate results](experiments/Inventory-20261106.md) record the actual run and the limits on later representation comparisons. Historical [Seagate experiments](experiments/Seagate-Footage.md) retain their original manifests and results.

## 1. Run a private inventory

Requirements: Linux/POSIX, Python 3.10+, `ffprobe` and `findmnt`. There are no Python package dependencies. Run from the repository root. The source directory must already exist; the tool never mounts a drive. For Seagate, the explicit UUID check refuses an unmounted directory or a directory on another volume.

```sh
python3 tools/datasets/inventory.py \
  --root '/run/media/kingoftheeast/Seagate Portable Drive/CARNE ASADA' \
  --expected-volume-uuid 72A448AAA44872A1 \
  --output research-data/my-inventory
```

For another local corpus, supply its root and, optionally, its own expected volume UUID. The code contains no Seagate path or sport default. `research-data/` is ignored by Git. Private manifests contain filenames and local filesystem metadata; do not commit them. Only the generated `summary.json` is designed for public aggregate reporting, subject to review.

The output must be a **new directory outside the source tree**, including after resolving symlinked output parents. Existing directories are refused. Each run writes:

| Artifact | Meaning |
|---|---|
| `snapshot.json` | Initial paths, dispositions, signatures, scan errors, mount and tool versions |
| `progress.jsonl` | Completed per-file records retained if interrupted; not an eligible inventory |
| `inventory.json` | Final change checks, deduplicated source records and aggregate counts |
| `provenance-template.json` | Every source starts unreviewed, with unknown exposure and quarantine assignment |
| `summary.json` | Counts, timestamps and artifact/code hashes without source paths |

Successful exit is `0`. Exit `2` means refusal, failure or a partial inventory; inspect retained output and use a new directory after resolving the cause. There is deliberately no stat-only hash cache or automatic resume: a new run hashes every candidate to EOF. A missing/changed mount cannot produce a completed manifest. Empty accessible folders yield an empty inventory, not a claim that some other volume was available.

## 2. Understand identity and metadata

`footage-inventory/1` has `root`, `started_utc`, `completed_utc`, `mount`, `expected_volume_uuid`, `tool_sha256`, `python_version`, `ffprobe_version`, `complete`, `scan_errors`, `files`, `sources` and `summary`.

Every observed leaf path has a `path` relative to the root, a `disposition`, `state` and filesystem `signature` (`dev`, `ino`, `size`, `mtime_ns`, `ctime_ns`, `mode`). The scanner excludes symlinks, special files, nested filesystems, archives, downloader components and unsupported file types. Completed video and standalone audio formats are candidates. Archives are listed but neither hashed nor extracted. This inventories the accessible extracted footage, not archive contents.

A candidate is `verified` only after a streaming SHA-256, successful media probe, checks around reading and the final whole-tree signature comparison. Failures are `error` with a bounded diagnostic; mutations/deletions become `changed`; late arrivals become `arrived_after_snapshot`. Scan failures or any of these nonterminal-success states make `complete` false. Only verified records contribute to `sources`, one per SHA-256 with all path aliases and conservative `upload_hints` where a downloader-style filename contains an upload ID. Matching bytes count once even when renamed; different bytes never automatically prove different recordings.

Media contains container duration/bitrate and each audio/video stream's codec, stream duration, time base, pixel format/color tags, sample rate/channels, encoded dimensions, rotation metadata, display dimensions, exact nominal/average frame-rate strings and numerical average fps/frame count when available. Unknown numbers are JSON `null`. Creation-time tags are retained as unverified metadata, never converted automatically to session IDs. Container frame rates do not establish constant frame rate or action quality. Cover art is not counted as a video stream. A probe is not a full-duration decode or a validation of every frame.

Inputs are opened read-only, with symlink refusal on every path component; hashing and ffprobe use the same open inode. No copies, frames, sidecars or metadata writes are made in the source tree. Reading a writable filesystem may update access time; access time is excluded from preservation signatures. Final signatures detect ordinary concurrent changes, not adversarial restoration of file contents and metadata. SHA-256 is not a backup or a filesystem-health assessment.

## 3. Review provenance before a study

Copy `provenance-template.json` to a separately named private review file. `footage-provenance/1` has `sources`, keyed by **full SHA-256**, with these fields:

```json
{
  "reviewed": true,
  "reviewer": "reviewer or evidence curator",
  "evidence": "Verified session log and source recording reference",
  "recording_ids": ["recording-001"],
  "session_ids": ["session-001"],
  "parent_sha256": [],
  "exposure": "unseen",
  "requested_split": "train"
}
```

This is an illustrative row, not a claim about the user's footage. `reviewed: true` requires nonempty reviewer/evidence and recording/session IDs. Multiple IDs are supported for compilations spanning recordings or sessions. Re-encodes and excerpts share recording IDs; clips from one session share session IDs. Parent hashes connect derivatives transitively, and an absent parent quarantines that source. Include all relevant parents in the inventory before evaluating derivatives. Athlete independence is a separate study claim, not guaranteed by this schema.

`exposure` is `unknown`, `unseen` or `opened`. Hashing/probing headers alone does not open an evaluation target, but earlier sampling, annotation, model selection or diagnostic inspection does. Check historical experiment ledgers before attesting `unseen`. A filename, title, date tag or archive membership alone is insufficient proof of an independent recording session. Review attestations are evidence supplied to the guard, not facts the software can verify.

`requested_split` is `train`, `validation`, `test` or `quarantine`. A missing review or any quarantined member quarantines the entire connected component. Otherwise all connected sources must request the same split. A fresh test component requires explicit unseen exposure for every member. No percentages or random seed silently assign unknown sources to training.

## 4. Freeze and validate partitions

```sh
python3 tools/datasets/splits.py plan \
  --inventory research-data/my-inventory/inventory.json \
  --provenance research-data/reviewed-provenance.json \
  --output research-data/my-study

python3 tools/datasets/splits.py validate \
  --inventory research-data/my-inventory/inventory.json \
  --provenance research-data/reviewed-provenance.json \
  --plan research-data/my-study/split.json
```

Use the unreviewed template for a safe initial plan: all sources stay quarantined. No source video is read by the splitter. `footage-split/1` binds the exact input bytes by SHA-256, records the splitter code hash, and contains deterministic `groups`, per-source `exposure`, counts and limitations. Each group stores its identity tokens, source hashes, assignment and blockers. Shared SHA-256, recording IDs, session IDs, parent relationships and upload hints are joined **transitively**. Upload hints only add conservative grouping; they cannot establish independent sessions.

For every subsequent plan in the same study lineage, supply **all applicable frozen plans** with repeated `--prior-plan path/to/split.json`, and supply those same inputs when validating. Frozen non-quarantine assignments cannot move. Their group identities persist even when an old file disappears or a differently encoded file takes its place. New evidence joining formerly separate frozen partitions causes refusal; preserve the old result and redesign the study transparently. Previously recorded opened exposure cannot be changed to unseen. Quarantined groups can be released after genuine provenance review.

Validation recomputes the entire plan, including input/code hashes, rather than trusting its summary or a success flag. Even whitespace changes in inputs invalidate the binding. Keep exact copies of frozen inputs and code. Supplying fabricated review evidence or omitting prior plans is outside what this guard can detect. Existing `private-library/1`, `barbell-plan/1` and `new-footage-plan/1` artifacts are historical formats, not silently imported or reinterpreted. Review their references/exposure explicitly; their opened tests remain diagnostics.

## 5. Evaluate representations only after the dataset gates

A complete inventory is necessary but does not supply reference measurements or coaching labels. [The roadmap](ROADMAP.md) requires reviewed grouping, genuine labels and a frozen protocol before model comparison. Keep the existing geometric/pose/grip baseline, learned representations and hybrids behind the same sport-agnostic stage interfaces. Pre-register targets, numeric acceptance criteria, label uncertainty, compute/latency budgets and a test-opening policy; use identical eligible sessions and report failures and abstentions as well as accuracy.

After representation validation, evaluate CARNE ASADA separately against a no-update control with genuine coach feedback and a disjoint session holdout. Preserve hull limits, priority isolation, zero-edit cases and adverse changes. Neither a successful inventory nor an object detector score establishes coaching improvement.

## Test and extend

```sh
python3 -m unittest discover -s tools/datasets -v
```

Tests cover originals/output isolation, mount refusal, symlinks/special files, mutation and deletion, rational/HDR/rotation/audio metadata, corrupt/probe-timeout isolation, exact aliases, real generated audiovisual media, provenance, transitive leakage and frozen-plan enforcement. The real-media test requires `ffmpeg`; CI installs it. Historical research tools remain available under [tools/carne_asada](../tools/carne_asada/README.md).
