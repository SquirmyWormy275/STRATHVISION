# Bundled models

## pose_landmark_full.onnx

MediaPipe BlazePose GHUM 3D pose landmark model ("full"), converted from the original `pose_landmark_full.tflite` to ONNX with tf2onnx (opset 13). The outputs match the original within 1e-3 on landmarks and 1e-4 on world landmarks.

- Source: https://storage.googleapis.com/mediapipe-assets/pose_landmark_full.tflite (Google MediaPipe)
- License: Apache License 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
- Copyright 2020–2026 The MediaPipe Authors

Inputs: `input_1` [1,256,256,3] float32 RGB in 0–1.
Outputs:
- `Identity` [1,195]: 39 landmarks × (x, y, z, visibility, presence) in input pixels.
- `Identity_1` [1,1]: pose presence.
- `Identity_4` [1,117]: 39 world landmarks × (x, y, z), metres, hip-centred.

## yolox_nano.onnx

YOLOX-Nano object detector (COCO, 80 classes), official ONNX export, used unmodified; only the person class is read.

- Source: https://github.com/Megvii-BaseDetection/YOLOX/releases/download/0.1.1rc0/yolox_nano.onnx
- SHA-256: c789161ed43c8269fcd4e67c67eeeb4e80c622da2eb296a20bc6007bd18a0b7d
- License: Apache License 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
- Copyright 2021 Megvii Inc.

Input: `images` [1,3,416,416] float32 BGR in 0–255, letterboxed (top-left aligned, padded with 114).
Output: `output` [1,3549,85]: per anchor point (strides 8, 16, 32) cx, cy, log w, log h (grid-relative), objectness, 80 class scores.
