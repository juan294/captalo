# Research: Qwen3-TTS as the single speech engine

- Date: 2026-11-14
- Repository: `juan294/captalo`, branch `develop`, commit `5b1933fca50c25ea0fd5e55af294cb5b6d355133`
- Workflow: `rpi-research` (descriptive). No product code, configuration or dependency was changed. Measurements ran in the ignored, task-owned folder `.local/listening-test/`.
- Builds on: [clean-eyes re-evaluation](2026-11-14-clean-eyes-reevaluation-assessment.md) and [inherited baseline](2026-11-14-inherited-baseline-for-initial-plan.md).

## Research question

What exists today for using Qwen3-TTS as the only speech engine in Cáptalo, covering both built-in voices and a clone of the user's own voice, in place of Kokoro through FluidAudio? This report records the model family, licences, voices, cloning inputs, streaming and long-text behaviour, sizes, measured behaviour on this Mac, offline loading, and the Swift runtimes that load the model.

## How this question arose (session context, 2026-11-14)

- The owner wants an optional "read in my own voice" feature as a product differentiator.
- Local zero-shot clones from FluidAudio v0.18.3 (Pocket TTS, StyleTTS2, LuxTTS) were judged by the owner as not close enough.
- An ElevenLabs instant clone on `eleven_v4_turbo` was judged "amazing", but ElevenLabs documentation states clones cannot be exported and run only on its servers, and its terms restrict serving end users to plans from 299 USD per month. The owner then asked for a local alternative.
- Three open models were tested with a 14-second clip of the owner's voice: VoxCPM2, Qwen3-TTS 1.7B Base and LongCat-AudioDiT. The owner's verdict: "clone-qwen3.wav is the best one, I'd be happy to use this one". That sample came from `mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16`.
- The owner then asked to research using Qwen3-TTS for everything.

## Summary

Qwen3-TTS (Alibaba Qwen, released January 2026, Apache-2.0 for code and weights) is a family of separate models, not one model. Voice cloning exists only in the "Base" models. Ready-made voices exist only in the "CustomVoice" models, which ship nine speakers of which two are English-native and both are male (Ryan, Aiden). A third model, "VoiceDesign" (1.7B only), creates a voice from a text description. One engine therefore still means at least two model files if both cloning and preset voices are wanted.

On this Mac (Apple M5 Ultra, 96 GB) every tested configuration loaded in about 1.3 to 2 seconds from disk, produced the first audio 0.06 to 0.24 seconds after a warm request, generated speech 4.4 to 6 times faster than real time, and loaded with the network disabled. Peak memory was 2.3 to 6.2 GB depending on the variant. Smallest files on disk are 1.7 GB per model.

The cloned-voice runs read the one-minute test passage in 63 to 68 seconds of audio. The preset-voice runs, given the same passage in a single request, produced 73 to 179 seconds of audio, with up to 50 seconds of silences longer than one second. Upstream issues describe swallowed words, accelerating speech, looping and voice drift on long inputs. The model has no text normalizer.

Three Swift routes load the model on Apple Silicon through MLX: `mlx-audio-swift` (MIT), `speech-swift` (Apache-2.0) and the engine package inside the Vocello app (MIT). FluidAudio does not support Qwen3-TTS. MLX needs a Metal shader library that the SwiftPM command line cannot build; Xcode or `xcodebuild` can.

## Evidence labels

- **Measured**: run on this Mac in this session; raw outputs are in `.local/listening-test/mlx/` (`bench.jsonl`, `bench/*.wav`, `status*.txt`).
- **Local**: read from files installed on this Mac.
- **Web**: page or file opened on 2026-11-14 by a delegated read-only investigator; URLs under Sources.
- **Inferred**: not directly observed.

## 1. Model family

Web, from `github.com/QwenLM/Qwen3-TTS` (last push 2026-03-17) and Hugging Face `Qwen/*` cards (created 2026-01-21):

| Model | What it does | Original size |
|---|---|---|
| `Qwen3-TTS-12Hz-1.7B-Base`, `-0.6B-Base` | Voice cloning from reference audio; no preset speakers | 4.54 GB, 2.52 GB |
| `Qwen3-TTS-12Hz-1.7B-CustomVoice` | Nine preset speakers plus style instructions | 4.52 GB |
| `Qwen3-TTS-12Hz-0.6B-CustomVoice` | Nine preset speakers, no style instructions | not measured |
| `Qwen3-TTS-12Hz-1.7B-VoiceDesign` | Voice from a text description; no 0.6B variant | not measured |
| `Qwen3-TTS-Tokenizer-12Hz` | Audio codec, 12.5 frames per second, 24 kHz | part of each model |

- Licence: Apache-2.0 for code and weights. No NOTICE file, and no consent or misuse clause in the README or Base card (Web).
- No newer Qwen TTS release was found under `Qwen/` on Hugging Face (Web; absence of evidence only).
- Languages: Chinese, English, Japanese, Korean, German, French, Russian, Portuguese, Spanish, Italian (Web).
- Preset speakers: Vivian, Serena, Uncle_Fu, Dylan, Eric (Chinese); Ryan, Aiden (English, male); Ono_Anna (Japanese); Sohee (Korean) (Web). The same nine names were returned by the loaded CustomVoice models here (Measured: `supported_speakers` in `bench.jsonl`). There is no English-native female preset.
- The Base models returned an empty speaker list (Measured), matching the runtime README: "voice cloning via `ref_audio`/`ref_text`; no preset speakers" (Local, `.local/listening-test/mlx/.venv/lib/python3.12/site-packages/mlx_audio/tts/models/qwen3_tts/README.md`).
- Cloning inputs: reference audio plus its exact transcript; an "x-vector only" mode needs no transcript, with the upstream note that "cloning quality may be reduced"; a reusable clone prompt object exists upstream (Web). The Python runtime requires 24 kHz reference audio for the speaker embedding (Local, `qwen3_tts.py:328`).
- Text handling: no text normalizer was found in the upstream inference code (Web). The runtime README states that generation "prefills the complete input text before producing audio tokens" and that streaming emits chunks after that prefill (Local, same README).
- Limits: upstream `max_new_tokens` is 8192; no documented input-length limit or chunking guidance (Web).
- Upstream issue reports (Web, all closed, several by an inactivity bot): last words swallowed on a 300-word text (#181); speaking rate accelerates on long text (#239); distortion and looping, described by a commenter as near-certain past five minutes (#258); speaker sometimes changes (#80); a clone keeps the source-language accent (#134).

## 2. MLX conversions and sizes

Web (Hugging Face API) unless marked:

| Variant | bf16 | 8-bit | 6-bit | 4-bit |
|---|---|---|---|---|
| 0.6B Base | 2.52 GB | 1.99 GB | 1.85 GB | 1.71 GB |
| 1.7B Base | 4.54 GB | 3.10 GB | 2.72 GB | 2.34 GB |
| 0.6B CustomVoice | not queried | 1.97 GB | not queried | 1.69 GB |
| 1.7B CustomVoice | 4.52 GB | 3.08 GB | not queried | 2.31 GB |

- 4-bit and 8-bit sizes for the CustomVoice and 0.6B Base rows were also read from the Hugging Face API in this session (Measured query).
- The audio codec part stays 682 MB unquantized in every variant (Web), which is why the smallest file is still 1.7 GB.
- Third-party statements on quantization quality (Web, not reproduced): the `speech-swift` documentation calls 4-bit "decommissioned for TTS quality" and says 1.7B 4-bit "degraded badly (silent or garbled output)" in its own conversion; its benchmark page lists word error rates of 15.58% (0.6B 4-bit), 9.74% (0.6B 8-bit), 3.47% (1.7B 4-bit) and 3.66% (1.7B 8-bit). The 4-bit runs measured here produced complete, non-silent audio (section 3).

For comparison, the Kokoro v1.0 files measured earlier are 92 MB including five voices (clean-eyes assessment, "Listening test samples").

## 3. Measurements on this Mac

Setup (Measured): Apple M5 Ultra, 96 GB memory, macOS 27.2.1; Python 3.12 virtual environment with `mlx-audio` 0.6.5; models from `mlx-community`; one process per configuration; each process loaded the model once, ran a short warm-up, one sentence, then the full 190-word passage as a single streaming request (`streaming_interval=0.32`). Clone runs used a 14-second, 24 kHz clip of the owner's voice with its transcript. "First audio" is the time from the request to the first audio chunk.

| Configuration | Load from disk | First audio (sentence / passage) | Passage: generation time | Passage: audio produced | Speed vs real time | Peak memory |
|---|---|---|---|---|---|---|
| 1.7B Base bf16, clone | 2.0 s | 0.24 s / 0.19 s | 14.4 s | 63.3 s | 4.4x | 6.2 GB |
| 1.7B Base 4-bit, clone | 1.3 s | 0.13 s / 0.13 s | 11.5 s | 66.3 s | 5.8x | 4.0 GB |
| 0.6B Base 4-bit, clone | 1.3 s | 0.13 s / 0.13 s | 12.2 s | 67.5 s | 5.5x | 3.3 GB |
| 0.6B CustomVoice 4-bit, Ryan | 51.3 s (included download) | 0.06 s / 0.07 s | 19.2 s | 113.0 s | 5.9x | 2.5 GB |
| 0.6B CustomVoice 4-bit, Aiden | 1.4 s | 0.06 s / 0.07 s | 31.1 s | 178.6 s | 5.8x | 2.5 GB |
| 1.7B CustomVoice 4-bit, Ryan | 77.1 s (included download) | 0.08 s / 0.09 s | 22.2 s | 115.0 s | 5.2x | 3.1 GB |
| 1.7B CustomVoice 4-bit, Aiden | 1.3 s | 0.07 s / 0.09 s | 12.7 s | 73.2 s | 5.8x | 3.0 GB |

Observations (Measured):

- First-request latency in a fresh process (the warm-up row) was 0.10 to 0.61 s after the model was loaded.
- Audio length for the same passage varied widely in the preset runs: 73 s to 179 s, against 63 to 68 s for the clone runs and 62 to 72 s for the Kokoro, Phonon and Pocket TTS samples recorded earlier.
- Silences longer than one second, detected with `ffmpeg silencedetect` at -45 dB: 0.6B Aiden 50.6 s across 28 gaps; 1.7B Ryan 17.3 s across 13 gaps; 0.6B Ryan 1.0 s in one gap; 1.7B Aiden none; 0.6B Base clone none. The 0.6B Ryan run produced 113 s of audio with almost no long silence; the cause of its extra length was not analysed.
- Whether words were skipped, repeated or mispronounced in any run was not checked; no transcript comparison was made.
- An earlier non-streaming command-line run of the 0.6B Base 4-bit clone took 35 s wall-clock including process start and model load, against 16 s for 1.7B 4-bit and 20 s for 1.7B bf16 (`status3.txt`). The streaming benchmark above did not show that difference.
- Offline loading: with `HF_HUB_OFFLINE=1` and `TRANSFORMERS_OFFLINE=1`, the cached 0.6B Base 4-bit model loaded in 1.1 s and generated audio. Network traffic was not monitored.

Limits of these measurements: this Mac is far above typical hardware, so the speed and latency figures do not describe an ordinary MacBook. They were taken through the Python MLX runtime, not through a Swift runtime. No ten-minute passage was generated.

Figures published by others for other Macs (Web, not reproduced):

| Source | Chip | Model | Result |
|---|---|---|---|
| `mlx-audio-swift` issue #224 (2026-07) | M4 Pro 48 GB | 1.7B bf16; 0.6B 8-bit, clone | 6.2 and 8.4 tokens per second, where real time is 12.5; peak 6.2 and 4.6 GB |
| `mlx-audio-swift` PR #315 (2026-10-26) | M2 Pro | 1.7B 8-bit, clone | 11.7 to 25.3 tokens per second |
| soniqo.audio benchmarks | M5 Pro 48 GB | 0.6B and 1.7B, 4-bit and 8-bit | generation takes 0.76 to 0.85 of the audio length |
| `speech-swift` docs | M2 Max | unspecified | 0.55 to 0.7 of the audio length; first chunk about 225 ms |
| Vocello README | Mac mini M6 16 GB; Mac mini M2 8 GB | 1.7B 4-bit | 0.26 to 0.32; 0.53 to 0.82 of the audio length; peak about 3 GB with streaming |

No figures for M1 or M3 Macs were found (Web).

## 4. Owner listening verdicts so far

- `clone-qwen3.wav` (1.7B Base bf16): accepted by the owner as the best local clone.
- `clone-qwen3-1.7B-4bit.wav` (2.34 GB model, whole passage in one request): owner verdict "the voice sounds really good", but the delivery ran on "like a train", without pauses at full stops and commas.
- `clone-qwen3-1.7B-4bit-paced.wav` (same model; each sentence generated separately, 0.30 s of silence added after each sentence and a further 0.35 s after each paragraph; 12.7 s to generate 63.9 s of audio): owner verdict "good".
- `clone-qwen3-0.6B-4bit.wav` (1.71 GB model): owner verdict "terrible".
- Preset samples copied to `.local/listening-test/samples/`: `qwen3-preset-ryan-0.6B.wav`, `qwen3-preset-aiden-0.6B.wav`, `qwen3-preset-ryan-1.7B.wav`, `qwen3-preset-aiden-1.7B.wav`. These are the single-request runs with the length anomalies described above.
  - `qwen3-preset-ryan-1.7B.wav` (the run with 17.3 s of long silences): owner verdict "horrible".
  - `qwen3-preset-aiden-1.7B.wav` (the run with no long silences): owner verdict "better, not the greatest".
  - The two 0.6B preset files were not judged; the owner rejected the 0.6B model size on the clone.
- For reference, the owner earlier judged all Kokoro, Phonon and Pocket TTS preset samples "very acceptable".
- The reference clip is conversational speech, not reading aloud; the transcript was produced locally with FluidAudio's speech recognition.

## 5. Swift runtimes that load Qwen3-TTS

All Web unless marked. None was built or run in this session.

| | `mlx-audio-swift` | `speech-swift` | Vocello engine (`VocelloQwen3Core`) |
|---|---|---|---|
| Repository | `Blaizzy/mlx-audio-swift` (redirects to `Neywa-Labs`) | `soniqo/speech-swift` | `PowerBeef/QwenVoice` |
| Version, date | v0.1.9, 2026-11-09 | v0.0.29, 2026-10-25 | app v3.0.0, 2026-10-24 |
| Licence | MIT | Apache-2.0 | MIT |
| Minimum | macOS 14, Swift tools 6.2 | macOS 15, Swift tools 5.10, Xcode 16 with Metal toolchain | macOS 26 |
| Loading from a local folder | `Qwen3TTSModel.fromModelDirectory(_:)` | `fromLocal(modelDirectory:)`; `fromPretrained(... offlineMode:)` | models downloaded once by the app, never bundled |
| Preset voice | `generate(text:voice:...)` with the speaker name | `synthesize(text:language:speaker:instruct:)` | supported in the app |
| Clone | `generate(... refAudio:refText:...)`; `prepareReferenceConditioning` returns a reusable object | `synthesizeWithVoiceClone` (no transcript) and `synthesizeWithVoiceCloneICL` (with transcript); in-memory cache | supported in the app |
| Streaming | `generateStream(... streamingInterval:)`, incremental | `synthesizeStream`, first chunk after 3 frames | streaming, segments long scripts with a planner |
| Long text | no chunker or text normalizer in the Qwen3 code | `TextChunker.chunk(_:maxWords: 35)` | `LongFormPlanning.swift` splits, plays in sequence, joins |
| Models it uses | `mlx-community/*` | its own conversions under `aufklarer/*`; also a CoreML 1.7B path of about 7.1 GB, described as not validated for GPU or Neural Engine placement | its own "hybrid-attn" conversions under `PowerBeef02/*`, 4-bit and 8-bit |
| Notes | open issue #224 "not real-time on M4 Pro"; v0.1.9 lists three Qwen3 streaming fixes | large dependency graph (WhisperKit, hummingbird and others); whether the loading functions are `public` was not confirmed | fork of `mlx-audio-swift` v0.1.2 narrowed to Qwen3-TTS; README says it is not the upstream SDK; embeds an AudioSeal watermark in output |

Other routes found (Web): `predict-woo/qwen3-tts.cpp` (GGUF, Metal), `HaujetZhao/Qwen3-TTS-GGUF` (llama.cpp for the language-model part), `gabriele-mastrapasqua/qwen3-tts` (C with BLAS). FluidAudio's README lists no Qwen3-TTS support. `sherpa-onnx` has open requests only.

## 6. MLX inside a shipped Mac app

- `mlx-swift` 0.33.0 (2026-10-27), MIT, macOS 14+ (Web).
- Its README states: "SwiftPM (command line) cannot build the Metal shaders so the ultimate build has to be done via Xcode"; `xcodebuild` works. A missing shader library fails at run time with `Failed to load the default metallib` (Web, `speech-swift` README, which ships a build script for it).
- Open packaging issues in `mlx-swift` (Web): #345 signed and notarized bundling of `default.metallib`; #415 no API to override the shader library path; #349, #460, #500.
- Vocello ships notarized with Hardened Runtime and Developer ID, using the entitlements `allow-unsigned-executable-memory` and `disable-library-validation`, with the sandbox off (Web). Whether MLX requires those entitlements is not established.
- macOS 27 reports in `mlx-swift` (Web): #504 a Metal validation assertion on `Memory.cacheLimit`, reproduced on macOS 27.2 with the debug layer only; #492 a precision problem on M5; #485 a hang before `main()` on a device.
- The Python MLX runtime ran every configuration here on macOS 27.2.1 without a crash (Measured). That does not cover the Swift runtime.

## 7. Comparison with the recorded Kokoro baseline

Facts side by side; no evaluation.

| Aspect | Kokoro v1.0 via FluidAudio v0.18.3 | Qwen3-TTS via MLX |
|---|---|---|
| Files on disk | 92 MB with five voices (Measured earlier) | 1.7 GB minimum per model; cloning and preset voices are separate models (Web, Measured) |
| English preset voices | 28, both sexes (Web) | 2, both male (Web, Measured) |
| Own-voice cloning | none | Base models, from a short clip (Measured, owner-accepted on 1.7B bf16) |
| Licence | Apache-2.0 | Apache-2.0 |
| Runtime | CoreML through FluidAudio (Apache-2.0) | MLX through one of three Swift packages (MIT or Apache-2.0) |
| Streaming | no; one chunk at a time | yes, after the whole text is prefilled |
| Text normalization | NeMo normalizer built in (Local, `KokoroAneManager.swift:193-198` in the July checkout) | none found upstream (Web) |
| One-minute passage in one request | completed at 62 to 72 s for five voices (Measured earlier) | clone 63 to 68 s; presets 73 to 179 s with long silences in two of four runs (Measured) |
| Peak memory | 788 MB in FluidAudio's own benchmark on M5 Pro (Local doc, not measured here) | 2.3 to 6.2 GB here (Measured) |
| Speed on ordinary Macs | FluidAudio's own figures only | third-party figures from slower than real time (M4 Pro, July) to about 3x (Mac mini M6) |
| Build | SwiftPM or Xcode | Xcode or `xcodebuild` required for the Metal shader library |

## Unresolved questions and practical impact

1. Whether the 4-bit and 0.6B clones still sound like the owner. This decides the download size of the own-voice feature (1.7 GB to 4.5 GB).
2. Whether Ryan or Aiden are acceptable built-in voices, and whether an English female voice is required. No English female preset exists; other ways to obtain one (VoiceDesign, or cloning from a licensed reference clip) were not tested.
3. Long-text behaviour. The preset anomalies and upstream reports were seen on single long requests. Behaviour with sentence or paragraph chunking, and over ten minutes, is unmeasured.
4. Performance on a typical Mac. All local numbers come from an M5 Ultra with 96 GB.
5. The Swift route. None of the three Swift runtimes was built here; their real latency, memory, stability on macOS 27 and behaviour under Hardened Runtime are unverified.
6. Numbers, abbreviations, file names and URLs without a text normalizer. Not evaluated.
7. Two models in memory at once (Base plus CustomVoice), or switching between them, was not measured.
8. Reuse of a saved voice prompt across launches in the Swift runtimes: an object exists in `mlx-audio-swift`, persistence to disk was not confirmed.

## Sources (Web, retrieved 2026-11-14 by a delegated investigator)

- https://github.com/QwenLM/Qwen3-TTS and its issues #10, #80, #134, #181, #239, #258, #359
- https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-Base and sibling cards under `Qwen/`
- https://huggingface.co/mlx-community (Qwen3-TTS conversions; sizes through the Hugging Face API)
- https://github.com/Blaizzy/mlx-audio-swift (v0.1.9; issues #58, #149, #185, #224; PR #315)
- https://github.com/soniqo/speech-swift (v0.0.29; issue #291) and https://soniqo.audio/benchmarks
- https://github.com/PowerBeef/QwenVoice (Vocello v3.0.0)
- https://github.com/ml-explore/mlx-swift (0.33.0; issues #345, #349, #415, #460, #485, #492, #500, #504)
- https://github.com/predict-woo/qwen3-tts.cpp, https://github.com/HaujetZhao/Qwen3-TTS-GGUF, https://github.com/gabriele-mastrapasqua/qwen3-tts
- ElevenLabs facts in the context section: https://elevenlabs.io/docs/product-guides/voices/voice-cloning/instant-voice-cloning, https://elevenlabs.io/oem-terms, https://elevenlabs.io/pricing/api

## Handoff

- Objective: descriptive research on Qwen3-TTS as the single engine. Scope: this artifact plus measurements in the task-owned folder. No implementation.
- Baseline: `develop` at `5b1933f`; three research documents are uncommitted; `.summon` was modified before the session and is preserved.
- Delegation: one read-only web investigation, completed; its unverified items are listed in section 5 and under "Unresolved questions".
- Checks run: the benchmark in section 3 and one offline-load check. No build of the app, no Swift runtime test.
- Resources: the task-owned folder `.local/listening-test/` (about 22 GB: downloaded models, Python environment, FluidAudio clone and build, generated samples, the owner's recordings and clones) was deleted on 2026-11-14 at the owner's request, after checking that no test process was running. The raw files cited in this report (`bench.jsonl`, `bench/*.wav`, sample files) therefore no longer exist; the figures above are the record. The owner's two original recordings remain in his own Desktop and Downloads folders and were not touched. One voice named "Juan - Captalo test" exists in the owner's ElevenLabs account, created by the owner and kept by his decision for other uses; about 5,300 credits were used in the trial.
- Outcome: the owner decided on Kokoro for built-in voices and Qwen3-TTS 1.7B Base 4-bit for an optional own-voice feature (see the clean-eyes assessment, "Speech engine decisions after the listening tests", and the [own-voice brief](2026-11-14-own-voice-brief.md)).
- Next: `rpi-plan`. Revalidate versions before relying on them.
