# Native libraries

## x86_64/libonnxruntime.so

ONNX Runtime 1.15.1 for Android x86_64, unmodified. The `onnxruntime` Flutter plugin (1.4.1) bundles the same release for arm64-v8a and armeabi-v7a only, so without this file the pose and person models cannot load on x86_64 devices (emulators, Chromebooks).

- Source: https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/1.15.1/onnxruntime-android-1.15.1.aar (`jni/x86_64/libonnxruntime.so`)
- AAR SHA-256: ff98a189aca2e731688d54f7876da49995484e855497d90cf9ffd3fe276d3c63
- License: MIT (https://github.com/microsoft/onnxruntime/blob/v1.15.1/LICENSE)
- Copyright (c) Microsoft Corporation
