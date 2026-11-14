# Cáptalo: project briefing

> Created 2026-11-13. Read this before planning or changing the application.

## Purpose and accepted decisions

Listening helps the owner understand long passages faster, especially in English as a second language. The product promise is “If I can see it, I can hear it.” Coverage includes terminals, browser pages, PDFs, document editors, scanned pages and text in images; Rex is one acceptance surface, not the product boundary.

The name is **Cáptalo**, with ASCII slug `captalo`. Suggested copy is “Escúchalo. Cáptalo.” The name was accepted after an initial public-name search found no exact-name read-aloud app, although unrelated businesses use Captalo. No domain registration or trademark clearance was performed.

The app must process text, speech and OCR locally, require no paid reader or cloud voice subscription, and remain nearly invisible during use. No floating transcript or player window. A temporary screen-region selection rectangle is explicitly accepted. Select text and invoke a shortcut for ordinary reading; invoke a region shortcut and drag when selection is unavailable. Pleasant voice quality is a hard acceptance requirement, not something inferred from the model name.

## Why a fork

The owner selected [Shreysid/Sotto](https://github.com/Shreysid/Sotto) as the starting point after discovering it already implements selection capture, local Kokoro speech, clipboard restoration and playback controls. The owner explicitly authorized creating the GitHub fork and setting up this dedicated workspace, Summon, RPI, Archy tracking and Graphify. No product implementation plan was requested in the Archy conversation.

- Repository: https://github.com/juan294/captalo
- Local workspace: `/Users/juan/code/captalo`
- Upstream baseline: `30e0dfbf2cfbef01b8c462bfec2452b3c0295a61`
- Integration branch: `develop`; release branch: `main`.
- `origin` targets the fork. `upstream` fetches the original; its local push URL is disabled to prevent accidental upstream publication.
- Preserve upstream history, LICENSE and THIRD_PARTY_NOTICES.md. Keep changes small enough to review upstream improvements and potentially contribute fixes separately.

## What exists and what does not

At the baseline, `Sotto/Services/SelectionReader.swift:18` reads selected text using Accessibility, with a simulated-copy fallback. `Sotto/Services/SpeechController.swift:6` configures the local Kokoro voice. `Sotto/Services/SpeechControllerKokoro.swift:62` prepares local inference with CPU/GPU fallback. `Sotto/App/SottoApplicationDelegate.swift:14` uses regular app activation and creates the Studio controller.

The application is still named Sotto internally and in the inherited UI. No source rename or new app icon was part of setup. Screen-region OCR, a fully quiet app presence, and confirmed Rex/PDF/document compatibility remain future work. The source contains no inherited automated test target or CI workflow. Build success alone cannot establish speech quality, runtime privacy, clipboard safety, or compatibility.

Upstream reports describe Markdown punctuation being spoken (issue 5) and structured text reading order problems (issue 1). These are useful reproduction candidates, not proof that every case fails locally. No broad refactor or backend replacement has been approved.

## Workspace conventions

Use native RPI skills: `$rpi-plan` in Codex or `/rpi-plan` in Claude, then the other `rpi-*` skills as the phase requires. Shared instructions live in AGENTS.md; CLAUDE.md imports them. Skills and ownership baselines are installed through cc-rpi's lifecycle engine rather than copied ad hoc. Summon uses the existing `opus-codex-shell` layout.

Archy enrollment is local fleet/tracking integration. It does not authorize hosted graph export, deployment, or changes to Sutura-owned CI routing. Graphify must be queried through this repository's own `graphify-out` link after indexing; absent/stale graph evidence falls back to source and must be reported.

## Research and owner decisions of 2026-11-14

Read these before planning. Where they differ from the sections above or from the 2026-11-13 design brief, the newer documents govern.

- [Inherited baseline](research/2026-11-14-inherited-baseline-for-initial-plan.md): what the Sotto code does today, with `file:line` evidence.
- [Clean-eyes re-evaluation](research/2026-11-14-clean-eyes-reevaluation-assessment.md): every inherited choice reassessed, the owner's answers, the distribution decision, the development method and the speech engine decisions.
- [Qwen3-TTS research](research/2026-11-14-qwen3-tts-single-engine.md): measurements and owner listening verdicts behind the own-voice engine.
- [Own-voice design brief](research/2026-11-14-own-voice-brief.md): the optional "read in my own voice" feature.

Decisions in force:

- Built-in voices: Kokoro v1.0 through an upgraded FluidAudio, bundled in the app, English only.
- Own voice: optional, local clone with Qwen3-TTS 1.7B Base 4-bit as a one-time user-initiated download. No cloud voice service.
- Interface: background app with no Dock icon, no menu-bar item and no popover; one small settings window; user-chosen shortcuts; silence when nothing is selected; Pronunciation and Stats screens removed.
- Capture: layered Accessibility reader, then the app's own Copy menu item, then synthetic copy as last resort; a per-app probe comes first. Screen-region OCR with ScreenCaptureKit and `RecognizeDocumentsRequest`.
- Platform and distribution: macOS 26 minimum; direct download from the owner's site, Developer ID signed and notarized; no App Store or TestFlight; not sandboxed.
- Identity: own name, team and bundle ID. Recommended `com.thecreativetoken.captalo`; the owner has not yet confirmed the exact string.
- Development method: Makefile wrapping `xcodebuild` with `xcbeautify`, signed build installed at one fixed path, unit tests first, local Apple documentation, "no fallbacks without approval".

Still open for the plan: bundle ID confirmation; the Swift build of Qwen3-TTS and its behaviour on an ordinary Mac; FluidAudio v0.18.3 not compiling unmodified with Xcode 27.0 beta; whether the Xcode 27 JSON project format is usable for the rename.

## Next session

Start with `$rpi-plan` or `/rpi-plan` here. Read this briefing, AGENTS.md, the [design brief](research/2026-11-13-captalo-brief.md), and the [setup handoff](setup-handoff.md). Verify actual refs and setup evidence before using them. Plan from the inherited behavior and reproduce relevant gaps before proposing repairs. Make local voice acceptance and cross-app capture validation early decisions, include the accepted rectangle/OCR interaction and minimal interface, and preserve the all-local constraint. Stop after the reviewed product plan; this setup does not authorize product implementation or release.
