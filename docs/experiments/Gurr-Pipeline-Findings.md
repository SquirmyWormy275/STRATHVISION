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

## Round 3 (2026-11-05): fast rhythm, springboard, filming tip

- **Fast competition rhythm.** 68 of 122 competition stroke failures were "backswing too short". Frame by frame, the cause was the stroke cut, not blur: with no pause between strokes the midpoint between contacts falls inside the next backswing, so the backswing landed in the previous stroke.
  - Fix: the cut moves back to where the stroke starts moving (at most 0.4 s; INTERFACES `stops`).
  - On the saved auto4 tracks (engine only): competition 21 → 34 of 55 usable, training 61 → 65 of 80; contacts unchanged on the hand-read frames. Two previously usable competition strokes became unusable.
  - Checked on video: IMG_3869 frames 212–235 (rise 214, reach 226 at the top, contact 233 vs about 231 by eye) and IMG_3867 frames 228–259 (reach 242 vs top about 245, contact 253 vs about 251). On IMG_3869 frames 52–86, a low looping swing, the reach is early (62 vs about 65) and contact about 4 frames late.
  - A run without the 0.4 s limit scored higher (42 of 55) but put strokes over earlier, weaker swings; rejected.
- **Springboard event** (`timber/springboard`): standing-block phases and metrics plus both knees at contact. Placeholder metric choice for coach review.
- **Springboard tracking.** On IMG_3925 the follower swapped to a judge when the chopper climbed past the pole at 38 s and never found him on the top board (the main chopping, 1:44 on, was missed; the judge's arm made a stroke).
  - Fix: the athlete must be of their usual size; the last box moves with the pose between detector checks; after 1 s lost, look above and below (DECISIONS "Following").
  - IMG_3925 (full 170 s): followed up the pole (40–60 s), back on the ground (64–90 s) and on the top board (111 s to the end): 50 strokes, 42 usable, about 22 of them top-block chops that were missed before. 103–107 s follows a helper carrying a board (one bad stroke).
  - **IMG_8010 is not usable automatically, before and after:** the auto-pick takes a distant figure at the far pole, and later the follower drifts to spectators near the camera (28 s, 90 s). Its stroke counts (27/21 before, 22/15 after) are not real chops. The user has to pick the athlete; the choppers are small and far.
  - Colour (torso hue histogram) did not separate athlete from judges on IMG_3925; not used.
- **Regression check of the new tracking + cut (auto5, 20 s per clip):** training 64 usable (auto4: 58), no clip worse (IMG_3744 5 → 8, IMG_3692 2 → 4, IMG_0105 4 → 5). Competition: IMG_3869 2 → 11 of 14, IMG_3867 1 → 4 of 11, IMG_3923 2 → 3 of 5, IMG_8014 0 → 4 of 9. Underhand IMG_3862 1 of 1.
  - IMG_8055 4 → 5 of 6, IMG_8067 2 → 3 of 4, IMG_7987 1 → 1 of 1, IMG_7985 2 → 5 of 8. All eight competition clips: 14 → 36 usable (55 → 58 strokes found); no clip worse. IMG_8014's strokes are not checked on video.
- **Filming tip:** shown when at least 3 strokes are found, under 60% measured, and the clip is under 50 fps. That 60 fps helps is not yet measured (no 60 fps footage).

## Not fixed

- **Fast competition strokes (partly fixed in round 3: the stroke cut).** Competition strokes come about every 0.9 s.
  - Before round 3 many failed with "backswing too short": competition 14–21 of 55 strokes usable, training 58–61 of 80.
  - Blur remains. Frame-by-frame (IMG_3869): the swing is motion-blurred, so the pose model misreads the forearm for several samples in a row. The tip, projected 0.75 m along the forearm, jumps a metre between samples, and the turnaround before the swing lands mid-swing.
- **Tried, no clear gain (reverted):**
  - Smoothing radii in seconds instead of samples: worse at 30 Hz.
  - Backswing events read from the grip instead of the tip: 78 vs 82 of 135 usable.
  - A 3-sample median on the tip path: competition 24 of 67 vs 21 of 55, training 59 vs 61 of 80.
- **IMG_8014** (two choppers racing): the arms are smeared ghosts at this shutter speed. 4 of 9 strokes are measured after round 3; not checked on video.
- **Sampling every frame (30 Hz)** is not a clear win with the current engine.
  - IMG_3869: 2 → 4 usable. IMG_3711: 9 → 6.
  - An earlier run showed 2 → 10 on IMG_3869. That result could not be reproduced from its saved track with the current engine, so it is withdrawn.
- **Springboard:** event added in round 3; IMG_8010 still needs the user to pick the athlete, and the other two springboard clips (IMG_3917, IMG_7993: many small, distant choppers) were not evaluated.

## Likely next steps

- **Filming guidance:** a faster shutter / higher frame rate for competition footage, and the camera side-on to the swing. Blur is the limit on competition clips, not tracking.
- **A trained implement (axe-head) detector,** to replace the forearm projection that magnifies blur. Codex's first two frozen prototypes failed (HOG 0/16, SSDLite 0/8 visible heads; Gurr-Round2), so this needs labelled training data first.
- **Coach review** of the standing-block phase definitions (rise / reach / stop / release).
