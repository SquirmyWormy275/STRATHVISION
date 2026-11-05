# Gurr footage: pose pipeline findings (Claude)

These are engineering findings from running the app's real pose pipeline (`apps/strathvision/lib/vision`, `packages/analysis_engine`) on the Gurr Academy export. They are not accuracy claims about coaching.

The contact-timing checks below use impact frames I read off the video myself. Codex's frozen references in [Gurr-Accuracy.md](Gurr-Accuracy.md) were not used for tuning.

Evaluation harness: `apps/strathvision/integration_test/gurr_eval_test.dart`. It runs the first 20 s of each clip, writes per-clip JSON with the pose track, and supports `TURNS` and `RATE`. Footage is never committed.

## What the footage is

- There are 48 videos.
  - Standing block: 43.
  - Underhand: 1 (a competition heat, IMG_3862).
  - Springboard: 4, with small, distant choppers.
- 45 of the 48 are iPhone HDR: HLG / Dolby Vision, BT.2020, 10-bit.
- 4 were filmed with the phone turned, so the person appears lying down even after the file's rotation tag is applied.
- Training clips: one framed athlete, often with a coach or onlooker in the shot.
- Competition clips: crowds, several choppers, netting, fences, posts and an arm across the lens.

## Fixed

| Problem found on the footage | Cause | Fix | Effect |
|---|---|---|---|
| Person found in 0–40 of 300 frames on competition clips | Whole-frame tracking; the landmark model needs a person crop | YOLOX-Nano detector, auto-pick, correction UI | Athlete followed in 237–300 of 300 frames on all 20 evaluated clips |
| Nobody detected on bright HDR scenes | Headless decoder returned HDR washed out (mean luma 215 vs 153) | Tone-map HDR (zscale + Hable) | IMG_3744: nothing → 5/8 usable; IMG_3869: nothing → found |
| Wrong person picked (onlooker at the frame edge; distant figure) | Activity alone rewarded pose jitter | Score = seen × size × centrality × not-cut-off × (0.5 + hand range) | IMG_0103 and IMG_3862 pick the chopper |
| A swinging chopper split into fragments | Linking by box overlap; the axe swing changes box shape | Link by height and nearness (same rule as following) | Fragments merged |
| Sideways clips | — | Per turn: detected people checked upright by the pose model | 17/17 test frames; IMG_3697, 0104, 3746 and 3692 turned automatically |
| Standing block contact ~0.1 s late | First lightly smoothed slow sample after impact | Midpoint between last fast and first slow raw sample | Error 2.8 → 0.8 frames (mean, 6 hand-read contacts) |
| A real contact missed | Speed peak leads contact by up to 0.45 s, beyond the 0.4 s window | Window 0.6 s | IMG_3748 contact at 572 found |
| Tracking at ~200 ms per sample | `frame-step` waited out each frame's display time | Step at 16× with no frame drops | 93–127 ms per sample, still deterministic |
| Detector at 104 ms | Output converted to nested Dart lists | Read the tensor buffer directly | 60 ms, same boxes |
| Pose model not loadable on x86_64 Android; Android CI red | Plugin ships ARM libraries only and pins compileSdk 33 | Official ORT 1.15.1 x86_64 library; plugin compiled against SDK 36 | real_pose_test passes on the emulator; release APK builds |

## Not fixed

- **Fast competition strokes.** Competition strokes come about every 0.9 s.
  - Many fail with "backswing too short": competition 14–21 of 55 strokes usable, training 58–61 of 80.
  - Frame-by-frame (IMG_3869): the swing is motion-blurred, so the pose model misreads the forearm for several samples in a row. The tip, projected 0.75 m along the forearm, jumps a metre between samples, and the turnaround before the swing lands mid-swing.
- **Tried, no clear gain (reverted):**
  - Smoothing radii in seconds instead of samples: worse at 30 Hz.
  - Backswing events read from the grip instead of the tip: 78 vs 82 of 135 usable.
  - A 3-sample median on the tip path: competition 24 of 67 vs 21 of 55, training 59 vs 61 of 80.
- **IMG_8014** (two choppers racing): the arms are smeared ghosts at this shutter speed, and nothing usable comes out.
- **Sampling every frame (30 Hz)** is not a clear win with the current engine.
  - IMG_3869: 2 → 4 usable. IMG_3711: 9 → 6.
  - An earlier run showed 2 → 10 on IMG_3869. That result could not be reproduced from its saved track with the current engine, so it is withdrawn.
- **Springboard:** choppers are now tracked, but the timber pack has no springboard event.

## Likely next steps

- **Filming guidance:** a faster shutter / higher frame rate for competition footage, and the camera side-on to the swing. Blur is the limit on competition clips, not tracking.
- **A trained implement (axe-head) detector,** to replace the forearm projection that magnifies blur. Codex has an axe benchmark in progress (Gurr-Round2).
- **Coach review** of the standing-block phase definitions (rise / reach / stop / release).
