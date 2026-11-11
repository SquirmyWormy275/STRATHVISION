# Local voice-note transcription

CARNE ASADA can turn a dropped voice note into text on the workbench computer. Transcription is optional and fully local. With no engine or model installed, voice notes stay `awaiting_transcription`, and review, profiles and the playground work as before. Nothing is uploaded.

## Pinned engine and model

| | |
|---|---|
| Engine | [whisper.cpp](https://github.com/ggml-org/whisper.cpp) `whisper-cli`, release **v1.9.5** (Arch Linux `extra/whisper-cpp 1.9.5-1`) |
| Engine license | MIT |
| Model | `ggml-base.en.bin` (OpenAI Whisper base, English-only, ggml format) |
| Model license | MIT (OpenAI Whisper weights) |
| Model size | 147,964,211 bytes (141 MiB). Matches the upload at `huggingface.co/ggerganov/whisper.cpp`. |
| Model SHA-256 | `a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002`. Computed from a local copy whose size matches the upload; Hugging Face's metadata API did not expose the hash. |
| Audio input | `.m4a .mp3 .wav .aac .ogg .flac`, converted to 16 kHz mono WAV with ffmpeg in a private temporary directory that is deleted afterwards |

The app refuses a model whose size or SHA-256 differs (`missingModel`), so results always come from the documented model.

## Install

1. Install the engine:
   - **Linux (Arch):** `sudo pacman -S whisper-cpp`. Other distributions: build v1.9.5 from source.
   - **macOS:** Homebrew `whisper-cpp`, or build v1.9.5 from source.
   - **Windows:** the v1.9.5 `whisper-bin-x64` release archive.
   - `ffmpeg` must also be on `PATH`.
2. Put `ggml-base.en.bin` (from `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin`) in `<application support>/transcription/`. On Linux that is `~/.local/share/com.strathvision.strathvision/transcription/`.
3. Overrides: `STRATHVISION_WHISPER_BIN` (engine path) and `STRATHVISION_WHISPER_MODEL` (model path).

The engine is found at playground start. Restart the playground after installing.

## Behaviour

- Each transcription is a subprocess with a 10-minute limit. **Cancel** in the playground status stops it, and the audio is kept.
- Transient failures (`failed`, `timedOut`) are retried once. After that the language binding is dropped and the audio kept (DECISIONS.md edge case). `missingModel`, `missingEngine`, `unsupportedAudio` and `cancelled` are not retried.
- A successful transcript is **held for review** and nothing is used or recorded yet. **Review** shows the editable text and segment timestamps. The reviewer must choose who is speaking (Coach or Athlete), then Accept or Discard.
- On Accept, the run record binds the reviewed text to: the audio's SHA-256, pack and event, segment timestamps, author, acceptance time, engine/model, whether the text was edited, and the clip that was current when the note was dropped. Only then is the text applied like a text note (`priority: <attribute>`, `ignore this clip`). Speech never changes geometry directly (DECISIONS.md: visual demonstration is ground truth).
- Discarded and pending transcripts never enter the experiment report. Audio files are never copied, moved or modified.

## Verification

- Fixture tests: `test/transcriber_test.dart` (conversion/parsing, missing or unpinned model, unreadable audio, missing tools, engine failure, timeout, real-subprocess cancel/timeout, detection) and `test/carne_test.dart` (review before use, binding, discard, retry-then-drop, no speech, review dialog).
- Real audio, opt-in: `LIVE_TRANSCRIBE=1 LIVE_AUDIO=<file> LIVE_EXPECT="<phrase>" LIVE_OUT=<json> flutter test test/live_transcription_test.dart`. Results are recorded in [VALIDATION.md](VALIDATION.md), with synthetic-voice and real-recording results kept separate.

## Limitations

The base English model is small and fast but makes mistakes, especially with background noise (saws, crowds), accents and sport-specific words. That is why every transcript needs explicit review. Other languages need a different model, which is not supported yet. Speed depends on CPU.
