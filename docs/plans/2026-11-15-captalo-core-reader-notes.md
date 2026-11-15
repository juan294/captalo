# Notes: Cáptalo core reader implementation

Plan: `2026-11-15-captalo-core-reader.md` (revision 4, accepted 2026-11-15). Implementation session of 2026-11-15, `/rpi-implement` with the owner instruction "all phases, no stopping, when you're done merge to develop and prune the tree(s)".

- Worktree: `/Users/juan/code/captalo-core-reader`, branch `feat/core-reader`, created from `develop` at `5788d4c`.
- Overlay: `.rpi/project/rpi-implement.md` does not exist. No overlay or declared override applies.
- Authority: local commits and a local merge into `develop` only. No push, PR, release, signing-account change or publication.

## Deviations

### D1. Signing identity not created (phase 1, task 6)

- Plan said: `make signing-setup` runs the first automatic-signing build with `-allowProvisioningUpdates`, which creates the Apple Development certificate for the Personal Team; then `make install` and first launch.
- Found: `security find-identity -v -p codesigning` reports 0 valid identities. No local provisioning profile or Xcode preference names the Personal Team ID (the only profiles on disk are expired 2016 profiles of another organization). The session's permission classifier denied the `xcodebuild -allowProvisioningUpdates` call as an account-changing action.
- Chose: implement `make signing-setup` (accepts `TEAM=<id>`), `Scripts/signing-identity` and `Scripts/install` completely, test them with captured output and temporary directories, leave `DEVELOPMENT_TEAM` empty, and do not install or launch.
- Why: creating a certificate in the owner's Apple account is an account change that needs the owner's explicit go-ahead in this session. Everything that depends on the fixed signed install (task 6, the manual criteria, permission survival in phases 2 and 5, the matrix, listening) stays pending until the owner runs `make signing-setup TEAM=<Personal Team ID>` or authorizes it.

### D2. Build-info inputs come from `make` (phase 1, task 4)

- Plan said: a Run Script phase writes `build-info.json` (commit, dirty flag, configuration, UTC time) into Resources before signing.
- Found: the target enables `ENABLE_USER_SCRIPT_SANDBOXING`, and a sandboxed script cannot read the Git directory (a worktree's `.git` also points outside the source root).
- Chose: `make` passes `CAPTALO_COMMIT` and `CAPTALO_DIRTY` as build settings; `Scripts/write-build-info` declares its script input and output and stays sandboxed. A plain `xcodebuild` call outside `make` records `"commit": "unknown"`. The install record takes commit and dirty flag from the installed bundle's `build-info.json` only.
- Why: one source for the installed commit, with script sandboxing kept on (the first candidate turned sandboxing off; the simplify pass replaced that).

### D2a. `make install` reuses `make build` (phase 1, task 4)

- Plan said: `make install` resolves the identity, builds signed, stages, verifies and replaces.
- Chose: `make install` runs `signing-check` (`Scripts/signing-identity`), then the same `build` recipe as `make build CONFIG=…`, then `Scripts/install --app <built app>` for staging, verification, replacement and the record. Install state (record, staging, rollback copy, install logs) lives in the main checkout's `.local/build/`, found through the Git common directory, so every worktree sees one record.
- Why: one build definition (simplify review), and one install record for the one fixed path (phase 1 review, finding 6).

### D3. RPI installation update to v2.2.0 (verification step 2)

- Plan said: step 2 is `rpi-distribution.py check`.
- Found: the check failed on `develop` before any change, because the local cc-rpi source moved to v2.2.0 (`4325825`) while the installation recorded v2.1.0.
- Chose: a reviewed update plan whose only operations were `.rpi/distribution.json`, `.rpi/manifest.json` and one new baseline, applied as its own commit (`7f7737a`).
- Why: the gate must pass, and the update changes no skill, rule or instruction body.

### D4. Removed tracked upstream `xcuserdata` (phase 1, task 1)

- Found: `Sotto.xcodeproj/xcuserdata/shreysid.xcuserdatad/…/xcschememanagement.plist` was tracked although `.gitignore` excludes `xcuserdata/`.
- Chose: delete it in the rename commit. Added `__pycache__/` to `.gitignore` for the script tests.

### D5. Pasteboard calls stay on the main actor (phase 2 design)

- Plan said: the clipboard transaction runs off the main thread where the pasteboard API permits, checked against Apple documentation.
- Found: the NSPasteboard, `changeCount` and `NSPasteboardItem.data(forType:)` pages (sosumi.ai mirror, read 2026-11-15) say nothing about threads, and nothing about promised-data blocking or failure.
- Chose: the transaction's pasteboard calls run on the main actor; waits are non-blocking `Task.sleep` polls.
- Why: without documented permission, the conservative reading is main-thread use. A synchronous promised-data provider can still block the main thread during the snapshot; the elapsed-time check after materialization aborts such snapshots before Copy, and the matrix records provider time.

### D6. Plan verification step 3 needs `DEVELOPER_DIR`

- Plan said: `swift test --package-path Packages/CaptaloCore`.
- Found: the machine's developer directory is Command Line Tools, whose SwiftPM cannot resolve `.macOS(.v26)`.
- Chose: the Makefile exports `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` (overridable); policy steps call `make test-core-debug` and `make test-core-release`.

### D7. A failed clipboard restore leaves the clipboard empty (phase 2)

- Plan said: stuck-state row "Clipboard restore fails: the clipboard holds the source app's copied text".
- Found: NSPasteboard requires `clearContents()` before `writeObjects`, so when the restore write fails the clipboard is already empty (phase 2 review, finding 6).
- Chose: keep one restore path (clear, then write) and correct the plan's stuck-state row; `restoreFailureDoesNotSpeak` now models the clear and asserts the empty clipboard.
- Why: there is no API that replaces pasteboard contents atomically. This case is silent and logged (`PrivacyLog.restoreFailed`); it stays within the accepted clipboard limitation (decision 9).

### D8. Chromium retry re-queries the focused element (phase 2)

- Plan said: set `AXManualAccessibility` once per app launch, retry step 1.
- Chose: after the write, re-query the focused element up to 5 times, 40 ms apart (200 ms bound), and probe it each time.
- Why: Chromium builds its tree asynchronously; the element captured before the write may not expose the selection (phase 2 review, finding 4, inferred). The once-per-PID rule is unchanged.

### D9. FluidAudio pin: local patched branch instead of a pushed fork (phase 3, unit 3B)

- Plan said (owner decision 2): if upstream `v0.18.3` does not build as an app dependency, fork to `juan294/FluidAudio`, branch `captalo/v0.18.3-xcode27` from the tag, patch only the CoreAI failure, push, and pin by exact revision; the fork write needs the owner's confirmation in the session.
- Found: reproduced as an app dependency with Xcode 27.0 (27A5218g): two errors, both in LFM3Audio CoreAI files: `LFM3AudioCoreAIBackbone.swift:228` (`NDArray.MutableRawView` has no `withUnsafeMutableBytes`) and `LFM3AudioCoreAIDepthDecoder.swift:76` (mutating `withUnsafeMutablePointer` on an immutable view). The SDK's `MutableRawView.mutableBytes` (`MutableRawSpan`) and a `var` view fix both; no Kokoro file changes.
- Chose: the same branch and patch, built locally and reproducibly: `Patches/fluidaudio-v0.18.3-xcode27.patch` (committed), `Scripts/prepare-fluidaudio` (clones the tag, checks `c8b41f98`, applies the patch, commits with a fixed author and date), pinned commit `6fe650eb55641f408b2369ac792a3255de2789e3` recorded in `Patches/fluidaudio-v0.18.3-xcode27.commit`. `Packages/CaptaloSpeech` depends on `.local/vendor/FluidAudio` by path; the app no longer depends on FluidAudio directly.
- Why: the push to a new GitHub fork is an outward-facing write that was not confirmed in this session. The local route keeps the exact patch and revision reviewable. Moving to the fork later: create `juan294/FluidAudio`, push `.local/vendor/FluidAudio` branch `captalo/v0.18.3-xcode27` (same commit hash), and change the CaptaloSpeech dependency to `.package(url: …, revision: "6fe650eb…")`. Owner decision needed.

### D10. Pronunciation rules and word statistics are no longer applied (phase 3)

- Plan said: phase 4 deletes the pronunciation and Stats code.
- Chose: phase 3 no longer applies pronunciation rules to speech or counts words; the inherited screens remain until phase 4 deletes them.
- Why: the reading pipeline is built off the main actor from the captured text; the inherited rules live in main-actor UI state that phase 4 removes. Carrying them for one phase would add a second text path.

### D11. Speech-recognition calibration not run (phase 3, unit 3D)

- Plan said: the test-only recognizer download needs its own approval after its size is shown; without it, the check is recorded as not run.
- Chose: not requested in this autonomous run; `make completeness-test` records `"recognition": "not run"`. The listening audit is the completeness gate.

### D12. Model copy phase overwrites declared outputs only

- Found: with script sandboxing on, the copy phase cannot delete the `Resources/Models` directory before copying.
- Chose: copy each manifest file to its declared output (input and output xcfilelists generated with the manifest). A file from an older manifest could remain in a reused DerivedData build; `bundle-check` validates every manifest file and the manifest copy itself.

### D13. Audio sink calls are synchronous

- Found (TDD): with an async `schedule`, a device-change replay could interleave with a newly synthesized unit, so audio order broke and one callback was ignored (hang in `deviceChangeReplaysCurrentUnitOnly`). Separately, playback callbacks reach the session through separate tasks and can arrive out of order (intermittent hang in `playedBuffersAreReleased`).
- Chose: `AudioSink.schedule` and `stop` are synchronous (AVAudioPlayerNode scheduling is immediate), so stop and reschedule run on the session actor with no suspension; each scheduled buffer carries a sequence number, callbacks mark buffers played, and the leading played buffers are released in order. Regression test `outOfOrderPlaybackCallbacksReleaseInOrder`.

### D14. Voice sample input kind

- Chose: `InputKind.sample` and `RequestCoordinator.playText` for the settings window's sample button: it replaces any reading and is never a stop gesture.

### D15. Underscore emphasis is not stripped (phase 3, unit 3A)

- Plan said: strip Markdown emphasis.
- Found (phase 3 review): the underscore forms removed underscores from identifiers (`__init__.py` became `init.py`), against decision 7 ("code operators and names spoken as written").
- Chose: strip asterisk emphasis (`*word*`, `**word**`) and strikethrough only; `_word_` and `__word__` stay as written. Fixtures: `__init__.py`, `_private_`, `__strong__`.

### D16. Table rows only inside Markdown tables (phase 3, unit 3A)

- Found (phase 3 review): any line with two pipes became a table row, so a shell pipeline (`cat log | grep x | wc -l`) was read as cells.
- Chose: a line is a table row when it starts with a pipe, when a separator row follows it (a header) or when it follows a table row. Fixtures: two pipelines and a header-only pipe table.

### D17. One validation pass per launch (phase 3)

- Found (phase 3 review): each launch hashed about 276 MB (bundle, store, then the engine check).
- Chose: activation validates the installed version first and reads the bundle only when it must copy; `VoiceSetup` hands the directory validated under the consumer lock to the engine. A launch with a valid store hashes the 95 MB once. A repair from a damaged bundle still reports "Reinstall Cáptalo".

### D18. Two lock-guarded adapters opt out of Sendable checking (phase 4, Swift 6)

- Plan said: the Release build passes in Swift 6 mode with no new warning suppressions.
- Found: `MenuCopyAdapter` keeps the last found menu item (`AXUIElement`) and `AVAudioSink` owns `AVAudioEngine` and `AVAudioPlayerNode`; none of these types is `Sendable`, so `Synchronization.Mutex` cannot hold them.
- Chose: both classes are `@unchecked Sendable` with every mutable access under one `NSLock`. No `@preconcurrency` import and no warning suppression remain; the build has no warnings in Cáptalo code.

### D19. Defaults restore deletes before importing (phase 4 review)

- Found: `defaults import` merges into the domain, so keys written during the fresh-state check (a recorded shortcut) survived the restore and the comparison could never pass.
- Chose: restore deletes the domain, imports the backup, compares normalized XML and marks the record restored; backup refuses to start while an unrestored record exists. Tested on a disposable domain, including an extra key written between backup and restore.

## Phase 1 handoff (2026-11-15)

- Candidate: branch `feat/core-reader`, commits `a000427` (rename), `7f7737a` (cc-rpi v2.2.0), `6eb0b4a` (foundation), `556c148` (review repairs) and the simplify commit that carries this note. `make verify` (8 checks: whitespace, rpi-installation, core tests debug and release, unsigned Debug and Release builds, log-audit, script-test) passed on the simplify candidate; evidence in the worktree's ignored `.rpi/local/verification.json`.
- Tests: 13 CaptaloCore tests (chunker characterization, PrivacyLog), 18 script tests.
- Mutation checks (run once, 2026-11-15): first-chunk minimum 45 to 40 fails `firstChunkTargets45To110Characters`; first-chunk hard length 110 to 150, later minimum 80 to 90, and disabling the 240 word split each fail the chunker suite.
- Independent review: one fresh-context reviewer. Findings and dispositions: (1) blocker, `.SHELLFLAGS` ignored by GNU Make 3.81: fixed, with a script test that runs a failing `xcodebuild` stub; (2) weak characterization tests: fixed, mutations above; (3) install error handling and logs: fixed; (4) bundle-ID check before quit, relaunch after rollback: fixed; (5) `signing-setup` without a team: fixed, it now explains how to set the team; (6) per-checkout install record: fixed (main checkout state); (7) record the real signing authority: fixed (`codesign -dv` Authority); (8) log-audit patterns: fixed; (9) exhaustive PrivacyLog test: fixed; (10) leftover Sotto names in notices and the release playbook: fixed; `docs/index.html` (upstream marketing page) left for the owner; (11) `DEVELOPER_DIR` for step 3: recorded as D6.
- Simplify pass (four reviewers: reuse, simplification, efficiency, altitude). Applied: one `xcb` Makefile macro; install reuses `make build` (removes the duplicate build and shell quoting); build-info via build settings with sandboxing on; one commit source in the record; removed the unused install-path override and log-audit exception list; shared helpers (`info_plist`, `codesign_field`, `write_json`, `poll_until`); `Duration` division for milliseconds; test helpers. Skipped: the team plumbing (the owner must still supply the team once); the second deep `codesign --verify` after the move (the phase spec requires both); lazy `PrivacyLog` rendering (one allocation per event); `git status --untracked-files=no` (untracked files are part of the dirty flag).
- Not done, blocked by D1: task 6 (signed install, first launch, the after-launch shared-cache record), the real-path install replacement check (covered by temp-directory tests), and all manual criteria. Shared-cache record before first launch: `~/.cache/fluidaudio` absent at 2026-11-15T06:23Z (`.local/build/evidence/phase-1.json` in the worktree).
- Team ID and designated requirement: not available until signing setup.
- Setup DerivedData (`.local/setup/DerivedData`, main checkout): retained; removal needs owner authorization.
- Phase 2 entry: the automated phase 2 work proceeds under the owner's all-phases instruction. Its manual gates (Accessibility grant, matrix, permission survival) need the signed fixed install first.

## Phase 2 handoff (2026-11-15)

- Candidate: `e8644c9` (capture), `2e3cab9` (review repairs), `53e27d7` (cc-rpi 0d0213e), and the simplify commit that carries this note. `make verify` (8 checks) passed on the simplify candidate (exit 0).
- Verification note: on `2e3cab9`, `make verify` failed only `rpi-installation`, because the local cc-rpi source moved to `0d0213e` during the session; the reviewed update is `53e27d7`, after which all 8 checks passed (exit 0). My first commit chain checked `grep`'s status instead of `make verify`'s; later runs check the exit status itself.
- Tests: 61 CaptaloCore tests (RequestCoordinator 11, ReadingIdentity 1, CaptureCoordinator 16, ClipboardTransaction 19, CaptureProbe 2, PrivacyLog 4, chunker characterization 10), 21 script tests. Every test name in the phase 2 spec exists.
- Mutation checks (2026-11-15): removing the final change-count check fails `writeBetweenReadAndFinalCheckIsPreserved`; disabling the identity comparison fails `stopGestureStopsSession` and `sameCapturedTextTogglesStop`; letting a confirmed-empty selection reach Copy fails `confirmedEmptyNeverReachesCopy`; removing step 0 fails `cancelWhileWaitingForLockSendsNoCopy` (after the test was tightened to count snapshots); removing the stale-handle guard fails `interleavedPromotionsNeverStartAStaleHandle`; removing the once-per-PID guard fails `chromiumGetsManualAccessibilityOnce`.
- Independent review (fresh context): no blockers. Dispositions: (1) recheck order: fixed, slow source check first, currency and change count immediately before Copy, test added; (2) stale handle start/stop: fixed, guarded promote and per-session speech stop, test added; (3) nonzero unreadable range: fixed, test added; (4) Chromium tree built asynchronously: fixed, bounded re-query (D8); (5) unreadable menu: fixed, `.unknown` sends no key, test added; (6) failed restore leaves the clipboard empty: plan row corrected (D7), test models the clear; (7) weak once-guard test: fixed; (8) `secondChange` test asserts no read: fixed; (9) materialization failure test: added; (10) provider time: the transaction now logs `clipboardSnapshot`; the probe's own snapshot limitation is documented; focus check includes the element; (11) stale playback callbacks: dropped; (12) shutdown during a resolve: fixed (entry removed after resolve); (13) main-thread AX at press: source read off the main actor; modifiers re-checked at the post.
- Simplify pass (four reviewers). Applied: capture logging once, in `RequestCoordinator`; `CaptureOutcome.capturedLayer` and `capturedLength`; `FocusEnvironment.matches`; `copyAction` returns `Bool` (a failed press ends at once); `ClipboardResult` is `.copied`, `.cancelled` or `.failed(CaptureFailure)`; `AsyncSerialLock.withLock` (one release path); the session factory passes a finish callback (removes the weak box and the shared-state reach-back); probe mode chosen once at wiring; trust checked only by the coordinator; shared `AX` helpers with one timeout policy on every element; one menu walk per Copy press and one batched attribute read per item; the byte budget enforced during materialization; probing stops at the first AX error; `Synchronization.Mutex` for the two lock-protected classes; one hash per press; a test that the collector's subsystem matches `PrivacyLog`. Skipped: the Debug probe's extra clipboard reads (Debug only, documented); replacing real sleeps in the transaction tests (about 0.5 s per run).
- Not done, blocked by D1 (no signed install): the 12-app matrix (`docs/research/2026-11-15-capture-matrix.md`, status "not run"), the Accessibility revoke-and-grant check and permission survival. No waivers were requested. `CopyPolicy`: `com.microsoft.VSCode`.
- Phase 3 entry: plan accepted through phase 2's automated gates only; the manual gates above stay open.

## Phase 3 handoff (2026-11-15)

- Candidate: `6e86e90` (speech), `5f79a0d` (review repairs) and the simplify commit that carries this note. `make verify` (13 checks: whitespace, rpi-installation, CaptaloCore and CaptaloSpeech tests in debug and release, unsigned Debug and Release builds, bundle-check, offline-test, completeness-test, log-audit, script-test): passed (exit 0) on the simplify candidate's code; this commit adds only the notes and phase file.
- Pin: FluidAudio `v0.18.3` (`c8b41f98`) plus the committed patch, local deterministic commit `6fe650eb55641f408b2369ac792a3255de2789e3` (D9). The plan's "`Package.resolved` pins FluidAudio by exact revision" is met in substance by the recorded commit, which `Scripts/prepare-fluidaudio` reproduces and checks; the app's `Package.resolved` lists no remote FluidAudio pin because CaptaloSpeech uses a path dependency. Moving to the `juan294/FluidAudio` fork needs the owner's confirmation (one push, one dependency line).
- Source audit: `docs/research/2026-11-15-fluidaudio-source-audit.md`. No background or out-of-process transport; no child processes; word-level G2P warnings disabled through `AppLogger` (no fork patch, no acceptance needed).
- Voices: `af_heart` (default), `af_bella`. Manifest version `c9a7935e5471f3a8870ee7ec13258f973bb1410668f34a245dd0d6787c6bce17`, 49 files, 95,331,935 bytes; generated set empty (a fresh store gained no files in the offline test). Licences: Apache-2.0 for FluidInference/kokoro-82m-coreml (`51c07202`) and hexgrad/Kokoro-82M (`f3ff3571`), recorded in `THIRD_PARTY_NOTICES.md`.
- Limits as built: units of one sentence, at most 400 characters (first unit 160), hard split at a grapheme-cluster boundary; at most one synthesis in flight and 3 units ahead; every enqueued unit (audio plus pause) at most 35 s, else split (minimum piece 40 characters) and re-synthesized, never truncated; queued audio at most 105 s; pauses 0.30 s after a sentence and 0.35 s more after a paragraph.
- Recognition check: not run (D11). The listening audit is the completeness gate.
- Measurements (Release probe on this Mac, M5 Ultra, not the installed app; completeness evidence of 2026-11-15: first audio 834 ms for the first voice on a fresh engine and 119 ms for the second; longest unit 24.6 s; peak footprint 1,053 MB and 1,130 MB on the completeness fixture; on the 20,000-character unpunctuated fixture 51 units, longest 26.2 s, first audio 1,156 ms, 45.1 s total, peak footprint 1,539 MB, no oversize splits; stop to silence 0 ms and to an idle pipeline 168 ms (paced run); a device change replayed exactly one unit (25.9 s); the paced queue reached 77.4 s with 4 buffers retained). These are probe-level numbers for the owner's verdict, not the app measurements the plan asks for.
- Mutation checks (2026-11-15): removing the emphasis rule fails `markdownEmphasisNotSpoken`; earlier phase mutations unchanged.
- Independent review (fresh context): 2 blockers, 9 should-fix, nits. Dispositions: (1) second instance before the lock: fixed, `VoiceSetup` takes the consumer lock first, test `secondConsumerCannotRepairOrReclaim`; (2) device change skipped units: fixed with `PlaybackGate` in the sinks, test `engineRestartCompletionsDoNotSkipTheAudibleUnit`; (3) engine-start failure and wrong format: `schedule` reports failure, the reading ends with a voice error, test `sinkFailureEndsWithVoiceErrorAfterScheduledAudio`; (4) TextPreparer pipelines, dunder names, code-line prompts, URL punctuation, missing negatives: fixed (D15, D16), tests added; (5) 105 s bound with pauses: fixed, tolerances removed; (6) unbalanced split: fixed with a midpoint fallback, test added; (7) four weak tests: rewritten, plus a script-level fetch rejection test; (8) completeness-test vacuous checks: fixed (exact played sequence, text reassembly, per-unit records with phonemes, normalized text and completion, paced queue bound, stop-to-silence and stop-to-idle); (9) offline-test gaps: fixed (exit 4 for a damaged store, signal handling, timeouts, child sampling, grep status); (10) source audit recorded; (11) reinstall during a reading: the reading stops first with a voice error, engine start serialized; nits: logger order, manifest update keeps `generated` and writes only with `--write`, one validation pass per launch (D17), rollback message, break exactly at the limit (test). Not changed: one sample button for the selected voice (the phase 4 settings window lists a sample per voice); the single `CurrentReading` slot (the coordinator starts a new session only after stopping the old one).
- Simplify pass (four reviewers). Applied: one `audioSeconds` helper; `VoiceLoader` folded into `VoiceSetup` (the damaged-store test now runs the production path); one probe sink and wait helper; computed queue bound; voice and speed sync through `didSet`; dead probe error and sink state removed; atomic marker writes; `URL.applicationSupportDirectory`; one hex helper; precompiled block patterns and a static pause set; bounded length check in the chunker; `TextPreparer.units(for:source:)` as the one text-to-units chain for the app and the probe, and `hasSpeakableText` in CaptaloCore; `play(text:)` for the sample instead of a fake input kind; scheduled events carry character counts for probe pairing; a stamp so `make build` skips vendoring and model verification while their inputs are unchanged; the completeness evidence takes the manifest version from the probe. Skipped, with reason: in-place regex on one mutable string, tokenizer reuse and per-block normalization dedupe (preparation is not the first-audio cost; the engine is); the pause-padding copy (one copy per unit); hashing while copying (fresh installs only); fewer probe runs in completeness-test (each mode stays isolated); the 50 ms child sampling in offline-test (needed for the child check); moving device-change routing into CaptaloCore (the app's `SpeechService` keeps it; covered by the gate test and the manual unplug check).
- Not done, owner or signing required: ten-minute listening (`Fixtures/speech-listening.md`, 1,307 words; the plan asks for about 1,500), audible stop and replace in the six mandatory apps, cleanup intelligibility, the performance verdict on the installed Release app, headphones unplug, Wi-Fi off reading, the shared-cache record after the manual session, the final voice list.
- Resources: `.local/models` (95 MB, verified), `.local/vendor/FluidAudio` (patched clone), `.local/fetch-home` (empty), offline and completeness run directories removed on success, completeness evidence JSON in `.local/completeness/`. All are ignored, task-owned and reproducible. The real `~/.cache/fluidaudio` is still absent.

## Phase 4 handoff (2026-11-15)

- Candidate: `338c84c` (delete-only), `5317cab` (shell), `a16a774` (review repairs) and the simplify commit that carries this note; `make verify` (14 checks, adding `shell-audit`) passed (exit 0) on the simplify candidate's code.
- Entry probe (task 1): KeyboardShortcuts 3.1.0, tag commit `772133d9dbe800fdac0473226822994c5c162c58`, read 2026-11-15 through `gh api`. `HotKey` is an internal class; `onRegistrationFailed` (`HotKey.swift:17`, fired at `:262` when `RegisterEventHotKey` fails) is used only inside `KeyboardShortcuts.swift:207` to drop the hot key. Callers get no signal, so the row shows the stuck-state table's second text: "If this shortcut does nothing, another app may use it; choose another." The package is pinned by that revision.
- Defaults keys (domain `com.thecreativetoken.captalo`): `reading.speed`, `reading.voice`, and KeyboardShortcuts' own `KeyboardShortcuts_readSelection`. The inherited keys (`globalShortcut`, `speech.pronunciationRules`, `stats.*`) have no writer; values written by earlier builds stay unused. The upstream `com.Shreysid.Sotto` domain is never touched.
- Tests: CaptaloCore 122 (SetupState 7 including `checkingVoiceIsPendingNotMissing`, ShortcutValidation 1, LoginItemState 7, ReadingPreferences 4); script tests 25 (defaults round trip on a disposable domain, including a key written between backup and restore). Mutation check: making Screen Recording required fails `missingScreenRecordingDoesNotRequireSetup` (and five more); adding `NSStatusItem` to `Captalo/` fails `shell-audit`.
- Independent review: 1 blocker, 4 should-fix, 7 nits. Dispositions: (1) restore merged into the domain: fixed (D19); (2) a second backup could hide the original: fixed, one unrestored record at a time; (3) a register error dropped the approval button: fixed, test added; (4) entry-probe evidence: recorded here; (5) shell-audit could pass while a symbol existed: fixed, mutation-checked; (6) the default Settings menu item: removed; (7) a press during the launch voice check opened the window: ignored now; (8) setup decisions outside `SetupState`: one `requireSetup()` (simplify); (9) unknown login status and toggle state: mapping in CaptaloCore with a test per value, approval-pending shows on; (10) `@unchecked Sendable`: recorded (D18); (11) a rejected binding was silent: a message now; (12) the running-app check missed launches with arguments: fixed.
- Simplify pass (four reviewers). Applied: one AX status mapping (the copies lacked `.parameterizedAttributeUnsupported`); a checking voice is pending in `SetupState` and `requireSetup()` is the one place that opens the window; the view reads `setup.showsVoiceError` and one fallback voice branch with a `repairLabel`; one refresh trigger (`didBecomeActive`) and no SMAppService read at launch; published values change only when they differ; a cached `readShortcutSet`; single default voice, speed and `speedIndex` in `ReadingPreferences`; a shared defaults-script helper; one window width. Skipped, with reason: removing `ShortcutValidation` and the rejection path (phase 5 adds the region shortcut, which makes it live); using `SMAppService.Status` directly in the row (the mirror keeps the row tests independent of the system enum); storing `selectionCapture` again as a lazy closure (Swift 6 rejected the lazy form; one small allocation per press).
- Not done, signing required (D1): the fresh-state check with `make defaults-backup` and `make defaults-restore`, Dock/menu bar/Cmd+Tab, Spotlight reopen and Quit, focus during a reading, launch at login across a logout, the shortcut conflict text, the capture matrix rerun and the installed `LSUIElement` check (the built products report `true`). `make offline-test` reran as part of `make verify`.
