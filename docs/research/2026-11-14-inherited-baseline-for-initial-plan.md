# Research: inherited Sotto baseline for the initial Cáptalo plan

- Date: 2026-11-14
- Repository: `juan294/captalo` at `/Users/juan/code/captalo`
- Branch: `develop`
- Commit: `5b1933fca50c25ea0fd5e55af294cb5b6d355133` (upstream product baseline `30e0dfbf2cfbef01b8c462bfec2452b3c0295a61`)
- Working tree at research time: only `.summon` modified (pre-existing, not touched by this research)
- Workflow: `rpi-research` (descriptive). No product code, configuration, dependency or remote state was changed.

## Research question

What does the inherited Sotto code actually do today, end to end, in the areas the initial Cáptalo plan must cover: trigger and shortcuts, selection capture and clipboard handling, text processing, local speech synthesis, playback controls, model installation and network behavior, visible interface, permissions, build identity, tests, and the absent screen-region OCR path? The [briefing](../briefing.md) and [design brief](2026-11-13-captalo-brief.md) define the target; this report records the starting point.

## Summary

The app is a small SwiftUI/AppKit program (28 source files, about 2,170 lines) with one global shortcut that reads the current selection and speaks it with FluidAudio's ANE-split Kokoro model. Capture tries Accessibility `AXSelectedText` on the focused element, then falls back to a synthetic Cmd+C with a 200 ms pasteboard poll and a snapshot restore. Text is flattened (newlines become spaces), split into 45 to 240 character chunks, synthesized sequentially and queued into one `AVAudioPlayerNode`. Speed is applied after synthesis by a time-pitch unit.

There is no screen capture, OCR, Vision or ScreenCaptureKit code. Pause, resume, stop and section skip exist only as buttons in the menu-bar popover; the only keyboard control is the single read shortcut, which also stops playback when pressed again on the same text. The app runs with a Dock icon (`.regular` activation policy) and a Studio window that activates the app over other apps when permission or model prompts appear. Feedback for capture failures is a status string in the menu-bar popover only.

FluidAudio's own documentation states the KokoroAne English chain ships a single voice, `af_heart`, and that adding voices requires model reconversion. Models download from Hugging Face into `~/.cache/fluidaudio/Models`, outside any app container. No Kokoro model is present on this Mac today. There is no test target. The app retains upstream identity (bundle ID `com.Shreysid.Sotto`, upstream development team `8P96S63H2N`).

## Detailed findings

Evidence labels: **Observed** means read in source or run in this session. **Inferred** means derived from reading code paths without running the app. **External** means a documented claim from a dependency or SDK, not measured here.

### 1. Application shell and visibility

- Observed: entry point is a SwiftUI `App` with a `MenuBarExtra` using `.window` style and an 18 pt animated waveform icon (`Sotto/App/SottoApp.swift:12-23`).
- Observed: launch sets `NSApplication.shared.setActivationPolicy(.regular)`, which gives the app a Dock icon and app menu (`Sotto/App/SottoApplicationDelegate.swift:14`). There is no `LSUIElement` key; the Info.plist is generated (`Sotto.xcodeproj/project.pbxproj:280-283`, `:325-328`).
- Observed: a 1040 x 690 "Sotto Studio" window controller is created at launch (`Sotto/App/SottoApplicationDelegate.swift:42-47`, `Sotto/UI/Studio/SottoStudioWindowController.swift:6-22`). Showing it calls `makeKeyAndOrderFront`, `orderFrontRegardless` and `activate(ignoringOtherApps: true)` (`Sotto/UI/Studio/SottoStudioWindowController.swift:26-33`). Clicking the Dock icon reopens it (`Sotto/App/SottoApplicationDelegate.swift:33-36`).
- Observed: the Studio window is opened automatically, with a sheet alert, when Accessibility is missing (`Sotto/App/SottoApplicationDelegate.swift:56-74`) or the Kokoro model is missing (`:76-94`). Each alert shows at most once per launch (`:10-11`, `:57-58`, `:77-78`).
- Observed: the menu-bar popover contains the title, a speed slider, an optional status line, a primary "Speak Selection" or download button, transport buttons (previous section, pause/resume, next section, stop, quit) and an "Open Sotto Studio" row (`Sotto/UI/MenuBar/SottoMenuBarView.swift:8-85`).
- Observed: Studio has three pages: Settings (voice engine, Accessibility, speed, "pause for voice apps", menu-bar status toggle, shortcut, voice status), Pronunciation, and Stats (`Sotto/UI/Studio/SottoStudioView.swift:8-31`, `Sotto/UI/Studio/SottoStudioSettingsView.swift:6-23`).
- Observed: the status icon animates at 24 fps whenever the status string starts with Preparing, Loading, Reading, Generating or Speaking (`Sotto/App/SottoAppState.swift:59-63`, `:75-78`, `Sotto/UI/MenuBar/WaveStatusIconAnimator.swift:15-31`).
- Observed: the hotkey path itself opens no window and does not call `activate`; it runs `speakSelection()` directly (`Sotto/App/SottoApplicationDelegate.swift:156-158`).
- Observed: no floating transcript or player panel exists; there is no `NSPanel` usage in `Sotto/` (repository grep this session).

### 2. Trigger and keyboard shortcuts

- Observed: one Carbon hotkey is registered with `RegisterEventHotKey`, signature `SOTT`, ID 1 (`Sotto/App/SottoApplicationDelegate.swift:103-145`). The handler ignores any other ID (`:120`). Default is Cmd+Shift+R (`Sotto/Models/GlobalShortcut.swift:5`).
- Observed: registration failure sets the message "That shortcut is already in use." (`Sotto/App/SottoApplicationDelegate.swift:140-144`), shown under the recorder in Studio (`Sotto/UI/Studio/SottoStudioSettingsView.swift:88-100`).
- Observed: the recorder rejects shortcuts without a modifier (`Sotto/Models/GlobalShortcut.swift:15-24`) and persists the shortcut as JSON in `UserDefaults` key `globalShortcut` (`Sotto/App/SottoAppStateSettings.swift:15-22`, `Sotto/App/SottoAppState.swift:51-56`).
- Observed: there are no keyboard shortcuts for pause/resume, stop or section skip. Those actions are reachable only through the popover buttons (`Sotto/UI/MenuBar/SottoMenuBarView.swift:45-63`).
- Observed: pressing the read shortcut again while the same text is playing stops playback (`Sotto/App/SottoAppStatePlayback.swift:31-36`). The comparison uses the raw captured `text`, while `SpeechController.activeText` holds the post-pronunciation `spokenText` (`Sotto/App/SottoAppStatePlayback.swift:40-43`, `Sotto/Services/SpeechController.swift:62`, `:87-89`). Inferred: when a pronunciation rule changes the text, the second press restarts the reading instead of stopping it.
- Observed: pressing the shortcut with a new selection replaces the current reading (`Sotto/Services/SpeechController.swift:57-65` stops the player, cancels synthesis and starts a new request).

### 3. Selection capture and clipboard handling

Flow: `speakSelection()` (`Sotto/App/SottoAppStatePlayback.swift:4-71`) checks Accessibility trust, then `canSpeak`, then calls `SelectionReader.read()` (`Sotto/Services/SelectionReader.swift:18-40`).

- Observed, Accessibility path: reads `AXFocusedUIElement` from the system-wide element, then `AXSelectedText` from that element (`Sotto/Services/SelectionReader.swift:52-68`). No other attributes (for example selected text ranges, parameterized string-for-range, or ancestor/child traversal) are queried. The result is trimmed and returned whole; there is no length limit (`:23-25`).
- Observed, copy fallback: when the AX value is absent or empty, it snapshots every pasteboard item's data for every type (`Sotto/Services/SelectionReader.swift:71-82`), posts Cmd+C key down/up through `CGEvent` at `.cghidEventTap` with only `.maskCommand` set (`:42-50`), then polls 20 times at 10 ms intervals for a `changeCount` change with a `.string` value (`:30-37`).
- Observed: on success or timeout it calls `restore`, which only rewrites the pasteboard if `changeCount` differs from the snapshot (`Sotto/Services/SelectionReader.swift:84-93`).
- Inferred from code: any pasteboard write during the 200 ms window is accepted as the selection, whatever process wrote it; the writer is not checked. A copy that lands after the window is neither read nor restored, so it remains on the user's clipboard. Snapshotting calls `item.data(forType:)` on every type, which forces promised data to materialize. The effect of the user's still-held shortcut modifiers (Shift in the default Cmd+Shift+R) on the synthetic Cmd+C has not been tested.
- Observed: no stale clipboard read path exists. If neither path yields text, `read()` returns `nil` (`Sotto/Services/SelectionReader.swift:38-39`).
- Observed failure handling: empty or missing selection stops any current reading and sets status "No text selected" (`Sotto/App/SottoAppStatePlayback.swift:25-30`). Missing Accessibility sets status "Accessibility access required" and triggers the one-time Studio alert (`:5-10`). Missing model sets "Kokoro needs to be installed" and triggers the download alert (`:14-19`).
- Recovery and visibility: status strings appear only inside the menu-bar popover when it is open and the status toggle is on (`Sotto/UI/MenuBar/SottoMenuBarView.swift:25-31`) and on the Studio Settings page. There is no sound, notification or transient HUD for capture failure. Accessibility state is re-read whenever the app becomes active (`Sotto/App/SottoApplicationDelegate.swift:38-40`, `Sotto/App/SottoAppStateAccessibility.swift:6-12`); the Settings row offers "Open Accessibility Settings" (`Sotto/UI/Studio/SottoStudioSettingsView.swift:49-61`, `Sotto/Services/SelectionReader.swift:10-16`).
- Not established: which target apps (Rex, browsers, PDF viewers, document editors) expose `AXSelectedText` and which need the copy fallback. No app was launched in this session.

### 4. Text processing before speech

- Observed: pronunciation rules are user-entered term/replacement pairs, stored as JSON in `UserDefaults` key `speech.pronunciationRules` (`Sotto/App/SottoAppState.swift:13`, `Sotto/App/SottoAppStatePronunciation.swift:45-62`). They are applied longest-term first as case-insensitive `\b`-bounded regex replacements on the text (`Sotto/App/SottoAppStatePronunciation.swift:33-43`).
- Observed: no Markdown, code, URL or symbol filtering exists. Upstream issue 5 (opened 2026-10-01, open) reports `**Hello there**` spoken as "asterisk asterisk hello there asterisk asterisk" and requests regex exclusions (retrieved with `gh issue view 5 -R Shreysid/Sotto`, 2026-11-14).
- Observed, chunker (`Sotto/Services/SpeechChunker.swift`): replaces NBSP and every newline with a space, then inserts a space after `.`, `!` or `?` when followed by an uppercase letter or digit (`:54-66`). Sentences come from `NLTokenizer(unit: .sentence)` (`:68-78`). Sentences split into phrases at words ending in `,`, `;` or `:` or when a phrase would exceed 240 characters (`:80-108`). The first chunk targets 45 to 110 characters for fast first audio; later chunks flush at 80 or more characters on a sentence end, with a 240 character hard limit (`:8-11`, `:26-49`, `:118-137`).
- Inferred: because newlines are removed before tokenization, line-oriented structure (tables, lists, code, terminal output, headings without terminal punctuation) is joined into running text. Upstream issue 1 (opened 2026-07-17, open) reports mixed reading order for tables and structured text (retrieved 2026-11-14).
- Observed: a single whitespace-free token longer than 240 characters stays in one phrase, because `boundedPhrases` only flushes before appending (`Sotto/Services/SpeechChunker.swift:92-99`).
- External/Observed in dependency: FluidAudio rejects phoneme strings longer than 510 with `phonemeSequenceTooLong` (`FluidAudio/Sources/FluidAudio/TTS/KokoroAne/Assets/KokoroAneVocab.swift:39-42`, `KokoroAneConstants.swift:27-29`). English text passes through NeMo normalization first, which expands forms such as "$5" and "2024" (`KokoroAneManager.swift:193-198`). The chunker limits characters, not phonemes; the margin for long numbers, symbols or expanded tokens is unmeasured.
- Observed: the "Words spoken" statistic stores only a whitespace word count (`Sotto/App/SottoAppStateStats.swift:4-10`). No captured text is written to disk by app code. The first-audio log line records chunk length and timing, not text (`Sotto/Services/SpeechControllerSynthesis.swift:35-37`).

### 5. Local speech engine (FluidAudio KokoroAne)

- Observed: dependency is `https://github.com/FluidInference/FluidAudio.git` pinned by revision `5fc19fcde8aff5970ab18c974b109891479384c2` (`Sotto.xcodeproj/project.pbxproj:372-376`); `Package.resolved` records branch `main` at that revision (`Sotto.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`). The local checkout's head commit is dated 2026-07-15. FluidAudio is Apache-2.0 (`FluidAudio/LICENSE`) and also pulls a prebuilt `NemoTextProcessing.xcframework` binary from GitHub releases (`FluidAudio/Package.swift:36-42`).
- Observed: Sotto creates `KokoroAneManager(defaultVoice: "af_heart")` (`Sotto/Services/SpeechController.swift:7`). `prepare()` initializes and warms with "Ready."; on failure it retries once with `computeUnits: .cpuAndGpu` (`Sotto/Services/SpeechControllerKokoro.swift:62-80`).
- External: FluidAudio documents the KokoroAne English variant as a single voice, `af_heart`, and says adding voices requires reconverting four of the seven CoreML stages (`FluidAudio/Documentation/TTS/KokoroAne.md:17`, `:160-163`, `:203`). The same document points to `PocketTtsSynthesizer` or `StyleTTS2Manager` for multi-voice use (`:23-24`). The code still exposes `ensureVoicePack` downloads for other voice names (`KokoroAneResourceDownloader.swift:327-370`); whether those packs work with the converted chain is not established.
- External: the same document says "Custom lexicon: No" (`KokoroAne.md:19`), while the code exposes `setEnglishCustomLexicon` for word-to-IPA overrides (`KokoroAneManager.swift:139-143`). Sotto does not call it.
- External, unmeasured here: first-ever load about 20 s on M1 (ANE compile), warm load about 0.3 s, synthesis 3 to 11 times real time (`KokoroAne.md:211-214`).
- Observed: the pinned package also contains other TTS backends: PocketTTS, StyleTTS2, LuxTts and Supertonic3 (`FluidAudio/Sources/FluidAudio/TTS/` listing). Sotto uses none of them. Upstream issue 3 requests alternate local models such as PocketTTS (open, retrieved 2026-11-14).
- Observed: synthesis speed parameter stays at the default 1.0; Sotto never passes `speed:` (`Sotto/Services/SpeechControllerSynthesis.swift:30`, `:65`).

### 6. Playback pipeline and controls

- Observed: `AVAudioEngine` graph is player node to `AVAudioUnitTimePitch` to main mixer, 24 kHz mono Float32 (`Sotto/Services/SpeechController.swift:8-41`). Speed is the time-pitch `rate`, clamped to 0.75 to 1.35 (`:43-49`), selectable in six steps (`Sotto/App/SottoAppState.swift:8`).
- Observed: the first chunk is synthesized and scheduled, then a task synthesizes the remaining chunks in order and schedules each buffer as soon as it is ready (`Sotto/Services/SpeechControllerSynthesis.swift:18-77`). The loop does not wait for playback, so synthesis runs ahead and all remaining audio accumulates as scheduled buffers (Inferred memory effect for long passages; unmeasured).
- Observed: completion is detected when synthesis is complete and every scheduled buffer has reported `.dataPlayedBack` (`Sotto/Services/SpeechControllerPlayback.swift:45-65`). Requests are guarded by a UUID so stale callbacks are ignored (`:46`, `:52`).
- Observed: pause/resume toggles `player.pause()`/`play()`; synthesis continues while paused (`Sotto/Services/SpeechController.swift:91-101`). Stop clears the request, cancels synthesis and stops the player (`:73-81`).
- Observed: section skip uses the chunk list (`Sotto/Services/SpeechController.swift:103-124`). `sectionIndex` is updated when a chunk is scheduled, not when it becomes audible (`Sotto/Services/SpeechControllerSynthesis.swift:68`). Inferred: because synthesis runs ahead, "next" and "previous" are relative to the last synthesized chunk, not the one being heard.
- Observed failure mode: if a later chunk fails to synthesize, `onError` sets "Playback error: ..." and the loop exits without setting `synthesisComplete` (`Sotto/Services/SpeechControllerSynthesis.swift:73-76`). Inferred: already-scheduled audio plays, then the request stays active with no "Finished" callback. Recovery is a manual stop or a new read; the error is visible only as popover/Studio status.
- Observed: when one of eight listed bundle IDs (Siri, ChatGPT, Claude desktop, Zoom, FaceTime, Teams, Discord, Slack) becomes frontmost and the toggle is on, playback stops (`Sotto/App/SottoAppStateSettings.swift:28-37`, `Sotto/App/SottoApplicationDelegate.swift:147-167`).
- Observed: there is no audio route or device-change handling in the current code. History: upstream commits `f4de59b` and `313cb61` added audio output recovery (`SpeechAudioOutput.swift`, `AudioOutputDevice.swift`, `tests/AudioOutputChecks.swift`) and `30e0dfb` (2026-10-24) reverted all of it, 629 lines removed; the commit message gives no reason (`git show --stat 30e0dfb`).
- Observed: speed, "pause for voice apps" and "menu bar status" are plain `@Published` properties with no persistence, so they reset on launch (`Sotto/App/SottoAppState.swift:17-19`, `Sotto/App/SottoAppStateSettings.swift:9-13`).

### 7. Model installation, storage and network behavior

- Observed: model root is `~/.cache/fluidaudio/Models` on macOS (`FluidAudio/Sources/FluidAudio/TTS/Shared/TtsCacheDirectory.swift:22-43`, `KokoroAneResourceDownloader.swift:12`, `:374-378`). This is shared by any FluidAudio client of the same user and sits outside an app container.
- Observed: Sotto's "installed" check counts the seven `.mlmodelc` bundles, `vocab.json`, `af_heart.bin` and three G2P files (`Sotto/Services/SpeechControllerKokoro.swift:10-26`; names at `FluidAudio/Sources/FluidAudio/ModelNames.swift:1277-1309`).
- Observed: downloads use `https://huggingface.co` unless `REGISTRY_URL` or `MODEL_REGISTRY_URL` is set (`FluidAudio/Sources/FluidAudio/ModelRegistry.swift:32-37`). The UI describes the download as about 170 MB (`Sotto/App/SottoApplicationDelegate.swift:85`); the actual size was not measured.
- Observed: `KokoroAneManager.initialize()` also fetches `us_lexicon_cache.json` on a best-effort basis (`KokoroAneManager.swift:88-95`, `KokoroAneResourceDownloader.swift:289-318`). This file is not part of Sotto's installed check. When the lexicon is unavailable, the phonemizer is not cached and the fetch is retried on the next phonemize call (`KokoroAneManager.swift:291-331`). Inferred: with the lexicon missing and the network off, every chunk attempts a network request before falling back to BART-only G2P. Runtime offline behavior was not tested.
- Observed: delete removes the two model folders and resets the manager (`Sotto/Services/SpeechControllerKokoro.swift:44-60`).
- Observed on this Mac: `~/.cache/fluidaudio/Models` does not exist (`ls`, 2026-11-14). No voice is installed, so no local audition has been possible.
- Observed: build settings allow outgoing network connections and disable incoming ones; App Sandbox is off; Hardened Runtime is on (`Sotto.xcodeproj/project.pbxproj:266-269`, `:311-314`). `Sotto/Sotto.entitlements` is an empty dictionary (`Sotto/Sotto.entitlements:4-5`).

### 8. Permissions

- Observed: Accessibility is checked with `AXIsProcessTrusted()` (`Sotto/Services/SelectionReader.swift:6-8`); the app never calls `AXIsProcessTrustedWithOptions` to raise the system prompt and instead deep-links to System Settings (`:10-16`).
- Observed: no Screen Recording, microphone or other privacy usage strings or checks exist. Generated Info.plist keys are limited to display name, category and copyright (`Sotto.xcodeproj/project.pbxproj:325-328`).
- Inferred: because the bundle ID and team are inherited, any macOS permission grant made for a local build is tied to the current signing identity; changing either later can require granting permissions again. Not tested.

### 9. Screen-region OCR (absent) and available SDK building blocks

- Observed: no `Vision`, `ScreenCaptureKit`, `CGWindowListCreateImage` or selection-overlay code exists in `Sotto/` (repository grep this session).
- Observed in the installed macOS 27.0 SDK (Xcode 27.0, build 27A5218g):
  - `SCScreenshotManager.captureImage(in:completionHandler:)` captures a screen-space rectangle, available from macOS 15.2 (`MacOSX27.0.sdk/.../ScreenCaptureKit.framework/Headers/SCScreenshotManager.h:156-161`).
  - `CGWindowListCreateImage` is marked `SCREEN_CAPTURE_OBSOLETE(10.5,14.0,15.0)` (`MacOSX27.0.sdk/.../CoreGraphics.framework/Headers/CGWindow.h:271-274`). The target deploys to macOS 15.0.
  - Swift Vision `RecognizeTextRequest` is available from macOS 15.0; `RecognizeDocumentsRequest` from macOS 26.0 (`MacOSX27.0.sdk/.../Vision.framework/Modules/Vision.swiftmodule/arm64e-apple-macos.swiftinterface:2385-2386`, `:2567-2568`). `VNRecognizeTextRequestRevision3` adds automatic language detection (`.../Vision.framework/Headers/VNRecognizeTextRequest.h:72-74`, `:103`).
- Not established: OCR accuracy, reading order on multi-column or code content, and the exact TCC prompt behavior for region capture on macOS 27.

### 10. Build identity, toolchain and tests

- Observed: one native application target `Sotto` (`Sotto.xcodeproj/project.pbxproj:55-79`). Bundle ID `com.Shreysid.Sotto`, display name Sotto, version 1.0 (1), development team `8P96S63H2N`, automatic signing, deployment target macOS 15.0, Swift language mode 5.0 with default `MainActor` isolation and approachable concurrency (`Sotto.xcodeproj/project.pbxproj:262-298`, `:307-343`). Logger subsystem and queue labels use `com.shreysid.Sotto` (`Sotto/Services/SpeechController.swift:6`, `:11-14`).
- Observed: no XCTest target, test files or CI workflow exist in the repository. The reverted upstream `tests/AudioOutputChecks.swift` was the only prior check file (`git show --stat 30e0dfb`).
- Observed on this Mac: macOS 27.2.1 (26B131), Xcode 27.0 at `/Applications/Xcode-beta.app`. The setup handoff records a passing unsigned Debug build at this commit with DerivedData retained at `.local/setup/DerivedData` (about 924 MB) for reuse ([setup handoff](../setup-handoff.md)). No build was rerun in this session.
- Observed: the graph at `graphify-out` was built at the current commit `5b1933f` (graph stats query, 1,442 nodes). Its most connected app nodes are `SottoAppState`, `SpeechController` and `SottoApplicationDelegate`, matching the source reading.

## Control-flow map

1. Hotkey press: Carbon handler (`Sotto/App/SottoApplicationDelegate.swift:109-125`) to `SottoAppState.speakSelection()` (`Sotto/App/SottoAppStatePlayback.swift:4`).
2. Guards: Accessibility trust (`:5-10`), model ready (`:14-20`).
3. Capture: `SelectionReader.read()`: AX selected text, else synthetic copy with restore (`Sotto/Services/SelectionReader.swift:18-40`).
4. Toggle check against the active text (`Sotto/App/SottoAppStatePlayback.swift:31-36`).
5. Word count stat, pronunciation substitution (`:39-40`).
6. `SpeechController.speak` (`Sotto/Services/SpeechController.swift:51-71`) to chunking (`Sotto/Services/SpeechControllerSynthesis.swift:13`) to first-chunk synth and play (`:26-38`) to background synth of the rest (`:45-48`, `:56-77`).
7. Buffer completion bookkeeping to "Finished" status (`Sotto/Services/SpeechControllerPlayback.swift:45-65`, `Sotto/App/SottoAppStatePlayback.swift:59-65`).

## Relevant historical context

- The fork baseline adds only workspace, RPI and documentation files on top of upstream `30e0dfb` (`git log`, commit `5b1933f`).
- Upstream open issues: 1 (structured text reading order), 2 (optional cloud providers with user API keys, which conflicts with the accepted all-local constraint), 3 (alternate local TTS such as PocketTTS), 5 (regex exclusions for Markdown). Retrieved with `gh issue list -R Shreysid/Sotto --state all`, 2026-11-14.
- The upstream README lists internet access for first dependency resolution and the Kokoro download as a requirement (`docs/upstream/Sotto-README.md:38`).

## Unresolved questions and practical impact

1. Voice acceptance: no model is installed and `af_heart` is the only documented KokoroAne English voice. The plan needs an explicit, owner-authorized model download before any audition, and must account for the documented one-voice limit if Juan rejects `af_heart`.
2. Per-app capture: which representative apps return `AXSelectedText` versus requiring the copy fallback is unknown. This decides how much clipboard-safety work the selection path needs.
3. Clipboard edge cases: late copies after 200 ms, other writers during the window, held shortcut modifiers and promised pasteboard data are untested inferences from code.
4. Offline behavior: the per-chunk lexicon retry and any other network attempts with assets installed are untested. Criterion 5 of the design brief depends on this.
5. Chunk safety: the character-based chunker against the 510-phoneme limit is unmeasured for numbers, symbols and long tokens.
6. Long-passage resources: unbounded synthesis-ahead buffering and the reverted audio-device recovery mean memory use and device switching during a ten-minute passage are unknown.
7. Region capture: Screen Recording consent behavior, `captureImage(in:)` with the macOS 15.0 deployment target (API needs 15.2), and OCR quality on Juan's content are all unverified.
8. Identity: the inherited bundle ID and upstream team affect local signing and permission grants; the plan must decide when identity changes, because each change can reset permissions.

## Handoff

- Objective: descriptive baseline research to inform the first `rpi-plan` for Cáptalo. Scope was read-only; no implementation, download, app launch, permission change or remote write was authorized or performed.
- Base and current: `develop` at `5b1933fca50c25ea0fd5e55af294cb5b6d355133`, worktree `/Users/juan/code/captalo`. The only pre-existing change is `.summon` (preserved).
- Evidence sources: full reads of all 28 files under `Sotto/`, `Sotto.xcodeproj/project.pbxproj` build settings, `Package.resolved`, the FluidAudio checkout at `.local/setup/DerivedData/SourcePackages/checkouts/FluidAudio` (revision `5fc19fc`), the installed macOS 27.0 SDK headers, `gh` reads of upstream issues, and the local graph. No delegated agents were used, so there are no delegated coverage gaps.
- Checks: no build or test was run. Build evidence comes from the setup handoff and applies only to commit `5b1933f`.
- Resources: none allocated. The retained `.local/setup/DerivedData` (setup-owned) and the FluidAudio checkout inside it were only read.
- Next phase: `/rpi-plan` (or `$rpi-plan`) in a new session. Before relying on these findings, verify that `develop` still points at `5b1933f` and that `Sotto/` is unchanged.
