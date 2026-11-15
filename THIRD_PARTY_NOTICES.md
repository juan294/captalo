# Third-party notices

## FluidAudio

Cáptalo, derived from Sotto, uses [FluidAudio](https://github.com/FluidInference/FluidAudio), the local audio inference layer for model loading and Apple Silicon inference. FluidAudio is licensed under the Apache License, Version 2.0.

Cáptalo builds FluidAudio from tag `v0.18.3` (`c8b41f98eae668794dd0083bbe028fe7e6585051`) with a local patch, `Patches/fluidaudio-v0.18.3-xcode27.patch`, that lets two LFM3Audio files compile with the Xcode 27 CoreAI SDK. The patch changes no Kokoro code and states its change, as the Apache License 2.0 requires for modified files.

The full license text is available at <https://www.apache.org/licenses/LICENSE-2.0>.

## Kokoro-82M voice files

The Cáptalo app bundle contains Kokoro-82M voice files: the Core ML conversion published as [FluidInference/kokoro-82m-coreml](https://huggingface.co/FluidInference/kokoro-82m-coreml) (revision `51c072023b254cd02368102ab88bcfbff6cad4cd`), including its English G2P models, vocabulary, US lexicon and the `af_heart` and `af_bella` voice packs, derived from [hexgrad/Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) (revision `f3ff3571791e39611d31c381e3a41a3af07b4987`). Both repositories state the Apache License, Version 2.0 (read 2026-11-15). The files are not part of this source repository; `make fetch-models` downloads them once and checks them against `Models.manifest.json`.
