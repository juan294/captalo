# Design Brief: read in my own voice

> Brainstormed on 2026-11-14

## Problem

Juan understands long text better when he hears it, and the voice he hears when he reads silently is his own. A stranger's voice works, but it is not the experience he has in his head. Other listeners will have the same preference. Today a personal voice is available only through cloud services that keep the voice on their servers, bill every reading and receive every text that is read.

## Goal

Let a user optionally have Cáptalo read in a clone of their own voice, created once from a short recording and used entirely on their Mac.

## Scope

**In:**

- An optional "my own voice" mode next to the built-in voices.
- A one-time setup inside the app: explicit consent, a short recording of the user reading a provided text, local creation of the voice, a sample to confirm it.
- A one-time, user-initiated download of the cloning model, with its size shown before it starts.
- Reading selections and OCR regions in the cloned voice, offline, through the same shortcuts as the built-in voices.
- Removing the cloned voice and its recording from the Mac on request.

**Out:**

- Cloud voice services, including ElevenLabs. The owner tested an ElevenLabs instant clone and liked it, then chose the local route because clones there cannot be exported, every reading is billed and sent to its servers, and serving other users needs a plan from 299 USD per month.
- Accounts, payments, servers, or any transfer of a voice recording off the Mac.
- Cloning a voice other than the user's own. The consent step states this.
- Sharing, exporting or syncing cloned voices between Macs.
- Languages other than English in the first version.
- Using the cloning engine for the built-in voices. Its presets were rejected by the owner.

## Constraints

- All recording, cloning and speech stay on the Mac. No network use after the model download.
- The built-in voices (Kokoro v1.0, bundled, 92 MB) must work without this feature and without its download.
- Engine: Qwen3-TTS 1.7B Base, 4-bit MLX conversion, 2.34 GB, Apache-2.0. The 0.6B model is excluded: the owner judged its clone "terrible".
- The engine needs about 15 seconds of the user's speech at 24 kHz plus the exact transcript of that clip.
- Text is fed one sentence at a time with pauses inserted between sentences and paragraphs. A whole passage in one request sounded "like a train" to the owner; the sentence-by-sentence version was judged "good".
- The engine has no text normalizer for numbers, abbreviations, file names or URLs.
- The engine runs on Apple's MLX framework, not on FluidAudio. The app therefore carries two speech runtimes. MLX needs a Metal shader library that must be built with Xcode or `xcodebuild`.
- The voice recording and the derived voice data are sensitive personal data: stored only in the app's own folder, never logged, never committed, never uploaded.
- macOS 26 minimum, direct distribution, not sandboxed, as already decided.

## Chosen Approach

Kokoro stays the built-in engine. Own-voice is an optional second engine that the user turns on in settings:

1. The user chooses "Use my own voice" and reads the consent text (it is their own voice; everything stays on this Mac; the model download size).
2. The app downloads the Qwen3-TTS model once.
3. The app shows a short text to read aloud in a calm reading style and records about 20 seconds. Using a known text gives the transcript without speech recognition and gives the clone a reading rhythm instead of a conversational one.
4. The app creates the voice locally, plays a sample, and lets the user accept or record again.
5. From then on the read shortcuts use the cloned voice; the user can switch back to a built-in voice or delete the clone at any time.

Rejected alternatives:

- **ElevenLabs instant clone, user's own account:** best likeness in the trial, but cloud-only, billed per character, needs an account and key, and conflicts with the offline promise.
- **ElevenLabs through the owner's account as a paid service:** needs a 299 USD per month plan, a server, billing and custody of other people's voices; break-even was estimated at about 65 to 70 subscribers.
- **FluidAudio's local cloning (Pocket TTS, StyleTTS2, LuxTTS):** judged not close enough by the owner.
- **VoxCPM2 and LongCat-AudioDiT:** tested with the same clip; the owner preferred Qwen3-TTS.
- **Apple Personal Voice:** restricted by Apple to personal, non-commercial use, and its setup failed on the owner's Mac at the model download step.
- **Qwen3-TTS for everything:** two English presets only, both male, judged "horrible" and "not the greatest", and every user would need a 2.3 GB model.

## Success Criteria

Proposed observable checks, not completed results.

1. On Juan's Mac, a voice created in the app from an in-app recording is judged by Juan to sound like him and to be comfortable for a ten-minute passage.
2. After setup, reading in the cloned voice works with network access disabled, and no network request is made.
3. With the feature never enabled, the app downloads nothing and the built-in voices work as before.
4. Sentence and paragraph pauses are audible; no passage is read as one unbroken stream; no sentence is skipped, repeated or cut off in a ten-minute reading (checked against the text).
5. Numbers, a file name, an acronym and a URL in a test passage are read intelligibly.
6. Time from shortcut to first sound, generation speed and memory use are measured on Juan's Mac and on at least one ordinary Apple Silicon Mac, and reviewed with Juan before the feature is called usable.
7. The recording and voice data exist only inside the app's own folder and are gone after "delete my voice".
8. Declining consent, denying the microphone, cancelling the download or failing the clone leaves the app working with the built-in voices and tells the user what happened.

## Open Risks

- The engine has only been run through the Python MLX runtime on an Apple M5 Ultra with 96 GB. No Swift runtime was built. Published figures for other Macs range from slower than real time to about three times real time; nothing was found for M1 or M3.
- Three Swift packages can load the model (`mlx-audio-swift`, `speech-swift`, the Vocello engine fork). All are young; which one works under Hardened Runtime and on macOS 27 is untested.
- Third-party reports describe degraded 4-bit conversions and long-text instability (swallowed words, acceleration, looping). The owner's "good" verdict covers one one-minute passage.
- Peak memory was 4.0 GB for this model here, on top of Kokoro and the app.
- The clone copies the rhythm of the sample; a rushed or noisy recording gives a rushed or noisy voice.
- A cloned voice is a tool that could be misused to imitate someone else. The consent step is a statement, not verification.
- Whether a microphone usage description and permission prompt behave well in a background app with no Dock icon is untested.
- The feature may justify a different product name, as the owner noted. No naming decision was made.

## Evidence

Measurements, owner verdicts per sample and sources are in [Qwen3-TTS as the single speech engine](2026-11-14-qwen3-tts-single-engine.md) and [the clean-eyes re-evaluation](2026-11-14-clean-eyes-reevaluation-assessment.md). The test folder that held the samples and models was deleted on 2026-11-14 at the owner's request.

The next workflow is `rpi-plan`.
