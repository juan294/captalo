# Assessment: clean-eyes re-evaluation of the inherited Sotto decisions

- Date: 2026-11-14
- Repository: `juan294/captalo`, branch `develop`, commit `5b1933fca50c25ea0fd5e55af294cb5b6d355133`
- Workflow: `rpi-assess` (evaluative). No code, configuration, dependency, download or remote state was changed.
- Builds on: [inherited baseline research](2026-11-14-inherited-baseline-for-initial-plan.md) (current-state evidence with `file:line`), the [briefing](../briefing.md) and the [design brief](2026-11-13-captalo-brief.md).

## Question

Starting from the Sotto fork but taking none of its choices for granted, what should Cáptalo use in November 2026 for speech, capture, text cleanup, OCR, app shell, offline guarantees and app identity?

## Owner decisions recorded in this session (2026-11-14)

1. The global shortcut must be user-configurable, never fixed.
2. No menu-bar item, no popover, no pause/play interface. Interaction is "select, press, listen". Minimal settings.
3. The app gets its own name, bundle ID and signing identity under the owner's control.
4. Minimum macOS may be 15.2 or newer. Older versions are of no interest.
5. Fully offline operation after install is mandatory.
6. Nothing is installed until the engine decision is made.

## Criteria

Voice pleasantness over 10 minutes (owner's ear decides), more than one voice, fully offline after one install, redistribution-safe licence, time to first audio, invisibility, clipboard and focus safety, low maintenance, small change from working code where that does not cost quality.

## Evidence labels

- **Local**: read on this machine in this session (repository, pinned FluidAudio checkout `5fc19fc`, macOS 27.0 SDK).
- **Web**: page opened by a delegated read-only investigator on 2026-11-14; URL listed under Sources.
- **Inferred**: reasoning or unopened source. Not proof.

Three investigations were delegated (speech models; selection capture and shell; OCR and Apple signing). All three returned. Their unverified items are carried into "Uncertainties".

## 1. Speech engine

### Current state

Sotto pins FluidAudio at a July 2026 revision and uses `KokoroAneManager` with one voice, `af_heart` (Local, `Sotto/Services/SpeechController.swift:7`). That revision's documentation says one voice per variant (Local, `Documentation/TTS/KokoroAne.md:17`).

### What changed since the pin

- FluidAudio v0.18.3 was released 2026-11-07; the pin is four months old (Web).
- Since v0.15.7 (2026-09-09) the Kokoro English backend accepts any Kokoro-82M v1.0 voice: 28 English voices (20 US, 8 GB) (Web). The one-voice limit in the baseline report is true only for the pinned revision.
- Kokoro-82M v1.0 (January 2025) is still the latest English Kokoro. No newer English model exists upstream (Web).
- New FluidAudio backends since July include Phonon 31m and smaller Pocket TTS variants (Web).
- FluidAudio documents a Metal abort on macOS 27.0.1 and now avoids Metal by default on macOS 27. This Mac runs 27.2.1 (Web for the advisory, Local for the OS version). Stability here is untested.

### Options

| Option | Licence | English voices | Spanish | First audio | Long text | Main risk |
|---|---|---|---|---|---|---|
| A. Kokoro-82M v1.0 on current FluidAudio | Apache-2.0 | 28 | 3 voices, older runtime, ungraded | about 280 ms per chunk on M5 Pro (FluidAudio's figure) | app must chunk under 510 phonemes; no streaming | chunk seams; needs FluidAudio upgrade |
| B. Phonon 31m on FluidAudio | Apache-2.0 | 37 | no | about 20 ms, streaming | prosody does not carry across sentences | three weeks old; quality claims are the vendor's |
| C. Pocket TTS 100M on FluidAudio | CC-BY-4.0 (attribution) | about 26 | yes, native pack | 26 ms streaming in FluidAudio's benchmark | built for long text, session API | per-voice licences unverified; about 330 MB |
| D. Apple `AVSpeechSynthesizer` | system | only what the user downloaded | yes | instant | fine | the owner already rejected the system voice; top Siri voices appear closed to apps (Inferred) |
| E. Separate MLX runtime (`kokoro-ios`, `mlx-audio-swift`) | MIT/Apache | varies | varies | varies | varies | second runtime; `mlx-audio-swift` downloads at run time with no documented offline path |

Excluded: Supertonic-3 (the investigator found an OpenRAIL-M licence with pass-through use restrictions and an archived upstream; the pinned FluidAudio doc says Apache-2.0, so the licence is in conflict and unresolved), LuxTTS (GPL-derived phonemizer data), Chatterbox (slow or single voice), Piper (GPL), large LLM-based models (heavy, can hallucinate on long text).

### Recommendation

Keep FluidAudio as the single speech runtime and upgrade the pin to a tagged release. Do not choose the model on paper. Run one owner listening session with the same ten-minute English passage on three candidates: Kokoro v1.0 (two or three top-graded voices), Phonon 31m and Pocket TTS 100M. The design brief already makes the owner's ear the acceptance gate.

Expected outcome if the voices are judged equal: Kokoro v1.0. It has the most independent evidence, the cleanest licence and the smallest code change. Phonon or Pocket TTS wins only if the owner hears clearly better long-form flow, because both stream and would also simplify the playback code.

What would reverse this: a crash or instability of FluidAudio CoreML models on macOS 27.2.1, or the owner disliking all three. The fallback then is option E with weights bundled locally.

Pin by release tag and exact revision. The current pin tracks branch `main` (Local, `Package.resolved`), which is not reproducible.

## 2. Fully offline operation

### Current state

Models download from Hugging Face into `~/.cache/fluidaudio/Models` on first use. One optional lexicon file is outside the app's "installed" check and is re-requested on every chunk while missing (Local, baseline report section 7). The build allows outgoing network connections (Local, `Sotto.xcodeproj/project.pbxproj:269`).

### Options

| Option | Offline guarantee | Cost |
|---|---|---|
| 1. Keep run-time downloads, complete the file list | weak: any new FluidAudio fetch breaks it silently | low |
| 2. One explicit setup step that fetches a fixed, checksummed file list into the app's own Application Support folder, then never touches the network | strong if combined with 4 | medium |
| 3. Ship the model inside the app bundle | strongest, zero setup | app grows by roughly 100 to 350 MB; repository must not carry the weights |
| 4. Enforce it: enable App Sandbox without the network-client entitlement, or keep the app unsandboxed and add a test that fails on any socket | proof instead of promise | sandbox conflicts with Accessibility-driven capture (Inferred), so the test route is more realistic |

### Recommendation

Use option 2 for development and option 3 for any build handed to another person, with option 4's test in both cases:

- Pass FluidAudio an explicit `directory:` inside `~/Library/Application Support/<bundle id>/` so the app owns its model files and never shares `~/.cache`.
- Treat a file manifest (every model file, every offered voice pack, the lexicon) as the definition of "installed". Voice packs otherwise download on demand (Web).
- After setup, point FluidAudio's registry base URL at an unroutable address so an unexpected fetch fails fast and visibly instead of reaching the internet. `ModelRegistry.baseURL` is overridable (Local, `ModelRegistry.swift:32-37`).
- Add an automated check that runs a synthesis with the network denied and asserts success. This is the only real proof; no source confirms FluidAudio makes zero requests after install.

## 3. Selection capture

### Current state

`AXSelectedText` on the focused element, then synthetic Cmd+C with a 200 ms poll and clipboard restore (Local, `Sotto/Services/SelectionReader.swift:18-40`).

### Findings

- Chromium builds its accessibility tree only after a client sets `AXEnhancedUserInterface`, which has documented window-management side effects. Electron accepts the narrower `AXManualAccessibility` (Web).
- Safari often needs the WebKit text-marker attributes instead of `AXSelectedText` (Web, SelectedTextKit source and Easydict FAQ).
- Ghostty implements selected-text accessibility. Other GPU terminals reportedly expose none (Web for Ghostty, Inferred for the rest).
- Rex documents no accessibility support. It documents a `pane.copy` action that copies the selection to the clipboard, and no command that returns the selection directly (Web, Rex docs, partial read).
- Mature open-source tools (SelectedTextKit 2.6.7, MIT; Easydict) use this order: Accessibility, then pressing the app's own Edit > Copy menu item through Accessibility, then synthetic Cmd+C only when no Copy item exists. A disabled Copy item is read as "nothing selected" (Web).
- Clipboard-manager etiquette: mark the restore write with the `org.nspasteboard` transient and auto-generated types (Web).

### Options

| Option | Coverage | Clipboard risk | Maintenance |
|---|---|---|---|
| Keep Sotto's two steps | misses Safari marker ranges and Chromium trees; copy fallback fires often | highest | none |
| Own layered reader (AX variants, then menu Copy, then Cmd+C) | broad | low, and "no selection" becomes detectable | medium, about 300 lines |
| Adopt SelectedTextKit | same strategy, already written | same | dependency on a small project; it mutes alert volume and uses AppleScript for browsers, which adds an Automation permission prompt |

### Recommendation

Write Cáptalo's own layered reader, using SelectedTextKit as a reference, in this order:

1. Focused element: `AXSelectedText`, then `AXSelectedTextRange` with `AXStringForRange`, then the WebKit marker pair.
2. For Chromium and Electron apps only: set `AXManualAccessibility`, retry once. Never set `AXEnhancedUserInterface`.
3. Press the enabled Edit > Copy menu item via Accessibility. If the item is disabled, report "nothing selected" and stop.
4. Synthetic Cmd+C only when no Copy item exists: wait for the shortcut's modifiers to be released, require a `changeCount` change, restore with transient markers.
5. Never read the clipboard when it did not change.

Skip AppleScript browser access: it adds a third permission prompt and the owner wants minimal setup.

The cross-app matrix cannot be settled on paper. It needs a small probe tool run against Rex, Safari, Chrome, Firefox, Preview, a PDF, VS Code, Terminal, Ghostty, Word or Pages on this Mac, recording which step succeeded. That is the first implementation task, before any interface work.

## 4. Text cleanup

### Current state

Newlines become spaces, pronunciation rules apply, nothing else. Markdown symbols are spoken and structure is lost (Local, baseline report section 4; upstream issues 1 and 5).

### Recommendation

Add one pure, unit-tested text-preparation stage between capture and chunking. It is deterministic string processing with no model:

- Preserve paragraph and line breaks as pause boundaries instead of deleting them.
- Strip Markdown emphasis, heading marks, list bullets, link syntax (keep the label), code fences and table pipes; read table rows as short sentences.
- Collapse terminal noise: box-drawing characters, prompt symbols, ANSI remnants, long hashes and separators.
- Speak URLs as their host name only.
- Rejoin words hyphenated across line breaks (common in PDFs and OCR).

This stage is where the project's first real test suite belongs, with synthetic fixtures. The inherited Pronunciation screen and Stats page are candidates for removal under owner decision 2; a pronunciation list could live in a plain file if it is ever missed.

## 5. Chunking, long passages and audio devices

- Chunk size: FluidAudio exposes `phonemes(for:)` (Local, `KokoroAneManager.swift:191`). For Kokoro, measure the phoneme count of each chunk and split again above about 450, instead of trusting the 240-character heuristic. Streaming engines (options B and C) remove this problem.
- Memory: synthesize at most a few chunks ahead of playback (back-pressure) instead of the whole passage.
- Seams: keep sentence-boundary chunks and insert a short fixed pause; judge seams in the listening session.
- Devices: handle `AVAudioEngineConfigurationChange` by restarting the engine and resuming from the current chunk. Upstream tried a larger recovery layer and reverted it (Local, commit `30e0dfb`), so keep this minimal and test it by unplugging headphones mid-reading.
- Section tracking: track the audible chunk, not the last synthesized one, if any skip feature survives. Under decision 2 it probably does not.

## 6. Screen-region OCR

### Findings

- `SCScreenshotManager.captureImage(in:)` needs macOS 15.2 and takes a screen rectangle in points across displays (Local SDK header and Web).
- Every capture route, including the system `screencapture` tool, requires the Screen Recording permission. macOS 15 re-asks about monthly; the cadence on macOS 26 and 27 is not confirmed (Web for 15, unknown for later).
- `RecognizeDocumentsRequest` (macOS 26) returns paragraphs, lists and tables in a natural reading structure for 26 languages. `RecognizeTextRequest` (macOS 15) returns unordered lines that the app must sort. Both run fully on device (Web, Local SDK).
- VisionKit `ImageAnalyzer` also returns a transcript without a view (Web); its ordering is undocumented.

### Options

| Option | Reading order | Minimum macOS | Effort |
|---|---|---|---|
| `RecognizeTextRequest` plus own line sorting | app's responsibility | 15.0 | medium, fragile on columns |
| `RecognizeDocumentsRequest` | paragraphs and tables provided | 26.0 | low |
| `ImageAnalyzer` | undocumented | 13 | low, opaque |

### Recommendation

Set the deployment target to macOS 26 and use `RecognizeDocumentsRequest`. The owner always runs the latest macOS and has no interest in older versions, and structured paragraphs directly address the reading-order criterion. Capture with `captureImage(in:)`. Draw the drag rectangle on one borderless, non-activating panel per display so focus never leaves the source app, convert coordinates carefully (AppKit origin is bottom-left; capture expects top-left), and discard the image immediately after recognition. Feed the result through the same text-preparation stage as selections.

Reversal condition: if anyone the app is shared with needs macOS 15, fall back to `RecognizeTextRequest` on those systems.

## 7. App shell, shortcut and feedback

### Options for the shell

| Option | Visible surface | How to reach settings or quit |
|---|---|---|
| Sotto as is (Dock icon, menu-bar popover, Studio window) | high | menu bar |
| Agent app (`LSUIElement`), no status item | none while running | open the app again from Spotlight or Finder; this fires `applicationShouldHandleReopen` and shows one small settings window |
| Agent app plus status item | one icon | menu |

Apple's own engineer recommends the third option, so the second departs from common advice (Web). The owner explicitly asked for no menu bar, and the reopen path is standard, so the second option fits.

### Recommendation

- Agent app, no Dock icon, no status item. Launch at login through `SMAppService`.
- One small settings window, shown only when the app is opened again or when setup is incomplete. Contents: the two shortcut recorders (read selection, read region), voice picker with a sample button, speed, launch-at-login, permission status, quit.
- Shortcuts: adopt `KeyboardShortcuts` 3.1.0 (MIT). It provides the recorder, conflict warnings and storage, uses the same system call Sotto uses, and needs no permission (Web). This replaces Sotto's hand-written Carbon code and recorder.
- Controls without interface: pressing the read shortcut while speaking stops. Pressing it with a new selection replaces the reading. This already matches Sotto's behaviour and needs no pause button. Fix the toggle comparison noted in the baseline report.
- Feedback without windows: a short distinct sound for "nothing selected" and for "permission or voice missing", plus opening the settings window only for the second kind, because it needs action. The design brief requires feedback instead of silence.
- Stack: stay native Swift, SwiftUI for the one window, AppKit for the overlay. Move to Swift 6 language mode when convenient. No reason exists to change language or framework; every dependency (Accessibility, ScreenCaptureKit, Vision, CoreML) is native-only.

## 8. Identity, signing and permissions

### Findings

- A free Apple Account in Xcode gives a "Personal Team" and a stable Apple Development signing certificate, enough for an app that runs on the owner's own Mac (Web, Apple DTS).
- macOS ties Accessibility and Screen Recording grants to the bundle ID plus signing identity. Unsigned or ad-hoc builds change identity on every build, so grants are lost each time. The project's documented verification build uses `CODE_SIGNING_ALLOWED=NO`, which is fine for compile checks but cannot hold permissions (Web for the rule, Local for the build command in `AGENTS.md`).
- Sharing with other people without security warnings needs the paid Apple Developer Program (99 USD per year), a Developer ID certificate and notarization. Homebrew planned to disable casks that fail Gatekeeper in September 2026 (Web; whether that happened is unverified).
- No Info.plist usage string is needed for Accessibility or Screen Recording (Inferred).

### Setup steps for a first macOS app

Owner-only steps are marked. Everything else can be done by the agent after authorization.

1. **Owner:** in Xcode, Settings > Accounts, add your Apple Account (login and two-factor code). Free.
2. **Owner decision:** choose the bundle ID once, for example `com.<your-domain-or-handle>.captalo`. Changing it later resets all permissions.
3. Replace the inherited team `8P96S63H2N` and bundle ID `com.Shreysid.Sotto` in the project; select your Personal Team with automatic signing; keep Hardened Runtime on.
4. Rename project, target, scheme, product name, source folder, logger subsystem and display strings from Sotto to Cáptalo in one dedicated commit, keeping upstream `LICENSE` and notices. Replace the icon later.
5. Add `LSUIElement`, set the deployment target, remove unused capabilities.
6. Build signed and install one copy at a fixed path (for example `/Applications/Captalo.app`). Always run that copy so grants stay attached.
7. **Owner:** grant Accessibility and Screen Recording once in System Settings when the app asks.
8. Only if you decide to share it: **Owner** enrols in the Developer Program (paid), creates the Developer ID certificate and stores notarization credentials once; the agent then archives, notarizes and staples after explicit release authorization.

## 9. Development method (owner-accepted 2026-11-14)

The owner asked for an evaluation of Paul Solt's article "How I Build Apps With Codex Without Opening Xcode" (X post dated 2026-04-03, https://x.com/PaulSolt/status/2040132557983936772). x.com refused the fetch; the content was read as a summary through `api.fxtwitter.com` on 2026-11-14, so the details are paraphrased. The AppCreator skill itself was not inspected.

The method: a Makefile wraps the Xcode command-line build with `xcbeautify` output; `make` builds and relaunches the app; `make test` and `make ui-test` run tests; the agent writes fast unit tests and verbose logs; AGENTS.md carries strict rules; the agent reads local Apple documentation (DocSetQuery or sosumi.ai).

| Element | Disposition | Reason and adaptation |
|---|---|---|
| Makefile with `make`, `make test` | Adopt | One command for owner and agent. Wraps the build command already in `AGENTS.md`. |
| `xcbeautify` (https://github.com/cpisciotta/xcbeautify) | Adopt | Small open-source formatter; one-time Homebrew install, to be authorized in the plan. |
| Build-and-relaunch script | Adopt with a change | Must build signed and relaunch the single copy at a fixed path, or macOS drops the Accessibility and Screen Recording grants on every build (section 8). |
| Unit tests first, UI tests rarely | Adopt | Matches the text-preparation and chunking tests. The app has almost no interface, so UI tests matter little. |
| Verbose runtime logs | Adopt with a limit | Logs must never contain captured text or OCR output. Log counts, timings and which capture step succeeded. |
| Local Apple docs (https://sosumi.ai or https://github.com/PaulSolt/DocSetQuery) | Adopt | The macOS 26 APIs are newer than the assistant's training; this adds prose documentation to the installed SDK headers. |
| His AGENTS.md rules | Mostly already covered | RPI rules already cover verification honesty, destructive actions and commit discipline. Add one rule: no fallbacks without approval, one code path per action. |
| Steer by talking, light planning | Partial | Suits the listening test and per-app capture testing. Keep the RPI plan for foundation decisions. |
| AppCreator skill | Skip | Behind an email sign-up and overlaps with RPI. Only the Makefile idea is needed. |

Limit: the article's example is a game with a visible interface. Cáptalo's hard parts (permissions, other apps' behaviour, voice quality) cannot be checked by `make test` and still need the owner to listen and try real apps.

Owner disposition: accepted ("perfect"). The Makefile, `xcbeautify`, the docs tool and the "no fallbacks" rule belong in the first phase of the plan. Nothing is installed until that plan is approved.

### App Store Connect CLI (evaluated 2026-11-14, not part of the method above)

Source: Rudrank Riyam's post of 2026-11-01 announcing App Store Connect CLI 6.3.0 (https://x.com/rudrank/status/2116684860177961035, read through `api.fxtwitter.com`) and the repository main page (https://github.com/rorkai/App-Store-Connect-CLI, MIT, unofficial, not affiliated with Apple). The tool (`asc`) scripts the App Store Connect API: TestFlight uploads, App Store submission, metadata, signing profiles, Xcode Cloud. It needs an App Store Connect API key, which exists only with the paid Developer Program. Telemetry is on by default (`ASC_TELEMETRY_DISABLED=1` turns it off).

Disposition: do not adopt now.

- Cáptalo is not headed for the Mac App Store. The store requires App Sandbox, and the app reads other apps' selections through Accessibility and posts key events (Inferred that these cannot pass sandbox review). TestFlight, pricing and store metadata therefore have no use here.
- Notarization for direct sharing is covered by Apple's own `notarytool`. The post's "notary logs" feature would be a convenience only, and only after the paid enrolment.
- The post's headline claim, that Xcode can now store a project as JSON and the CLI can read and edit it, is not described in the README that was read and is unverified. If Xcode 27 does offer a JSON project format, it would make the Sotto-to-Cáptalo rename and later project edits safer for an agent than editing `project.pbxproj`. Verify this against the installed Xcode during planning, independently of this tool.

Revisit only if the owner later decides to distribute through TestFlight or the App Store.

Update, same day:

- JSON project format, checked locally in Xcode 27.0 (27A5218g). The binary `Xcode-beta.app/Contents/Frameworks/DevToolsCore.framework/Versions/A/DevToolsCore` contains a JSON project serializer (Swift symbols `XCProjectFormat.XCJSON.Encoder`, `.Decoder`, `.Printer`; source paths under `ProjectModel/DataModel/Containers/JSONFormat/` for `PBXProject`, `PBXTarget`, `PBXReference`, build phases and Swift package references), the file name `project.xcproj` next to `project.pbxproj`, and a project-format entry named "Xcode 27.0". So Xcode 27 does carry a JSON project format (Observed by `strings`). Not established: how a project is switched to it (no command-line converter was found in `Developer/usr/bin`), whether `xcodebuild` and Swift package resolution behave identically with it, and whether Xcode 26 can open such a project. No project was converted.
- Owner decision (2026-11-14): Cáptalo will be distributed through TestFlight and the App Store. This reverses the "do not adopt now" disposition's premise and makes the paid Developer Program and App Sandbox requirements central. The earlier statement that the app cannot pass the store was an inference and must be re-examined. A dedicated feasibility investigation was started; its result belongs in a follow-up section and may change sections 2, 3, 7 and 8.

## 10. App Store and TestFlight feasibility (added 2026-11-14 after the owner's distribution decision)

Evidence from a fourth delegated read-only investigation, pages opened 2026-11-14. This section supersedes sections 2, 3, 7 and 8 wherever they conflict for a store build.

### Findings

- App Sandbox is mandatory for the Mac App Store, and uploads without it fail validation (Web: App Review Guideline 2.4.5(i); Apple forum thread 836644, July 2026). TestFlight uses the same upload (Inferred).
- The Accessibility API does not work in a sandboxed app. Apple DTS, October 2025: "It's not possible to use the Accessibility APIs from a sandboxed app" (Web: forum threads 805556, 756130, 810677). This removes steps 1 to 3 of the capture order in section 3 from any store build.
- Synthetic key events (`CGEvent.post`) are technically sandbox-compatible according to Apple DTS (thread 789896), but App Review rejected several 2026 apps for it with "Accessibility features should not be used for non-accessibility purposes" (Web: thread 820594, March 2026; Whisper Notes and WhisperPad public accounts). Enforcement is inconsistent. One rejection was triggered by fallback code merely present in the binary.
- Precedent: PopClip, the closest selection utility, left the store in 2024 when sandboxing was demanded and never had a sandboxed edition (Web: popclip.app). Whisper Notes and WhisperPad now ship a reduced store edition plus a full edition distributed directly (Web).
- Likely fine in the sandbox: ScreenCaptureKit region capture with Vision OCR (precedent: TextSniper is on the store with drag-to-OCR and speech; its internals were not verified), global hotkeys through `KeyboardShortcuts` (its README states store compatibility), `SMAppService` launch at login as an explicit opt-in, general pasteboard reads and writes (Inferred; macOS may show a paste alert).
- Models: bundling up to 350 MB is allowed (limit is 200 GB). Downloading after install must disclose the size and ask first (Guideline 4.2.3(ii)); downloading from a third-party host carries medium review risk. Apple-hosted Background Assets are available for macOS 26 targets (Web). Bundling also gives the offline guarantee with no network entitlement at all, which the sandbox then enforces.
- Account: paid Developer Program, 99 USD per year. Individual enrolment shows the owner's legal name as seller. A privacy policy URL is required, also linked inside the app. On-device processing counts as "Data Not Collected" (Web).
- TestFlight for macOS: 100 internal testers, up to 10,000 external after a review of the first build, builds expire after 90 days (Web).

### Sandbox-compatible ways to receive selected text (Inferred, untested)

1. A macOS Services entry ("Read with Cáptalo"). The system passes the selected text of the frontmost app to the service, needs no Accessibility permission, and lets the user assign their own keyboard shortcut in System Settings. Coverage is limited to apps that support Services; Rex, Electron apps and some PDF viewers must be tested.
2. "Copy, then press the shortcut": the user copies and the app speaks the clipboard. This conflicts with the design brief's rule against reading unrelated clipboard content unless the read is strictly tied to the user's own key press.
3. Screen-region OCR, which works for everything visible.

### Options

| Option | Selection reading | Store risk | Effort |
|---|---|---|---|
| A. Store only, sandboxed | Services plus OCR only; no automatic capture in apps without Services | low | lowest; smallest product |
| B. Direct only (Developer ID, notarized) | full layered capture from section 3 | none; no store presence | low |
| C. Two editions from one codebase | store edition as in A; direct edition as in B | low, if capture code is compiled out of the store target | highest: two targets, two signing setups, two test matrices |

### Recommendation

Build the capture layer behind one interface from the start, with the Accessibility and key-event code in a separate module that the store target does not compile. First test, before anything else, whether the Services route alone is good enough in the owner's daily apps. If it is, ship option A and the project becomes simpler than planned (no Accessibility permission at all). If it is not, go to option C, using the direct edition daily and the store edition for distribution.

What would reverse this: Services proving unreliable in Rex and browsers pushes toward C; App Review rejecting a clipboard or Services design can only be learned by submitting a build.

### Owner decision (2026-11-14): option B, direct distribution only

After reviewing the findings above, the owner decided that Cáptalo will be distributed from the project's own website as a Developer ID signed, notarized download. The Mac App Store and TestFlight are not used. This replaces the earlier same-day statement that the app would go through TestFlight and the App Store.

What this settles:

- One edition, not sandboxed, with the full feature set. The layered Accessibility capture in section 3, the shell in section 7 and the offline approach in section 2 apply as written. No Services-only variant and no second build target are needed.
- Beta builds are shared as direct downloads. Sparkle remains optional for automatic updates.
- The paid Apple Developer Program (99 USD per year) is still required, because the Developer ID certificate comes only with it. Steps 1 to 7 of the setup list in section 8 can start on the free Personal Team; step 8 (enrolment, Developer ID certificate, notarization credentials) is needed before the first build is given to anyone else.
- The App Store Connect CLI in section 9 stays "do not adopt". Notarization uses Apple's `notarytool`.
- The "Consequences for earlier sections" list below describes a store build and no longer applies. It is kept as the record of why the store was not chosen.

Still open: the model can be bundled in the download or fetched once at setup (section 2); a bundled model gives a larger download and the simplest offline guarantee.

### Consequences for earlier sections (store build only, not chosen)

- Section 2 (offline): bundle the chosen model inside the app, or use Apple-hosted Background Assets. Do not download from Hugging Face in the store edition. Omit the network entitlement.
- Section 3 (capture): the layered Accessibility reader applies only to a direct edition.
- Section 7 (shell): launch at login must be an opt-in toggle. A background app with no menu-bar item was not checked against review practice.
- Section 8 (identity): the paid Developer Program is now required. The bundle ID must be registered, an App Store Connect record created, and Apple Distribution plus Mac Installer Distribution certificates issued. The App Store Connect CLI evaluated in section 9 becomes useful for uploads and TestFlight.

### Settled only by submitting a build

Whether `SCScreenshotManager` region capture and its permission prompt behave in a sandboxed TestFlight build; pasteboard alert behaviour; review's view of a Services-based reader and of bundled third-party model weights.

## Recommended direction in one view

| Area | Keep from Sotto | Change |
|---|---|---|
| Language and frameworks | Swift, SwiftUI, AppKit, AVAudioEngine | deployment target macOS 26; Swift 6 mode later |
| Speech runtime | FluidAudio | upgrade from the July pin to a tagged November release; model chosen by listening test (Kokoro v1.0 multi-voice, Phonon 31m, Pocket TTS) |
| Models on disk | none | app-owned folder, manifest, registry blocked after setup, network-denied test |
| Capture | AX first, clipboard restore idea | layered reader with menu Copy before Cmd+C; per-app probe first |
| Text | chunker's sentence logic | new preparation stage with tests; phoneme-aware limits; back-pressure |
| OCR | nothing exists | ScreenCaptureKit region capture plus `RecognizeDocumentsRequest` |
| Shell | hotkey concept, toggle-to-stop | agent app with no menu bar; one settings window; `KeyboardShortcuts`; remove Studio, Stats, popover |
| Identity | upstream licence and attribution | own bundle ID, team, name, icon |

## Counterevidence and uncertainties

- No independent numeric voice-quality ranking could be read. Phonon's advantage over Kokoro is vendor-reported. Only the listening test settles this.
- FluidAudio CoreML stability on macOS 27.2.1 is untested, and FluidAudio documents crash advisories for recent OS versions.
- No source proves zero network requests after install for any FluidAudio backend.
- Pocket TTS per-voice licences were not readable. Supertonic-3's licence is in conflict between two sources.
- Accessibility behaviour of Rex, Preview, Word, Pages, VS Code, Slack, Firefox and iTerm2 is unverified. Whether Rex's Edit > Copy menu item or Cmd+C reaches its `pane.copy` action is unknown.
- Whether Chrome honours `AXManualAccessibility` is unconfirmed.
- Screen Recording re-prompt cadence on macOS 26 and 27 is unconfirmed.
- Whether an agent app without sandbox can be forced offline by any means other than tests and a blocked registry URL is unexplored.
- Several model names and versions in section 1 postdate the assistant's own knowledge and rest entirely on the delegated investigator's page reads.

## Decisions needed from the owner

1. Bundle ID and whether you own a domain to base it on.
2. Free Personal Team now (app runs only on your Mac), or pay for the Developer Program now so the app can be shared.
3. Is macOS 26 as the minimum acceptable? It gives the better OCR.
4. Confirm the listening test: authorize a one-time download of three candidate models into a throwaway folder, then choose by ear.
5. Feedback style when nothing is selected: a soft sound, or complete silence.
6. Is Spanish reading wanted in the first version? It narrows the engine choice.
7. Drop Pronunciation and Stats screens entirely?

## Owner answers (2026-11-14)

These close the "Decisions needed from the owner" list above.

| Question | Answer |
|---|---|
| Distribution | Direct download from the project website, Developer ID and notarization. No App Store, no TestFlight (section 10). |
| Minimum macOS | macOS 26. `RecognizeDocumentsRequest` is the OCR path. |
| Listening test | Authorized: a one-time download of the three candidate models (Kokoro v1.0, Phonon 31m, Pocket TTS 100M) into a throwaway folder, then choice by ear. Not yet run. |
| Feedback when nothing is selected | Silence. No sound, no window. |
| Spanish in the first version | No. English only. This keeps Phonon 31m eligible. |
| Pronunciation and Stats screens | Remove both. |
| Model delivery | Bundled inside the app download. No run-time model download in the shipped app; the network-denied test in section 2 still applies. |
| Bundle ID | The owner owns `thecreativetoken.com`. Recommended bundle ID: `com.thecreativetoken.captalo` (owner confirmation of the exact string pending). |

Consequence of "silence": failures that need owner action (missing permission, missing or corrupt voice) still open the settings window, because silence there would leave the app unusable with no explanation. Only the "nothing selected" case is fully silent.

## Speech engine decisions after the listening tests (2026-11-14)

Evidence and the owner's verdicts per sample are in [the Qwen3-TTS research](2026-11-14-qwen3-tts-single-engine.md) and the sections below.

| Topic | Decision |
|---|---|
| Built-in voices | Kokoro v1.0 through FluidAudio, bundled in the app (92 MB measured). The owner found the Kokoro, Phonon and Pocket TTS presets all "very acceptable", accepted the Kokoro recommendation, and later confirmed `kokoro-af_heart` and `kokoro-af_bella` as "great". Phonon (`en_us_Zoey` was singled out as very good) stays the fallback if Kokoro shows chunk seams or latency problems. |
| Own-voice feature | New scope, added by the owner as a product differentiator: an optional mode that reads in a clone of the user's own voice. Engine: Qwen3-TTS 1.7B Base, 4-bit (2.34 GB), run locally, fed sentence by sentence with inserted pauses. The owner judged that configuration "good". The 0.6B model was judged "terrible". The model is an optional one-time download, not bundled. |
| Qwen3-TTS for built-in voices | Rejected. Its two English presets were judged "horrible" (Ryan) and "better, not the greatest" (Aiden), both male, in a 2.3 GB model. |
| ElevenLabs | Not used. Its instant clone on `eleven_v4_turbo` was judged "amazing", but clones cannot be exported or run locally, every reading is billed and sent to its servers, and serving other users requires a plan from 299 USD per month. The local Qwen3-TTS clone replaces it. |
| Other local cloning engines | Pocket TTS, StyleTTS2 and LuxTTS clones (FluidAudio) were judged not close enough; VoxCPM2 and LongCat-AudioDiT were tested and not chosen. |

Consequences: the app carries two speech runtimes (FluidAudio/CoreML for Kokoro, MLX for Qwen3-TTS). The Qwen3-TTS path has only been run through the Python MLX runtime on an M5 Ultra with 96 GB; a Swift build and a test on ordinary hardware are open items for the plan. The "bundled model, no run-time download" answer above applies to the built-in voices; the own-voice model is a disclosed, user-initiated download.

## Listening test samples (generated 2026-11-14)

Setup, all Observed in this session:

- FluidAudio v0.18.3 (`c8b41f98eae668794dd0083bbe028fe7e6585051`) cloned and built in `.local/listening-test/FluidAudio` (ignored by git).
- Build finding: v0.18.3 does not compile unmodified with Xcode 27.0 beta (27A5218g). Two errors in the LFM3Audio code that uses the new CoreAI framework (`NDArray.MutableRawView` has no member `withUnsafeMutableBytes`; mutating member on immutable value). In the scratch clone the four `canImport(CoreAI)` files were disabled, after which the command-line tool built. The plan must either use a newer Xcode or account for this when upgrading the FluidAudio pin.
- Models were downloaded into `.local/listening-test/home/.cache/fluidaudio` by running the tool with `CFFIXED_USER_HOME` and `HOME` redirected. The real `~/.cache/fluidaudio` still does not exist. Download size on disk: 1.4 GB for all three engines.
- Passage: a 190-word synthetic text (`.local/listening-test/passage.txt`) with numbers, technical terms and questions; each sample is about 62 to 72 seconds.
- All three engines synthesized the full passage in one call on macOS 27.2.1 with no crash. Kokoro accepted the long input without app-side chunking in this version. Rough wall-clock time per one-minute sample, including model load: Phonon 4 to 5 s, Pocket TTS 11 to 15 s. Kokoro's first run took 34 s including the model download; later Kokoro runs were not timed.

Samples in `.local/listening-test/samples/` (16 files):

- Kokoro v1.0: `af_heart`, `af_bella`, `am_michael`, `bf_emma`, `bm_george`
- Phonon 31m: `en_us_Easton`, `en_us_Zoey`, `en_us_Juniper`, `en_us_Miles`, `en_gb_Maeve`, `en_gb_Edwin`
- Pocket TTS 100M (`english_2026-10`): `alba`, `michael`, `jane`, `george`, `vera`

Limits: one-minute samples are a shortlist step, not the ten-minute acceptance criterion. No quality judgment was made by the assistant. The task-owned folder `.local/listening-test/` and everything in it was deleted on 2026-11-14 at the owner's request once the engine decisions were made; the paths in this section are historical.

## Sources (retrieved 2026-11-14 by delegated investigators unless marked Local)

- FluidAudio releases, docs and source: https://github.com/FluidInference/FluidAudio (v0.15.7 to v0.18.3; `main` at `16780f04`)
- Kokoro: https://huggingface.co/hexgrad/Kokoro-82M and its `VOICES.md`
- Pocket TTS: https://github.com/kyutai-labs/pocket-tts (v4.0.1), https://huggingface.co/kyutai/pocket-tts
- Phonon: https://huggingface.co/gradium/phonon-31m-en
- Supertonic: https://github.com/supertone-inc/supertonic
- Other runtimes: https://github.com/mlalma/kokoro-ios, https://github.com/Blaizzy/mlx-audio-swift, https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/kokoro.html
- Leaderboard post: https://huggingface.co/blog/open-tts-leaderboard
- Apple speech: https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoicequality, https://developer.apple.com/forums/thread/834149
- Chromium accessibility: https://www.chromium.org/developers/design-documents/accessibility/
- Electron accessibility: https://www.electronjs.org/docs/latest/tutorial/accessibility
- `AXEnhancedUserInterface` side effects: https://github.com/Hammerspoon/hammerspoon/issues/3224
- SelectedTextKit 2.6.7: https://github.com/tisfeng/SelectedTextKit ; Easydict FAQ: https://github.com/tisfeng/Easydict/wiki/FAQ
- Ghostty source: https://github.com/ghostty-org/ghostty
- Rex docs: https://www.superlogical.com/rex/docs/reference/mac-actions.md, https://www.superlogical.com/rex/docs/reference/cli.md
- Pasteboard markers: http://nspasteboard.org/
- Hotkeys: https://developer.apple.com/forums/thread/735223, https://developer.apple.com/forums/thread/763878, https://github.com/sindresorhus/KeyboardShortcuts (3.1.0)
- ScreenCaptureKit: https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager
- Screen Recording prompts: https://tidbits.com/2024/08/19/apple-reduces-excessive-sequoia-permission-requests-shifts-to-monthly
- Vision: https://developer.apple.com/documentation/vision/recognizedocumentsrequest, https://developer.apple.com/documentation/vision/recognizetextrequest, https://developer.apple.com/videos/play/wwdc2025/272/
- VisionKit: https://developer.apple.com/documentation/visionkit/imageanalyzer
- Signing and TCC: https://developer.apple.com/forums/thread/775605, https://developer.apple.com/forums/thread/705932, https://developer.apple.com/forums/thread/730043
- Notarization: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- Gatekeeper: https://support.apple.com/en-us/102445
- Bundle ID: https://developer.apple.com/documentation/xcode/changing-the-bundle-identifier
- Homebrew: https://brew.sh/2025/11/12/homebrew-5.0.0, https://brew.sh/2026/06/11/homebrew-6.0.0/
- Local: pinned FluidAudio checkout `5fc19fc` under `.local/setup/DerivedData/SourcePackages/checkouts/FluidAudio`; macOS 27.0 SDK in `/Applications/Xcode-beta.app`; repository sources cited in the baseline report.

## Handoff

- Objective: evaluative input for the first `rpi-plan`. Scope was read-only research plus this artifact.
- Baseline: `develop` at `5b1933f`, worktree `/Users/juan/code/captalo`; `.summon` modified before this session and preserved; both research artifacts are uncommitted.
- Delegations: three read-only web investigations (speech models; capture and shell; OCR and signing), all completed. Gaps they reported are listed under "Counterevidence and uncertainties".
- Checks: none run. No model was downloaded, no app launched, no permission changed.
- Resources: none allocated.
- Next: owner answers the seven decisions; then `/rpi-plan` in a new session, with the per-app capture probe and the voice listening test as the first two planned steps. Revalidate FluidAudio's latest release and the commit before relying on version facts here.
