# Plan: Cáptalo core reader

- Date: 2026-11-15. Revision 4 (same day), after [the plan assessment](../research/2026-11-15-core-reader-plan-assessment.md), its revision 2 re-review (V2-1 to V2-9) and its revision 3 re-review (V3-1 to V3-4).
- Workflow: `rpi-plan`. Planning only; no product code, dependency, download, signing or remote state was changed while writing it.
- Repository: `juan294/captalo`, branch `develop` at `362f9eaf2630feaa27d9bb5e71701fea79b7d06f`, worktree `/Users/juan/code/captalo`.
- Phase files: [phase 1](2026-11-15-captalo-core-reader-phases/phase-1.md), [phase 2](2026-11-15-captalo-core-reader-phases/phase-2.md), [phase 3](2026-11-15-captalo-core-reader-phases/phase-3.md), [phase 4](2026-11-15-captalo-core-reader-phases/phase-4.md), [phase 5](2026-11-15-captalo-core-reader-phases/phase-5.md).

## Objective

Turn the inherited Sotto fork into the Cáptalo core reader: select text in any app (or drag a rectangle around visible text), press a user-chosen shortcut, and hear it in a pleasant local Kokoro voice, fully offline, with no Dock icon, no menu-bar item and no floating window.

The optional own-voice feature ([own-voice brief](../research/2026-11-14-own-voice-brief.md)) is out of scope. It gets a separate plan after this one is accepted (owner decision, 2026-11-15).

## Controlling inputs

Read completely for this plan, all still valid against the worktree (`git diff 5b1933f HEAD -- Sotto Sotto.xcodeproj` is empty, checked 2026-11-15):

- [Briefing](../briefing.md), `AGENTS.md`, [design brief](../research/2026-11-13-captalo-brief.md), [setup handoff](../setup-handoff.md).
- [Inherited baseline](../research/2026-11-14-inherited-baseline-for-initial-plan.md), cited as "baseline §N".
- [Clean-eyes re-evaluation](../research/2026-11-14-clean-eyes-reevaluation-assessment.md), cited as "assessment §N".
- [Plan assessment](../research/2026-11-15-core-reader-plan-assessment.md), cited as "review RN". Its findings and their dispositions are in the table below.
- [Qwen3-TTS research](../research/2026-11-14-qwen3-tts-single-engine.md) and [own-voice brief](../research/2026-11-14-own-voice-brief.md): read for scope exclusion only.
- [Resource contract](../development/resource-lifecycle.md), [release playbook](../release/release-playbook.md), `.rpi/release-profile.json`, `.rpi/policy.json`, `.rpi/rules/testing.md`.
- Project overlay: `.rpi/project/rpi-plan.md` does not exist. No overlay or declared override applies.

## Decisions in force

From earlier owner decisions (not re-litigated here):

| Area | Decision | Source |
|---|---|---|
| Voices | Kokoro v1.0 through FluidAudio, bundled in the app, English only; `af_heart` and `af_bella` confirmed "great" | assessment, "Speech engine decisions" |
| Interface | Background agent app: no Dock icon, no pause/play UI, user-chosen shortcuts. One menu-bar icon opens the settings panel, which replaces the settings window (decision 12) | assessment, owner decisions 1-2 and §7; owner decision 12 |
| Feedback | Nothing selected: complete silence. Missing permission or voice: open the settings window | assessment, "Owner answers" |
| Screens | Remove Pronunciation and Stats | assessment, "Owner answers" |
| Capture | Layered reader: per-app probe first; AX variants, then the app's Edit > Copy menu item, then synthetic Cmd+C | assessment §3 |
| OCR | ScreenCaptureKit region capture plus `RecognizeDocumentsRequest` | assessment §6 |
| Platform | macOS 26 minimum; direct distribution, Developer ID, notarized, not sandboxed | assessment §10 owner decision |
| Models | Bundled inside the app download; no run-time download in the shipped app | assessment, "Owner answers" |
| Method | Makefile around `xcodebuild` with `xcbeautify`; signed build at one fixed path; unit tests first; local Apple docs; "no fallbacks without approval" | assessment §9 |

Owner decisions of 2026-11-15, first round:

1. Bundle ID: `com.thecreativetoken.captalo`.
2. FluidAudio build route: if the app cannot build with upstream `v0.18.3` as a dependency, fork to `juan294/FluidAudio`, branch from tag `v0.18.3`, patch only the CoreAI compile failure, and pin by exact revision. Upstream contribution is a separate later decision.
3. Own voice: a separate later plan.
4. Phase order: 1 Foundation and identity, 2 Capture, 3 Speech, 4 Shell, 5 Region OCR.

Owner decisions of 2026-11-15, second round (after review):

5. **Capture gate.** The mandatory apps are Rex, Safari, Google Chrome, Preview (selectable PDF), TextEdit and Microsoft Word. Each must read the exact fixture text. An unsupported mandatory app blocks phase 2 until the owner approves a recorded exception for that app. Ghostty, Terminal, Firefox, Visual Studio Code, Pages and Notes are recorded but do not block.
6. **Device change.** Playback restarts at the beginning of the unit that was playing: one sentence, or one bounded piece of a long sentence (at most 400 characters, see "Synthesis units" below). A few repeated words after a device change are accepted.
7. **Conservative cleanup.** Remove only markup and noise: Markdown symbols, ANSI codes, box-drawing, separator runs, line-start prompt symbols. URLs become host names (already accepted). Paths, code operators and hashes are spoken as written. Hyphen rejoining applies only to OCR text.
8. **Optional OCR setup.** Setup is complete with the voice, Accessibility and the read shortcut. Screen Recording and the region shortcut are optional rows, requested only when the user uses OCR.

Owner decision of 2026-11-15, third round (after re-review V2-2):

9. **Clipboard exception accepted.** The Copy layers stay, with every fence and check in phase 2. These races remain and are accepted as a known S3 limitation, recorded in the matrix document and in release notes when a release is planned: (a) a single foreign clipboard write within the 1 s Copy window can be spoken and then overwritten by the restore; (b) a foreign write in the instant between the final change-count check and the restore write is overwritten; (c) a source-app Copy that arrives after the 1 s window replaces the previous clipboard. Cáptalo never claims that the clipboard is always preserved.

Owner decision of 2026-11-19 (after the first signed-install check):

10. **Apps that hide their selection use a synthetic Copy (D31).** Rex is the main daily source of text. It reports an empty Accessibility selection and a disabled Edit > Copy item while text is selected, so decision 5's mandatory Rex row cannot pass under the "Copy needs evidence of a selection" rule. For the apps in `CopyPolicy.selectionHidden` (Rex only), an empty Accessibility answer is not evidence: capture skips the menu and sends one synthetic Cmd+C, with every phase 2 fence and the decision 9 exception. A posted key that changes nothing means nothing was selected, so, as in other apps, it stops a playing reading (the stop gesture); that answer comes after the modifier wait and the 1 s Copy window, and a Rex Copy that arrives after the window is lost and replaces the clipboard (decision 9c). Accepted side effect: the selected text passes through the clipboard for up to 1 s, so Universal Clipboard and clipboard-history apps can receive it. Release gate: a Claude Code output sample in Rex reads acceptably after cleanup (passed by the owner on 2026-11-20: a multi-line block with a list and code text), and the owner accepts the clipboard exposure (accepted by the owner on 2026-11-19).
11. **A blocked screenshot is reported at once (D34).** When the region screenshot itself does not arrive before the 10 s deadline (usually a macOS screen-access prompt waiting for an answer), the failure is `captureTimedOut`: the settings window opens and the optional OCR row asks the user to answer the prompt and press again. Recognition errors and slow recognition stay silent, as in "Unreadable OCR region".
12. **A menu-bar icon opens the settings panel (D36).** This replaces the earlier "no menu-bar item, no popover" decision: without a visible entry point the owner could reach the app only through Spotlight. The settings content moves unchanged from its window into a panel (an `NSPopover`) under a one-colour icon in the menu bar; the separate window is removed. A plain menu was rejected because it cannot record a shortcut. Every place in this plan that says the settings window opens now means this panel opens under the icon. Not added: a playing-state icon and a setting to hide the icon.

Owner decision of 2026-11-22:

13. **Initial shortcuts.** Read selection starts as Control-Option-S, Read region as Control-Option-A and Stop reading as Control-Option-X (`ShortcutBinding.initialReadSelection`, `.initialReadRegion` and `.initialStopReading`; Stop added the same day after the Stop plan landed). This replaces "no default" for the read shortcuts and "user-chosen" for the Stop shortcut in `2026-11-22-stop-reading.md`; Stop stays optional and outside setup. The library writes an initial shortcut only when the user has no stored value, so a recorded or cleared shortcut is kept, and the user can record any other shortcut. Reasons: Option with a key types a character (Option-[ types "[" on the Spanish ISO and Italian Pro layouts, checked with `UCKeyTranslate` on 2026-11-22); Command with a letter belongs to app menus; Control with a letter belongs to text editing and the terminal; Apple's shortcut list uses Control-Option without Command only with Space; Rectangle's defaults use Control-Option with C, D, E, F, G, I, J, K, R, T, U, =, −, Return, Delete and the arrows, not S, A or X. Known overlap: while VoiceOver is on, Control-Option is its modifier. Effects: on a first launch the read shortcut is already set, so setup needs only the voice and Accessibility; the region shortcut is set but Screen Recording is still requested only by a region press or the settings row (decision 8).

Decisions made by this plan from accepted research and the review (the owner can override them at acceptance):

- **Tests.** Pure logic goes into `Packages/CaptaloCore` (Swift Testing, `swift test`, no AppKit UI, no FluidAudio). The FluidAudio adapter and model store go into a second local package, `Packages/CaptaloSpeech`, so that the same production speech code runs in a Release-configuration probe executable (review R5). The app target holds only the AppKit, Accessibility, ScreenCaptureKit and Vision adapters. Adding local packages is a small edit, because the project uses `objectVersion = 77` with a synchronized root group (`Sotto.xcodeproj/project.pbxproj:6`, `:17-23`).
- **Clipboard ownership policy (review R1, V2-2).** Cáptalo attributes a pasteboard change to its own Copy only inside one fenced, bounded transaction (phase 2). When the checks detect a foreign or uncertain write, Cáptalo does not speak and does not restore. The checks cannot detect every race. The undetectable cases are the owner-accepted exception in decision 9.
- **Copy needs evidence of a selection (review R2).** A confirmed empty selection never falls through to Copy, except in the apps of decision 10. Apps documented to copy something with nothing selected (seeded with Visual Studio Code, `editor.emptySelectionClipboard`) are excluded from the Copy layers. Other apps' preferences are never changed.
- **Pending input and committed playback are separate (review R3, V2-3).** A press creates a pending input (selection capture or region selection plus OCR) that supersedes any older pending input. The playing session changes only when that input resolves: a successful capture or recognition replaces it, and the stop gesture stops it. Cancelled, empty, failed or timed-out inputs leave it untouched. Stale results and callbacks of either kind are dropped.
- **"Pause for voice apps" is removed** in phase 4. It is not in the accepted settings list (assessment §7), and silently stopping when Zoom or Slack comes to the front is a hidden behavior.
- **Unreadable OCR region** (no text, a Vision error or a timeout) is silent and leaves any playing reading untouched. It is logged without content. After three consecutive region failures (errors or timeouts, not empty regions), the optional OCR row in the settings window shows the failure category the next time the window is opened. No window opens automatically for this. Exception (decision 11): a screenshot that never arrived opens the settings window at once.
- **Stop gesture.** Pressing the read shortcut stops the current reading when the same text is still selected or when the selection is confirmed empty. A press with a new selection replaces the reading. A region press never stops a reading. Only successfully recognized text replaces it.
- **Speed** uses Kokoro's `speed:` parameter, and the inherited time-pitch unit is removed (one code path per action). A speed change applies from the next reading. The reading in progress keeps its speed.
- **Synthesis units (review R9, V2-5).** A unit is one sentence. A sentence longer than 400 characters is split at the last whitespace or pause punctuation before the limit, or at a grapheme-cluster boundary when an unbroken token leaves no other break. The first unit of a reading is capped at 160 characters for fast first audio. FluidAudio's own 510-phoneme auto-chunking still applies inside a unit. Every synthesized unit is checked at run time against a 35 s audio limit before playback. An oversize result is split and re-synthesized, and is never truncated. The audible unit plus 3 queued units therefore hold at most 140 s of resident playback PCM, about 13.4 MB of 24 kHz mono Float32. This is not a whole-process memory bound: phase 3's measured peak-memory gate covers that.
- **Bundled voice set.** At least `af_heart` (default) and `af_bella`, plus any other English Kokoro voice the owner accepts in phase 3. Changing the list invalidates the per-voice evidence.
- **Apple documentation** comes from https://sosumi.ai through web fetch, which needs no local install. Only public API names go into queries.

## Evidence gathered for this plan (VERIFIED 2026-11-15 unless marked)

- FluidAudio `v0.18.3` (2026-11-07) is still the latest release. `main` contains commit `5fff83ae`, which triggered a Swift 6.4 `-O` miscompile that drops the first and last word of each chunk in release builds, fixed later in `16780f04` (PR #1160). The tag predates `5fff83ae`. The local toolchain is Swift 6.4 (`swiftlang-6.4.0.25.4`).
- At `v0.18.3`, CoreAI is imported by four LFM3Audio files (GitHub code search). The compile failure was observed on 2026-11-14 in a CLI build (assessment, "Listening test samples"), not yet as an app dependency.
- At `v0.18.3` (sources read through `gh api`):
  - `KokoroAneManager.phonemes(for:)` is public (`KokoroAneManager.swift:349`). High-level `synthesizeDetailed` auto-chunks phonemes at `KokoroAneConstants.maxPhonemeLength` (`:294-330`). The class documentation states this split at whitespace and pause punctuation (`:15-25`).
  - `ensureEnglishLexicon` returns early when the file exists. Otherwise it fetches the file and, on any error, logs a warning and returns `nil` (`KokoroAneResourceDownloader.swift:415-444`). A failed download therefore does not fail synthesis.
  - Stages load with `MLModel(contentsOf:)` on `.mlmodelc` bundles (`KokoroAneModelStore.swift:165`, `:265`, `:504`).
  - `TtsCacheDirectory.ensure()` creates the shared cache directory (`TtsCacheDirectory.swift:23-41`). The inherited app calls it at `Sotto/Services/SpeechControllerKokoro.swift:11` (local July pin), reached from `Sotto/App/SottoAppStateKokoro.swift:6`.
  - Documentation: `directory:` holds every Kokoro file, voice packs are `[510, 256]` fp32 (about 0.5 MB), and the library runs Metal-free on macOS 27 (`Documentation/TTS/KokoroAne.md`, lines 13-31, 85-94, 422-431).
- Network oracles (run on this Mac):
  - `sandbox-exec` with `(deny network-outbound (with send-signal SIGKILL))` kills the process on any denied outbound attempt. This held for a direct IP connection, for a host-name lookup (curl exit 137) and for a Python process that caught and ignored its own failed request (killed, rc -9, its next line never ran). An explicitly allowed loopback port still works under the same profile.
  - A loopback HTTP recorder on the allowed port receives and logs requests, so it can confirm that the registry redirect is the only allowed route.
  - Sandbox denials did not appear in `log show` without extra privileges, so the system log is not an oracle.
  - Scope: the claim covers the probe process, which starts no child processes (asserted by the harness). Network work handed to another process (for example a background `URLSession` served by `nsurlsessiond`) is not covered. Phase 3 audits the pinned sources for such configurations.
- At `v0.18.3`, `synthesizeDetailed` collects every internal chunk result and concatenates them before returning (`KokoroAneManager.swift:294-320`), so one call's latency and memory scale with its input (review V2-5).
- PR #1135 (on `main`, after `v0.18.3`) adds an opt-in fp32 vocoder for robotic onsets on SME chips. This Mac is an M5 Ultra. This becomes a listening-check item.
- KeyboardShortcuts 3.1.0 and xcbeautify 3.2.1 are the latest releases. `xcbeautify` is not installed.
- 0 valid code-signing identities. Xcode 27.0 (27A5218g) is the only Xcode. macOS 27.2.1 on an M5 Ultra with 96 GB. Runtime behavior on macOS 26 is **unverified** and stays so in this plan.
- Installed matrix apps: Rex Beta, Safari, Google Chrome, Firefox, Preview, Visual Studio Code, Terminal, Ghostty, Pages, Microsoft Word, TextEdit, Notes.

## Architecture

```
Packages/CaptaloCore    (Swift 6, macOS 26; no AppKit UI, no FluidAudio)
  Request/  RequestCoordinator (generation tokens, cancellation)
  Capture/  CaptureCoordinator, CaptureLayer, SelectionEvidence, ClipboardTransaction, CopyPolicy
  Text/     TextPreparer (Block input), UnitChunker
  Reading/  ReadingSession, SynthesisScheduler (bounded lookahead), Synthesizer/AudioSink protocols
  Shell/    SetupState
  OCR/      RegionGeometry, DocumentTranscript
  Logging/  PrivacyLog (typed events)
Packages/CaptaloSpeech  (depends on CaptaloCore + FluidAudio pin)
  ModelStore (versioned, atomic install), KokoroSynthesizer, captalo-speech-probe (executable)
Captalo (app target)
  AX/menu/CGEvent layers, NSPasteboard, AVAudioEngine sink, KeyboardShortcuts,
  settings window, overlay panels, ScreenCaptureKit, Vision
```

`PrivacyLog` narrows leakage through Cáptalo's own logging, because its events accept only enums, counts and durations. It does not make dependency or system logging safe. Phase 1 adds a code-search audit for direct logging in the app, and phase 3 audits FluidAudio's log calls at the pin (review, smaller items).

## Review dispositions

| Finding | Disposition | Where |
|---|---|---|
| R1, V2-2 clipboard | Mitigated: fenced snapshot with stability check, recheck before Copy, single-change attribution, no speech and no restore when uncertain, scoped cleanup authority. Undetectable races remain: owner exception, decision 9 | Phase 2 |
| R2 Copy without a selection | Specified: `SelectionEvidence` separates confirmed empty from unavailable; Copy policy list; no-selection case in every matrix app | Phase 2 |
| R3, V2-3 request ownership | Specified: pending input separate from committed playback; source revalidated before key posts and pasteboard writes; modifier timeout means abort; region press never stops playback | Phases 2, 3, 5 |
| R4, V2-4 offline and download attempts | Specified, with stated scope: fresh store from the built app's bundle; warm and damaged stores; every voice; kill-on-deny sandbox as the attempt oracle (in-process scope); recorder for the registry route; positive and negative controls; source audit for out-of-process transports | Phase 3 |
| R5, V2-7 Release speech and completeness | Specified: Release-built probe on the production adapter; per-unit completion metadata; speech-recognition check calibrated with corrupted-audio controls and used as a gate only if it separates them; listening audit remains the completeness gate | Phase 3 |
| R6, V2-6 model store lifecycle | Specified: versioned store; staging plus atomic activation; quarantine-and-replace repair with rollback; reader leases; retention of current, previous and leased versions; interrupted, disk-full, concurrent, upgrade-during-playback and failed-activation tests | Phase 3 |
| R7 shared cache and real preferences | Specified: no "must not exist" gate; isolated HOME for probes; before/after record of the real shared cache; disposable defaults suites; export and restore for the fixed-identity check; install ownership record | Phases 1, 3, 4 |
| R8, V2-8 matrix | Specified: whitespace-normalized fixture equality inside the probe; mandatory set with owner waiver (decision 5); representation-preserving clipboard check; phase 2 stop routing uses a labelled silent playback seam, and audible stop and replace are repeated in phase 3 | Phases 2, 3 |
| R9, V2-5, V3-1 performance bounds | Specified: bounded units (400 characters, 160 for the first, hard split for unbroken tokens) and lookahead; 35 s run-time result check with split and re-synthesis; resident-PCM bound labelled as such; long-unpunctuated fixture; stop and plateau tests; thresholds with an owner verdict | Phase 3 |
| R10, V2-9 OCR lifetime | Specified: overlay feasibility gate; content-filter exclusion; native cancellation probe; OCR slot held until the worker ends; caller timeout separate from worker lifetime; teardown on every path | Phase 5 |
| R11 shortcut and login promises | Specified: identical bindings rejected; registration result checked at phase entry, with disclosure where the library gives no signal; login-item approval states | Phase 4 |
| R12, V2-1, V3-4 signing and install | Specified: build-info generated before signing; staged copy verified, then a replace (never merge) of the recorded install with rollback; Debug and Release installs; grant survival tested in phases 2 and 5 | Phases 1, 2, 5 |
| V3-2 cancelled input before Copy | Specified: input currency checked on lock acquisition and right before Copy; cleanup authority unchanged after Copy | Phase 2 |
| V3-3 OCR slot admission | Specified: slot reserved atomically before capture, released on capture failure, token rechecked before Vision | Phase 5 |
| Store consumer scope | Specified: one consumer process per store root through a lifetime lock; leases in-process only | Phase 3 |
| Device-change replay | Owner decision 6 | Phase 3 |
| Speed change timing | Plan decision: next reading | Phase 3 |
| Lossy cleanup | Owner decision 7; negative fixture per rule; owner intelligibility verdict | Phase 3 |
| OCR table flattening | Specified: OCR produces structured `Block`s before cleanup | Phases 3, 5 |
| OCR setup in readiness | Owner decision 8 | Phases 4, 5 |
| `PrivacyLog` overclaim | Specified: wording narrowed; log audits added; a stop-and-decide path if FluidAudio logs content and cannot be silenced | Phases 1, 3 |
| Verification runner drift | Specified: each phase updates `make verify` and `.rpi/policy.json` together; capture probes rerun after phase 4 | All |
| Fork before reproduction | Specified: reproduce as an app dependency first; fork only on failure | Phase 3 |
| macOS 26 runtime | Recorded as unverified | This section |
| Smaller re-review items (marker types, snapshot budget, defaults restore, repeated OCR failure) | Specified | Phases 2, 4, 5 |

"Specified" means the plan now defines the contract and its test. None of these is verified until the phase implements and passes it.

## Phase overview

| Phase | Outcome | Owner-only prerequisites | Batch-eligible units |
|---|---|---|---|
| [1 Foundation and identity](2026-11-15-captalo-core-reader-phases/phase-1.md) | Cáptalo name and bundle ID, macOS 26, Personal Team signing, Makefile, `CaptaloCore`, fixed install with ownership record, verification policy | Add Apple Account in Xcode; approve `brew install xcbeautify` | none |
| [2 Capture](2026-11-15-captalo-core-reader-phases/phase-2.md) | Request coordinator, layered reader with selection evidence and clipboard transaction; exact-text matrix | Grant Accessibility once; perform matrix selections; decide any waiver | none |
| [3 Speech](2026-11-15-captalo-core-reader-phases/phase-3.md) | FluidAudio pin (fork only if needed), `CaptaloSpeech`, versioned bundled store, offline and no-download proof, Release completeness probe, cleanup, bounded session, device recovery, accepted listening and performance | Confirm fork write only if reproduction fails; approve model and test-ASR downloads; listen; accept performance numbers | 3A text preparation; 3B pin, store and probe |
| [4 Shell](2026-11-15-captalo-core-reader-phases/phase-4.md) | Agent app, one settings window, KeyboardShortcuts, removals, login item, Swift 6 | Record shortcuts | none |
| [5 Region OCR](2026-11-15-captalo-core-reader-phases/phase-5.md) | Overlay feasibility gate, filtered capture, `RecognizeDocumentsRequest`, structured transcript, teardown and bounds | Grant Screen Recording when first used; judge OCR order | 5A overlay and geometry; 5B OCR adapter and transcript |

Phases run and are accepted in order, with the atomic loop (implement, independent review, repair, simplify, verify) in isolated worktrees and local integration into `develop`. No working branch is pushed and no PR is created. Only the integration owner runs `make install` (the fixed path is a shared resource, review R7). Batch implementers run tests and unsigned builds only.

## Verification

Sequential, with the first failure preserved. `make verify` returns failure if any step failed, and `.rpi/policy.json` lists the same steps. Each phase that adds a step updates both in the same commit.

1. `git diff --check 30e0dfbf2cfbef01b8c462bfec2452b3c0295a61`
2. `python3 .rpi/scripts/rpi-distribution.py check --source /Users/juan/code/cc-rpi --target "$PWD" --harness both --route direct`
3. `swift test --package-path Packages/CaptaloCore` and the same with `-c release`
4. `xcodebuild … -configuration Debug CODE_SIGNING_ALLOWED=NO build` and the same for `Release`
5. From phase 3: `swift test --package-path Packages/CaptaloSpeech` (debug and release), `make bundle-check`, `make offline-test` (Release probe), `make completeness-test` (Release probe plus speech-recognition round trip)
6. From phase 5: `make ocr-probe`

Runtime evidence records the candidate commit, the app's `CFBundleVersion` plus build-info commit, and the `codesign` designated requirement. A compile pass does not prove capture, voice, offline or permission behavior.

## Stuck states and recovery

| State | Who sees what | How it ends | Test |
|---|---|---|---|
| No signing identity (phase 1) | `make install` stops: "No Apple Development identity. Add your Apple Account in Xcode > Settings > Accounts, then run make install again." | Owner adds the account | `Scripts/signing-identity` test with captured `security find-identity` output "0 valid identities found" exits 2 with the message |
| Accessibility not granted | Settings window opens with the permission row and its button | Detected on activation or by the window's poll; no restart | `SetupStateTests.untrustedRequiresAccessibility`; manual deny-then-grant |
| Confirmed empty selection | Silence; clipboard untouched; a playing reading stops (stop gesture). In a decision 10 app (Rex), the answer comes from one Cmd+C that changes nothing, after the modifier wait and the 1 s Copy window | Next press | `CaptureCoordinatorTests.confirmedEmptyNeverReachesCopy`, `hiddenSelectionWithNoCopyResultIsNothingSelected` |
| Clipboard not preservable (snapshot too large, slow or failing) | Silence; no Copy is sent | Next press; recorded per app in the matrix | `ClipboardTransactionTests.unpreservableSnapshotAbortsBeforeCopy` |
| Clipboard ownership uncertain (detected) | Silence; the newer clipboard content is kept | Next press | `ClipboardTransactionTests.secondChangeMeansUncertainNoSpeakNoRestore`, `writeDuringSnapshotAborts` |
| Clipboard restore fails | Silence; the clipboard is left empty, because NSPasteboard clears before it writes (corrected during implementation, notes D7) | Next press. The limitation is recorded under decision 9 | `ClipboardTransactionTests.restoreFailureDoesNotSpeak` |
| Shortcut modifiers still held after 500 ms | Silence; no Cmd+C posted | Next press | `CaptureCoordinatorTests.modifierTimeoutAbortsSyntheticCopy` |
| Source app changed before Copy | Silence; no key event or menu press reaches the new app | Next press | `CaptureCoordinatorTests.sourceChangedBeforeCopyAborts` |
| Mandatory matrix app unsupported | Phase 2 cannot be accepted | Owner approves a recorded waiver, or capture work continues | Matrix evidence gate |
| Model store damaged or incomplete | Settings window: "Voice files are damaged. Reinstall voice." The button reinstalls from the app bundle | Reinstall; if the bundle itself fails validation: "Reinstall Cáptalo" | `ModelStoreTests.damagedStoreRefusesBeforeEngine`, `repairReinstallsFromBundle` |
| Model install interrupted | Next launch finds the staging folder | Staging removed, install retried automatically | `ModelStoreTests.interruptedStagingIsRemovedAndRetried` |
| Not enough disk space for install | Settings window: "Cáptalo needs N MB free to install its voice." Retry button | User frees space and retries | `ModelStoreTests.diskFullReportsNeededSpaceAndLeavesNoStaging` |
| Synthesis fails mid-reading | Scheduled audio finishes, then the reading ends; settings window shows "The last reading stopped because of a voice error." | Next press starts a fresh reading | `ReadingSessionTests.chunkFailureEndsSessionAndReportsVoiceError` |
| Unexpected network attempt | No user-visible state in a correct build. In development, the kill-on-deny sandbox kills the probe and `make offline-test` fails | Fix in development | Probe exit status; positive control must be killed |
| Audio device change | Playback restarts at the beginning of the current unit on the new device | Automatic | `ReadingSessionTests.deviceChangeReplaysCurrentUnitOnly`; manual unplug |
| No read shortcut recorded | Settings window opens at launch | Recording one completes setup | `SetupStateTests.missingReadShortcutRequiresSetup` |
| Shortcut does not register or conflicts with another app | If 3.1.0 reports registration failure: the row says "This shortcut could not be activated; choose another." If it does not: the row says "If this shortcut does nothing, another app may use it; choose another." | User picks another | Phase 4 entry probe decides which; `ShortcutValidationTests.identicalBindingsRejected` |
| Launch at login needs approval | Settings row: "Approve Cáptalo in System Settings > Login Items", with a button that opens that pane | User approves; the row updates on the next status read | `LoginItemStateTests` over each `SMAppService.Status` value |
| App running in the background (no Dock icon) | Only the menu-bar icon | A click on the icon, or opening Cáptalo from Spotlight or Finder, shows the settings panel with Quit (decision 12) | Manual, phase 4 |
| Screen Recording not granted (optional feature) | On a region press: no rectangle; settings window opens on the Screen Recording row. A selection-only user never sees it | Grant; if macOS needs a relaunch, the row says so and offers "Quit and reopen" | `SetupStateTests.screenRecordingIsOptionalButRequestedOnRegionPress`; manual |
| Region cancelled, empty, failed or timed out | Overlay closes; focus returns to the source app; silence; a playing reading continues. A screenshot that never arrived opens the settings window with the prompt notice (decision 11) | Immediate | `RegionPendingTests.cancelAfterLookaheadLeavesSessionComplete`, `RegionReaderTests.everyExitPathTearsDown`; manual Esc |
| OCR worker still running after the caller's timeout | Silence; further region presses are silent until the worker ends | Automatic when the worker returns. After three consecutive recognition failures, the optional OCR row shows the failure category; a screenshot that never arrived shows at once and opens the settings window (decision 11) | `RegionReaderTests.slotHeldUntilBlockedWorkerReturns` (deterministic blocked recognizer) |
| Display configuration changes during a drag | Overlay closes as a cancel | Immediate | `RegionOverlayTests.screenChangeCancels` (notification-driven) |

## Consumer sweep

Commands run on 2026-11-15 from the repository root: `grep -rn "<symbol>" Sotto` for each symbol below.

| Changed contract | Callers and writers found | Disposition |
|---|---|---|
| `SelectionReader.read() -> String?` becomes `CaptureCoordinator.capture(token) -> CaptureOutcome` | `Sotto/App/SottoAppState.swift:34`, `Sotto/App/SottoAppStatePlayback.swift:25` | Phase 2 |
| `speakSelection()` (untracked `Task` at `Sotto/App/SottoAppStatePlayback.swift:13`) | `Sotto/UI/MenuBar/SottoMenuBarView.swift:101`, `Sotto/App/SottoApplicationDelegate.swift:157`, definition `:4` | Phase 2 (request token); phase 4 removes the menu-bar caller |
| `SpeechChunker.chunks(from:)` | `Sotto/Services/SpeechControllerSynthesis.swift:13` | Phase 1 moves it with characterization tests; phase 3 replaces it with `UnitChunker` |
| `SpeechController.speak/stop/isReading` | `Sotto/App/SottoAppStatePlayback.swift:26`, `:31-32`, `:42`, `:75` | Phase 3 |
| `KokoroAneManager(defaultVoice:)` | `Sotto/Services/SpeechController.swift:7`, `Sotto/Services/SpeechControllerKokoro.swift:48`, `:70` | Phase 3 (moved into `CaptaloSpeech`) |
| `TtsCacheDirectory.ensure()` (writes the shared cache) | `Sotto/Services/SpeechControllerKokoro.swift:11`, reached from `Sotto/App/SottoAppStateKokoro.swift:6` | Phase 1 records the before and after state; phase 3 removes the call |
| `GlobalShortcut` and defaults key `globalShortcut` | `Sotto/Models/GlobalShortcut.swift`, `Sotto/UI/Studio/ShortcutRecorder.swift:6`, `:23`, `:29`, `:58`, `Sotto/UI/Studio/SottoStudioSettingsView.swift:117`, `Sotto/App/SottoAppStateSettings.swift:15-19`, `Sotto/App/SottoAppState.swift:29`, `:40`, `:51-52`, `Sotto/App/SottoApplicationDelegate.swift:103` | Phase 4 |
| Defaults keys `speech.pronunciationRules`, `stats.wordsSpoken`, `totalDictationSeconds` | `Sotto/App/SottoAppState.swift:11-13`, `:46-47`, `Sotto/App/SottoAppStatePronunciation.swift:46`, `:61`, `Sotto/App/SottoAppStatePlayback.swift:130`, `Sotto/App/SottoAppStateStats.swift:9` | Phase 4 removes the writers. Any values written to the new domain in phases 1-3 stay, unused. The upstream `com.Shreysid.Sotto` domain is never touched |
| `pauseForVoiceApps` | `Sotto/UI/Studio/SottoStudioSettingsView.swift:13`, `:74-76`, `Sotto/App/SottoAppStateSettings.swift:29-35`, `Sotto/App/SottoAppState.swift:18` | Phase 4 |
| `KokoroInstallationState` | `Sotto/App/SottoAppState.swift:25`, `Sotto/Models/KokoroInstallationState.swift:1` | Phase 3 (`VoiceInstallState`) |
| `SottoStudioWindowController`, `MenuBarExtra`, `setActivationPolicy(.regular)` | `Sotto/App/SottoApplicationDelegate.swift:9`, `:14`, `:43-61`, `:81`, `Sotto/App/SottoApp.swift:13` | Phase 4 |
| Commands naming `Sotto.xcodeproj` | `.rpi/policy.json`, `AGENTS.md` (Verification), `README.md:27-28`, `docs/development/resource-lifecycle.md` | Phase 1 |

There are no test fixtures, E2E helpers or scripts in the repository today (baseline §10).

## Out of scope

Own voice (separate plan); Developer Program enrollment, Developer ID, notarization, website, Sparkle and any release; the release evidence analyzer (first-release plan); a new icon and marketing assets; languages other than English; macOS 26 hardware testing; contributing patches upstream.

## Durable handoff

- Objective and scope: this plan only. Accepting it authorizes phase 1 implementation in a new session. Each later phase has its own acceptance gate. The phase 3 fork write needs confirmation at that point, and only if reproduction fails. No release, publication, signing-account change or push of `develop` follows from acceptance.
- Base: `develop` at `362f9eaf2630feaa27d9bb5e71701fea79b7d06f`, `origin/develop` equal; `main` and `origin/main` at `30e0dfb`. Uncommitted at revision time: these six plan files and the review assessment.
- Overlay: none. Delegation: none in this revision. The review's two independent investigations are recorded in its own document.
- Review status: revision 4 makes the four localized corrections of the revision 3 re-review (V3-1 to V3-4), its two scope clarifications (single store consumer, no probe children) and its two label fixes. The reviewers asked for a localized check of these edits only, before owner acceptance. That check found no blocking issue (assessment, "Revision 4 localized check"). Owner acceptance is the remaining gate.
- Acceptance: the owner accepted revision 4 on 2026-11-15. This authorizes phase 1 implementation in a fresh session under the entry conditions below. It grants no push, release, signing-account change or later-phase acceptance.
- Evidence limits: versions are as of 2026-11-15 and must be rechecked at each phase entry. The FluidAudio compile failure has not yet been seen as an app dependency. No app was launched, and no permission, voice or OCR behavior was observed. macOS 26 runtime is unverified.
- Resources: none allocated by planning. The scratch FluidAudio source copies and the short sandbox and recorder experiments are in the session scratchpad; the recorder processes have been stopped. These are not project resources. Setup's `.local/setup/DerivedData` (931 MB) becomes stale after the phase 1 rename. Removing it needs authorization at phase 1 acceptance.
- Next: owner acceptance of revision 4, then `/rpi-implement` phase 1 in a fresh session. Phase 1 entry: plan accepted; Apple Account added in Xcode (otherwise phase 1 stops at signing and says so); `brew install xcbeautify` approved.
