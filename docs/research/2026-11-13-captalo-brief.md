# Design Brief: Cáptalo

> Brainstormed on 2026-11-13

## Problem

Juan prefers listening to long passages, particularly English, his second language. He wants to hear text encountered anywhere on his Mac: terminal output, browser pages, PDFs, documents, and text inside images. His experience with macOS Speak Selection failed on selected terminal text, and its voice sounded unpleasantly robotic to him. Aloud resembles the desired capability, but its purchase price and floating reading window conflict with his preferences.

## Goal

“If I can see it, I can hear it”: turn deliberately selected text or a marked screen region into pleasant local speech with almost no visible interface.

## Scope

**In:** Mac-wide reading of selected text; a shortcut plus a dragged rectangle for text that cannot be selected; local OCR and speech; natural-sounding voice evaluation; long-passage listening; unobtrusive keyboard playback controls. Rex, browser pages, selectable and scanned PDFs, document editors, and images are representative acceptance surfaces, not a closed list of supported applications. Juan explicitly accepted the rectangle interaction.

**Out:** Cloud processing, paid reader dependencies, recurring voice fees, floating transcripts, AI companions, chat, summarization, and translation. Proposed initial exclusions are document libraries, audio export, automatic page turning, and continuous screen monitoring: none is necessary for the requested interaction. The screen-region path reads the visible marked area; it does not imply access to unseen document pages.

## Constraints

- Captured text, screenshots, OCR, and speech processing stay on the Mac. No cloud fallback.
- No purchase is required to use the proposed reader. Building and maintaining it still costs development time.
- Playback must leave the source app usable and avoid a persistent overlay. A temporary rectangle selector is accepted.
- English is the first voice acceptance case because it motivated the request; support for other languages has not been specified.
- The current machine reports an arm64 architecture. Broader hardware distribution is not a requirement established by this brainstorm.
- Model assets must be available locally before offline use. A one-time asset download is a proposed setup assumption, not permission to download or install anything now.
- macOS permissions for cross-app selection and screen capture may require explicit system consent. Capture remains user-triggered.

## Chosen Approach

The selected direction is a fork of Shreysid/Sotto, named Cáptalo, adapted into a small native macOS background utility serving all apps. Preserve its local Kokoro/FluidAudio speech foundation and add the missing behavior after planning. Two inputs feed one local speech player:

1. Select text in the source app and invoke a global shortcut. Prefer exposed selection data. An automatic copy fallback is a candidate where necessary, provided it can preserve the clipboard and cannot speak stale clipboard contents. Manual copying is not an established requirement.
2. Invoke the region shortcut and drag around visible text. Recognize that region locally and speak it. This provides an application-independent fallback when ordinary selection is unavailable.

Apple documents selected-text accessibility attributes and image text recognition through Vision. These establish available building blocks, not verified compatibility with every app. See [Accessibility attributes](https://developer.apple.com/documentation/applicationservices/carbon_accessibility/attributes) and [Vision text recognition](https://developer.apple.com/documentation/vision/recognizing-text-in-images).

Kokoro is the initial voice-engine candidate: its publisher describes an 82-million-parameter model with Apache-2.0 weights and provides inference examples. The engine and voice remain provisional until Juan hears locally generated samples and the Mac meets practical responsiveness requirements. An inference runtime and its dependencies still need evaluation. See the [official model card](https://huggingface.co/hexgrad/Kokoro-82M).

Proposed playback defaults are keyboard pause/resume and stop, one active reading at a time, and a new explicit reading replacing the previous one. Voice and speed preferences can live in settings opened on demand. Exact shortcuts and optional menu-bar status remain design details; no floating player is needed. Capture failures need brief, accessible feedback rather than silent failure.

Alternatives considered:

- **macOS Speak Selection:** rejected for this user's observed terminal failure and unacceptable voice. Its existence does not satisfy the requirement.
- **Aloud:** a close existing product, but rejected by Juan on cost and visible reading interface. Its website describes selection capture, local voices, and OCR; those claims were not tested in this session. See [Aloud](https://aloudapp.app/).
- **Rex-only integration:** narrower application coverage than the accepted goal. Rex documents custom actions, keyboard bindings, and copying pane selections, so a targeted bridge remains possible if testing reveals a gap. It is not a prerequisite or a verified integration. See [Rex Lua API](https://www.superlogical.com/rex/docs/reference/lua) and [Mac actions](https://www.superlogical.com/rex/docs/reference/mac-actions).
- **OCR for every reading:** broad visual coverage, but needlessly introduces recognition errors when exact selected text is available. Retain it as an explicit second input.

## Success Criteria

These are proposed observable acceptance checks, not completed test results.

1. Juan chooses a locally generated English voice and finds it comfortable for a ten-minute passage. A technically working voice that he dislikes fails acceptance.
2. Selected text in Rex, a browser, a selectable PDF, and a document editor can be read without pasting into a separate reader. The source app and exact tested versions are recorded.
3. A rectangle around a scanned PDF passage or image produces intelligible speech in sensible reading order. OCR inaccuracies are recorded rather than treated as perfect transcription.
4. Neither capture nor playback silently substitutes unrelated text, stale clipboard data, or an entire window for the requested passage.
5. Reading and OCR continue with network access disabled after assets are installed. There are no cloud credentials or service charges.
6. No floating transcript appears. After the temporary region selector closes, focus returns to the source app. Keyboard stop and pause/resume work while another app is active.
7. A long passage finishes without dropped or duplicated chunks. Cold and warm startup latency, resource use, and stop responsiveness are measured on Juan's Mac and reviewed with him before calling the experience unobtrusive.
8. Empty selections, unavailable capture, denied permissions, and unreadable regions give concise feedback and do not start an unrelated reading.

## Open Risks

- Voice quality is subjective and has not been auditioned. This is a go/no-go validation before substantial interface work, not a settled engine decision.
- App accessibility varies. Rex selection capture, document viewers, clipboard restoration, and shortcut conflicts require real application testing.
- OCR can misread small text, code, mathematical notation, or multi-column layouts. Protected capture surfaces may remain inaccessible. The product promise is broad coverage with explicit limitations, not a guarantee for every visible pixel.
- Local inference can introduce startup delay, CPU use, memory pressure, or fan noise that conflicts with an imperceptible experience.
- The fork inherits Swift, FluidAudio and Kokoro. Packaging, permissions, voice acceptance and dependency behavior still need verification; no OCR or quiet-interface feature has been implemented.
- No quantitative latency threshold, additional language requirement, or distribution objective was specified. These are follow-up acceptance details; the core product direction is sufficiently defined for planning.

The next workflow is `rpi-plan`. Begin by making voice acceptance and real-app capture evidence prerequisites for committing to the proposed engine and integration details. The owner subsequently authorized repository/workspace setup, RPI adoption, Summon configuration and Archy/Graphify enrollment. Product planning belongs in the dedicated Cáptalo session; product implementation and release remain separate.
