# Optional local voice-note transcription

STRATHVISION's **Linux and Windows desktop apps** can use a separately installed **whisper.cpp** runtime to draft a transcript of a voice note. Audio is processed on the computer. The app does not download a model or send audio to a transcription service. A transcript must be reviewed before it becomes an accepted note; recognition is not a coach judgment or evidence that a movement was measured correctly.

The macOS app rejects this external-runtime configuration. Its sandbox requires a separate bundled, signed helper integration that has not been implemented or verified. The standalone macOS adapter test described below does not establish access from the packaged app. Ordinary review and retained audio remain available.

The initial input contract is **WAV, 16-bit PCM, 16 kHz, mono**, up to **10 minutes and 100 MiB (104,857,600 bytes)**. Other audio formats within the storage limit remain saved but cannot be transcribed by this integration. There is no recording interface or automatic media conversion. The multilingual model attempts language detection and transcription in the original language; accuracy for coaching terms, accents, background noise and languages other than the verification sample remains unvalidated. Phone builds do not run this desktop subprocess.

## Install explicitly

Prerequisites are Python 3.10 or newer, Git, CMake and a C/C++ toolchain. Linux needs a development compiler/toolchain; Windows needs Visual Studio Build Tools with the C++ desktop workload. Reproducing the standalone adapter check on macOS requires Xcode Command Line Tools; it does not enable the feature in the macOS app. Setup does not install these prerequisites or require administrator access itself.

From the repository root, choose a local destination with space for source, build outputs and the **147,951,465-byte model (about 141.1 MiB)**. Source/build sizes vary by platform and compiler; the observed Linux checkout and build occupied approximately 55 MiB and 18 MiB, in addition to the model and preinstalled toolchain:

```sh
python3 tools/transcription/setup.py --destination /absolute/path/to/strathvision-transcriber
```

On Windows, use `python` and a Windows path, for example:

```powershell
python tools/transcription/setup.py --destination "$env:LOCALAPPDATA/STRATHVISION/transcriber"
```

Only this explicit setup command downloads the pinned source and model. It builds the CPU command-line executable with static whisper/ggml libraries, disables GPU backends, RPC, libcurl and FFmpeg, verifies the model size/hash and checks the executable version. Operating-system C/C++ libraries can remain dynamically linked. The installation is for the machine on which it was built; copying its executable to another machine is not a verified deployment method.

Setup writes `transcriber.json` in the chosen destination and copies both MIT license notices into `licenses/`. The configuration contains absolute executable/model paths, their hashes and the source/model revisions. Keep the installation directory in place. Rerunning setup verifies an existing model rather than overwriting a mismatched file; a changed source checkout is rejected. Use a fresh destination for a different installation.

In desktop **CARNE ASADA**, open **Voice notes** and choose that configuration. A process can also provide its path through `STRATHVISION_TRANSCRIBER_CONFIG`. No global environment variable or app setting is changed by setup. The configuration is a local executable trust decision: select only the file produced by a setup you ran and trust. A binary hash identifies the configured executable; it is not a signature from a separate trusted publisher.

## Review before use

Add a voice note and request transcription. In **Review**, read and correct the draft, then explicitly choose the analyzed source clip and swing. The review shows its event and exact time range. Enter an author name, select **Coach** or **Athlete**, choose the attribute and a **red/green** judgment, then select **Use reviewed feedback**. The author/role are human-entered provenance, not verified professional credentials.

Confirmation saves the reviewed text and source/event/swing/time binding, then runs the existing bounded CARNE loop. Only the chosen red/green judgment supplies learning feedback; transcript wording does not issue commands or infer labels. Existing quality, footage, priority, hull and edit-limit gates still apply, so an accepted note may produce **no edit**. Installing the runtime or generating a draft alone does not run learning, approve a profile or publish a package.

Audio copies and JSON records are retained locally under the app's application-support `voice_notes` directory. Cancellation, unsupported audio, a missing model, timeout or transcription failure preserves the audio. Fix the setup/input and retry, or continue without a transcript. Those files survive a new session, but previous records/marks are not automatically loaded into it: re-add the preserved audio for a fresh review and current source binding. Recheck the selected athlete/source when analysis changes; old feedback must not silently attach to a different movement.

The [structured coaching-feedback review](FEEDBACK_REVIEW.md) remains the separate workflow for controlled research evaluation with reviewed stroke spans and independent fitting/evaluation sources. App voice-note acceptance does not establish coaching accuracy or satisfy that independent evidence requirement.

## Reproduce the real-audio check

The pinned upstream checkout includes `samples/jfk.wav`, an 11-second real historical speech recording. It is a native-runtime smoke test, not a coaching or multilingual benchmark. After setup, run the app adapter from `apps/strathvision`:

```sh
flutter pub get
STRATHVISION_TRANSCRIBER_CONFIG=/absolute/path/to/strathvision-transcriber/transcriber.json \
STRATHVISION_TRANSCRIPTION_AUDIO=/absolute/path/to/strathvision-transcriber/source/samples/jfk.wav \
STRATHVISION_TRANSCRIPTION_REPORT=/absolute/path/to/native-transcription-result.json \
dart run tool/transcription_check.dart
```

On PowerShell set the same three variables with `$env:NAME = 'path'`, then run `dart run tool/transcription_check.dart`. The report records hashes, actual recognized text/language, elapsed time and limitations. Acceptance requires the normalized phrase “ask not what your country can do for you”; it is not a full word-error-rate evaluation. The test invokes the same local adapter as the app, but does not exercise the desktop review UI. Synthetic subprocess tests remain separate.

The [targeted workflow](../.github/workflows/transcription.yml) runs setup, adapter/review regression tests and this real-audio check on Linux, macOS and Windows. It runs for relevant changes pushed to `implementation`, relevant pull requests and manual dispatch, retains compact JSON evidence, and performs no app publication or TestFlight actions. Platform success requires a completed passing run; compilation alone does not establish recognition or physical-device behavior.

On 2026-11-24 the [local Linux adapter check](../tools/transcription/verification/linux-20261124.json) passed: the 11-second sample produced the expected English phrase in 4.348 seconds, including adapter validation and processing. The transcript remained explicitly unreviewed. This is one observed run on this workstation; timings and accuracy are not promised for other hardware or speech. The setup integrity tests separately reject corrupt cached models, oversized downloads and hash mismatches without installing them.

| Target | Verification status |
|---|---|
| Linux desktop | App integration enabled. Native UI test passed with real speech, editable/persisted draft and acceptance disabled without source/swing; Ubuntu 24.04 adapter CI also passed, with 5.491 s elapsed time. [UI evidence](../tools/transcription/verification/linux-ui-20261124.json), [CI evidence](../tools/transcription/verification/ci-45480237008-linux.json) |
| macOS standalone adapter | Intel macOS 15.7.9 CPU setup and adapter passed, with 6.663 s elapsed time. **App integration unavailable** pending a verified bundled signed helper; Apple silicon is not covered. [CLI evidence](../tools/transcription/verification/ci-45480237008-macos.json) |
| Windows desktop | App integration enabled. Windows Server 2025 x64 runner CPU setup and adapter passed, with 5.312 s elapsed time; physical app UI remains unverified. [CI evidence](../tools/transcription/verification/ci-45480237008-windows.json) |
| iOS / Android | Desktop subprocess integration unavailable; no mobile transcription claim. |

All three jobs passed in [native run 45480237008](https://github.com/SquirmyWormy275/STRATHVISION/actions/runs/45480237008), source `aade34e22fd92594f7db4817c94770b5aa09a3f5`. They used the same pinned 11-second speech fixture and model; all recognized the expected phrase and preserved `reviewed: false`. These hosted runs verify native setup and adapter execution, not physical-device acceptance or multilingual/coaching accuracy.

The separate [native Linux review test](../apps/strathvision/integration_test/local_voice_review_test.dart) exercised real speech and the actual review dialog, persisted a text correction and kept acceptance disabled without an analyzed source/swing. It used a synthetic profile, no video inputs and no accepted feedback or mixture edits. The screenshot stays local; its hash and the observed result are in the compact UI evidence above. This is not a successful coaching-label or learning experiment.

## Pinned components and licenses

| Component | Pin | License |
|---|---|---|
| [whisper.cpp v1.9.6](https://github.com/ggml-org/whisper.cpp/releases/tag/v1.9.6) | `96ec4d9823e9d0211944172da35f9f29134af990` | [MIT](https://github.com/ggml-org/whisper.cpp/blob/96ec4d9823e9d0211944172da35f9f29134af990/LICENSE) |
| [Multilingual `ggml-base.bin`](https://huggingface.co/ggerganov/whisper.cpp/blob/5359861c739e955e79d9a303bcbc70fb988958b1/README.md) | Model revision `5359861c739e955e79d9a303bcbc70fb988958b1` | [OpenAI MIT model license](https://github.com/openai/whisper/blob/86098128c0b4f24f0e2aa2994de830614b474227/LICENSE) |

The model SHA-256 is `60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe`, verified against the pinned repository's [LFS pointer](https://huggingface.co/ggerganov/whisper.cpp/raw/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.bin). The speech fixture SHA-256 is `59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e`. Runtime and model pins were checked against primary upstream sources on 2026-11-24. Changes require updating the setup and app validation together, followed by fresh real-audio verification.
