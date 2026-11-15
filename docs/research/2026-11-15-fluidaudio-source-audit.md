# FluidAudio source audit at the pin

- Date: 2026-11-15. Plan: `2026-11-15-captalo-core-reader.md`, phase 3, unit 3B ("Source audit at the pin").
- Source: FluidAudio tag `v0.18.3` (`c8b41f98`) plus `Patches/fluidaudio-v0.18.3-xcode27.patch`, local branch `captalo/v0.18.3-xcode27` at `6fe650eb` (notes D9). Searched `Sources/FluidAudio` of that checkout.

## Network entry points

- `URLSession` is used only in `ModelRegistry.swift`, `Shared/AssetDownloader.swift` and `Shared/Download/{HFTreeLister,RetryPolicy,HFClient,ModelHub,FileDownloader}.swift`. These are the model and asset download paths; KokoroAne reaches them only through its `ensure…` functions, which return before fetching when every file is present (`KokoroAneResourceDownloader.swift`; for example the English lexicon at the early `fileExists` return).
- No background or out-of-process configuration: no `URLSessionConfiguration.background`, `background(withIdentifier:)`, `sharedContainerIdentifier` or `isDiscretionary` anywhere in the sources. No stop condition.
- No `Process`, `posix_spawn` or `NSTask` in FluidAudio, and none in `Packages/CaptaloSpeech` (also checked by `make offline-test`).
- Cáptalo points `ModelRegistry.baseURL` at `http://127.0.0.1:9` before any FluidAudio call (`KokoroSynthesizer.build`), so a fetch attempt cannot reach a registry. `make offline-test` proves the in-process claim under the kill-on-deny profile.

## Logging of text

- `TTS/KokoroAne/G2P/English/KokoroAneEnglishPhonemizer.swift` (two calls) and `TTS/G2P/G2PModel.swift` (one call) log single words at warning level when G2P fails. No error- or fault-level call in the Kokoro, G2P and shared TTS paths interpolates text.
- `AppLogger.minimumLevel` and `AppLogger.mirrorsToConsole` disable these without a patch: Cáptalo sets `.error` and `false` before building the engine (`KokoroSynthesizer.build`). Release builds write the unified log with private message text; Debug builds would mirror to the console, which the setting turns off.
- Disposition: content logging at default level is disabled through FluidAudio's own configuration; no fork patch and no owner acceptance are needed.
