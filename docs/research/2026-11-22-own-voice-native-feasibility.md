# Can native Swift read a new sentence using a local reference voice?

The November 14 test established an owner preference for the paced Qwen clone using Python. This investigation exercises a Swift runtime on the Studio with a synthetic reference. The product still needs in-app enrollment, shared playback and an owner listening test. [Design brief](2026-11-14-own-voice-brief.md)

## Inputs and method

- Hardware and OS: Apple M5 Ultra, 96 GiB, macOS 27.2.1 (26B131). Project Xcode 27.0 beta (27A5218g). Project baseline 255af060975f52b1c7b4cffac2c6834b82512612.
- Native SDK: mlx-audio-swift 0.2.1 at ff174ab2e961aa7516dedecf273be54c24b6426d. Swift package uses MLXAudioTTS and MLXAudioCore. Its MLX Swift dependency in the probe is 0.33.0 at 7ede4fd6d05f63305c1c0ebf4f8c1909a637c574. [Pinned SDK source](https://github.com/Neywa-Labs/mlx-audio-swift/tree/ff174ab2e961aa7516dedecf273be54c24b6426d)
- Public model: mlx-community/Qwen3-TTS-12Hz-1.7B-Base-4bit at 37e955a1deb861c088ae5f3a67043185f3d1a60c. The twelve payload files total **2,336,074,141 bytes**. The fetcher checked large-file SHA-256 and Git blob identities against the revision metadata and computed SHA-256 for every file. The main weight SHA-256 is ac973aa38ec79d4b4b52bf858948f0d47dd909aa4bcd383f5b900e277410fdb5. The speech tokenizer weight SHA-256 is 836b7b357f5ea43e889936a3709af68dfe3751881acefe4ecf0dbd30ba571258. [Pinned model files](https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-1.7B-Base-4bit/tree/37e955a1deb861c088ae5f3a67043185f3d1a60c)
- Reference: macOS synthetic speech, 8.403 seconds, 24 kHz mono. It describes morning light, a bird and a fence. Its exact transcript went to the conditioning API. The target was **“The silver lantern glowed beside the garden gate.”** No microphone, personal recording or captured text was used.
- The standalone Swift probe loads from a disposable clone of the verified model, calls prepareReferenceConditioning, then requests generateStream with a 0.32-second streaming interval and a 160-token ceiling. It uses the SDK defaults for sampling (temperature 0.9, top-p 1.0, repetition penalty 1.05) and does not fix the random seed. It measures first nonempty PCM and total generation separately, checks finite non-silent samples, and writes a synthetic WAV. A network policy kills the process on outbound network access. A deliberate network attempt under that policy exited with signal 9. The same profile denies reads from the source checkout, build products and the default Hugging Face cache. A separate path control failed as expected.
- A separate recognizer uses Parakeet TDT v2 through FluidAudio, loaded directly from the Mac's existing local Core ML files with outbound networking denied. The reference control recovered its words, with “blue bird” transcribed as “bluebird”. Compare the generated sentence with the target, ignoring case and punctuation only.

## Build and packaging observations

The initial build failed because the beta Xcode lacked its Metal compiler. Apple's matching developer component was installed. A tiny compiled Metal kernel on the Studio returned 42 for input 21. The global xcode-select setting remained at CommandLineTools. End users need the built shader resource inside the app. A second build showed that swift-collections 1.7.6 uses a compiler feature unavailable in this beta. The probe pinned 1.6.0. Swift's optimizer also crashed compiling an unrelated Irodori model in the same SDK target. These are engineering constraints for the optional helper.

The pinned SDK creates tokenizer.json beside the model when that file is absent. Its loader also contains a branch that removes the supplied model directory if the speech tokenizer has an unexpected filesystem layout. Keep staging separate from personal data, check the complete file tree first, and test corrupt layouts before integrating. [Local loader source](https://github.com/Neywa-Labs/mlx-audio-swift/blob/ff174ab2e961aa7516dedecf273be54c24b6426d/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTS.swift#L1145-L1230)

## Result on the Studio

**The signed native probe spoke all eight target words offline.** The independent recognizer transcribed “The silver lantern glowed beside the garden gate.” The file contained 69,120 finite mono Float32 samples at 24 kHz. This establishes conditioned native synthesis of a novel sentence. Only a listener familiar with the real speaker can judge resemblance.

| First request in a newly launched process | Measurement |
| --- | ---: |
| Local model load | 1.601 s |
| Reference conditioning | 4.447 s |
| Generation request to first nonempty PCM | 7.228 s |
| Start of model load to first PCM | 13.276 s |
| Generation request to complete unit | 7.703 s |
| Audio duration produced | 2.880 s |
| Peak process memory footprint (macOS time -lp) | 6,553,045,872 bytes |
| Maximum resident set (same run) | 2,501,591,040 bytes |
| Signed standalone bundle, sum of regular file lengths | 33,432,522 bytes |

The first generation took 2.67 seconds per second of audio. The current reader waits for a complete unit, and this probe wrote a file without opening an output device. Actual shortcut-to-first-sound and installed-app footprint must be measured in the app. The process peak includes the runtime and GPU work attributed by macOS. It does not include a concurrently running Cáptalo process.

The successful arm64 Release build used the project beta, swift-collections 1.6.0 and a local SDK patch that disables optimization for two unused Irodori samplers, irodoriSampleEulerCFG and irodoriSampleEulerMeanFlow. The Qwen and MLX code paths retained Release optimization. The standalone app passed strict signature verification with Hardened Runtime enabled. There is no reproducible stock-SDK Release build on this beta in the evidence. Before adopting this dependency, reproduce the candidate with a reviewed, pinned patch or an upstream/toolchain fix, and verify the helper when nested inside the actual Cáptalo app.

## Reading another sentence

A second process on the same Studio, after the first run, took 0.407 s to load and 0.040 s to condition. Its first request delivered PCM after 0.158 s. Keeping that process, model and conditioning alive, a different sentence delivered first PCM in **0.087 s** and **3.20 s of complete audio in 0.646 s**. The independent recognizer recovered all ten words of “By noon, the yellow boat had reached the old bridge.” It also recovered the repeated first sentence. Differences in persistent runtime, filesystem or shader caches were not isolated. Treat the first observed run and same-process reuse as two observations, not guaranteed latency bounds.

The two-request process peaked at **7,005,014,872 bytes** of memory footprint. The warm generation rate supports testing a continuous reading. The initial delay and memory cost justify loading the engine only when requested and measuring it alongside the reader before calling the feature usable. Long passages, owner likeness, installed app behavior and ordinary-Mac efficiency remain open. [Phase 1 acceptance](../plans/2026-11-22-own-voice-phases/phase-1.md)

## Local handoff

The Cáptalo project retains the pinned public weights and snapshot under .local/own-voice-model, the signed probe, synthetic samples, build recipe, exact package lock, compiler patch and logs under .local/own-voice-spike, and the independent ASR harness and transcripts under .local/own-voice-asr for Phase 1. The source tree and snapshot are separate from the writable model copy. Release the disposable probe build products after the nested helper reproduces the evidence. The small Metal control receipt is under .local/own-voice-metal. Its duplicate 870 MiB toolchain export was removed after checking consumers. The installed developer component remains available to Xcode. The runs exited and used no service or microphone.
