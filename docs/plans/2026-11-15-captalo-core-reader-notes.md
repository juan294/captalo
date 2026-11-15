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

### D20. Gate 0 runtime questions recorded as pending (phase 5)

- Plan said: gate 0 answers questions 1 to 3 on this Mac before 5A starts, and stops if question 1 or 3 has no working answer.
- Found: questions 1 to 3 need Screen Recording and an installed, signed app, which D1 blocks. The SDK has every API the chosen path needs, and question 4 ran.
- Chose: build the documented mechanisms (non-activating panels, a session event tap for Esc, ScreenCaptureKit with the app excluded) and record the runtime answers as owner checks in the phase 5 manual criteria.
- Why: no answer was negative; the questions are unanswered. If the owner check finds a negative answer, the stop condition applies then, and the region interaction needs a new owner decision.

### D21. The Vision adapter lives in `Packages/CaptaloOCR` (phase 5, unit 5B)

- Plan said: OCR adapter files in `Captalo/Services/OCR/`.
- Found: `make ocr-probe` must run the app's recognition step from the command line, and the app target cannot be linked by a command-line tool.
- Chose: `VisionRecognizer` in a small `CaptaloOCR` package used by both the app and `captalo-ocr-probe`; the ScreenCaptureKit capturer stays in `Captalo/Services/OCR/`. The image-write code search covers both.
- Why: the probe then tests the shipped recognition code, not a copy.

### D22. The overlay controller has no automated test (phase 5, unit 5A)

- Plan said: `RegionOverlayTests.screenChangeCancels` posts the notification to the controller and checks the result and the teardown.
- Found: the controller is AppKit code in the app target, which has no test target; `CaptaloCore` holds no AppKit UI by design.
- Chose: all selection logic lives in `RegionSelectionTracker` (CaptaloCore), which the test drives with `.screensChanged`; the controller only forwards events and tears down in one `tearDown`. The observer wiring, panel order-out, cursor pop and tap invalidation are owner checks (manual criteria 3 to 5).
- Why: adding an app test target is new test infrastructure outside this plan's scope; the logic that decides the outcome is tested.

### D23. RPI installation update to v2.2.1 (validation repair)

- Plan said: verification step 2 is `rpi-distribution.py check`.
- Found: the validation run on `b639189` failed this check (exit 2) because the local cc-rpi source moved to v2.2.1 (`909d202`) after the phase 5 verification.
- Chose: the same reviewed update procedure as D3. The plan's only operations were `.rpi/distribution.json`, `.rpi/manifest.json` and one new baseline, applied as its own commit (`04d23e0`). The optional push receipt gate the tool mentions was not enabled; that is a policy change for the owner.
- Why: the gate must pass, and the update changes no skill, rule or instruction body.

### D24. An unreadable menu stops the synthetic Copy (VAL-02)

- Plan said: the menu layer presses Copy when it finds it; synthetic Cmd+C runs only when Copy is known to be absent.
- Found: read errors on a menu child list or a key-equivalent attribute were treated as "no Copy", so an unreadable menu authorized Cmd+C.
- Chose: the walk lives in `CaptaloCore` (`MenuCopyFinder`, `AXStatus`). Only "attribute unsupported", "no value" and CFNull count as absence. Any other AX error keeps the result unknown, and the capture ends with `menuUnreadable` and no key event. A Copy item found in a readable branch is still pressed.
- Why: the plan forbids Cmd+C when Copy availability is unknown. Apps whose menus time out now get a "could not read" result where they used to get a synthetic copy. The capture matrix should watch for this.

### D25. Esc containment holds the tap while Esc is held (VAL-08)

- Plan said: Esc cancels the region overlay and never reaches the source app.
- Found: only keyDown was swallowed, and a nil event tap left panels on screen without Esc. The first repair removed the tap 2 s after the overlay closed even while Esc was still held, so later autorepeats and the keyUp reached the source (validation re-review).
- Chose: `EscapeContainment` (`CaptaloCore`) swallows the accepted Esc keyDown, its autorepeats and its keyUp. After the overlay closes it keeps the tap until that keyUp. Every 2 s it reads the physical key state through the tap (`CGEventSource.keyState(.hidSystemState, key: 53)` in production): while Esc is down the tap stays, and when it is up the tap is removed even if no keyUp arrived. An outer cap of 30 s after the overlay closes removes the tap whatever the key state. An Esc already held when the overlay opens, and every other key, pass through. If the tap cannot be created, no panel is shown, the press ends with `overlayUnavailable`, the failure notice shows at once and settings open. This supersedes the phase 5 dispositions N3 ("not changed") and N7 (press order, now VAL-01).
- Why: the whole gesture is contained, and the tap's lifetime stays bounded. Residual: an Esc held longer than 30 s after the overlay closes leaks its later autorepeats and keyUp; a keyUp still queued when a key-state tick removes the tap can reach the source; the size of that window is not measured. Real tap and key-state behavior is a gate 0 owner check (D20): hold Esc for 5 s or more over a key-event viewer.

### D26. One engine call at a time; stop cancels synthesis in flight (VAL-04)

- Plan said: at most one synthesis in flight; stop is immediate.
- Found: a replaced session's synthesis kept running while the next session started its own, and repair or lease release did not wait for it. The pinned FluidAudio does not serialize whole calls.
- Chose: `SynthesisGate` (`CaptaloCore`) admits one engine call at a time in arrival order, and a waiter cancelled before its turn never enters. `KokoroSynthesizer.stop()` (repair and lease release) waits for the active call. `ReadingSession.stop()` cancels its pipeline, so FluidAudio's cancellation checks end stale work early. Probe stop-to-idle went from 824 ms to 113 ms (one run each).
- Why: playback stop stays immediate. A hung CoreML call would also hold up a reinstall; that follows from the design.

### D27. Model store keeps a manifest record per version (VAL-07)

- Plan said: retain the most recent previous valid version.
- Found: the outgoing current version became "previous" only because it existed, so a damaged version could replace the last valid one.
- Chose: each installed version has a record at `<store>/.manifests/<hash>.json`. The outgoing version is promoted only when it validates against its record. A missing, unreadable or mismatched record is rewritten when that version is current. Each version change hashes the outgoing version once more (about 95 MB).
- Why: validity needs the content check. A store written before this change has no record for its current version and loses that rollback on its first upgrade; the app is unreleased, so no fallback was added.

### D28. Whole-selection normalization and whole-block cleanup remain (VAL-05 residual)

- Plan said: preparation is lazy, so first audio and stop do not wait for the whole text.
- Found: the eager parts the validation named (block array, line split, per-paragraph unit queue with `removeFirst`) are now lazy, and tests check production tokenization. Two passes still run before the first unit: character normalization over the whole selection (`TextPreparer.swift`, before the lazy iterator is built; the no-op path still scans every scalar, and real normalization copies the selection), and regex cleanup plus normalization over one whole block before its first sentence. Both run synchronously on the `ReadingSession` actor, so a stop cannot interrupt the pass in progress. No window cut can be proven byte-identical: several rules (`markdownLink`, `inlineCode`, the ANSI OSC form, emphasis and strike) match across sentence boundaries with no length limit, and NLTokenizer sentence boundaries depend on the whole paragraph.
- Chose: keep both passes and make them cheaper with identical output (no-op normalization skipped, lines found by byte search). Example measurements on this Mac for one paragraph: 0.69 MB from 0.131 s to 0.065 s to the first unit, 2.79 MB from 0.514 s to 0.272 s. Output was identical over 72,000 generated cases.
- Why: correct units matter more than bounded work on multi-megabyte single paragraphs. These measurements are examples, not an upper bound: there is no worst-case bound on first audio or on stop latency during preparation, for any input shape or Mac. The installed-app responsiveness check stays an acceptance gate. Status: S3 residual, owner acceptance pending (recommended by the integration owner and the validator); not fully fixed.

### D29. Preference tests delete their domain out of process (test hygiene)

- Plan said: tests use disposable preference domains.
- Found: `defaults delete` and `removePersistentDomain` left empty plist files in `~/Library/Preferences`. In-process deletion was written back by cfprefsd 2 to 12 s later.
- Chose: the Python and Swift test helpers delete their own exact disposable domain with `/usr/bin/defaults delete`, then remove that exact plist and assert it is gone. Real app domains are never touched.
- Why: a single test run on `develop` (`49923a1`) left no plist 30 to 60 s after it ended, in the isolated suite and in full Debug and Release runs. The old in-process teardown also left none in those runs, so the leak could not be reproduced on demand. Empty `tests.<UUID>` plists did appear during the 14:46 to 15:00 `make verify` runs, while other agents ran tests in parallel, and six more appeared at 15:12 and 15:13 with no test of this session running. The leak is not proven closed and its cause is unknown. Files left so far (44 `scripttest-*` and 159 `tests.<UUID>`, all empty) were not deleted; that is an owner decision.

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

## Phase 5 handoff (2026-11-15)

- Candidate: `cadd2d1` (region OCR), `1ee9b12` (review repairs), `3214cd7` (simplify pass) and the commit that carries this note. `make verify` (15 checks: whitespace, rpi-installation, CaptaloCore and CaptaloSpeech tests in debug and release, unsigned Debug and Release builds, shell-audit, bundle-check, offline-test, completeness-test, ocr-probe, log-audit, script-test): passed (exit 0) on `3214cd7`, recorded 2026-11-15T11:00:10Z with the tree identity unchanged; the note commit adds only documents.
- Overlay read in this phase: `.rpi/project/rpi-implement.md` is not installed; no declared override applied.
- Gate 0: results table in `phase-5.md`. Question 4 measured (Vision throws `requestCancelled` within 0.2 ms of a mid-run cancel); questions 1 to 3 are owner checks (D20). Mechanisms: non-activating panels per screen that never become key, Esc through a session event tap (swallowed), `SCScreenshotManager` with a content filter that excludes Cáptalo and `sourceRect` at native scale.
- Built: `KeyboardShortcuts.Name.readRegion` (no default) with identical-binding validation in both directions; the optional settings section (recorder, Screen Recording row with "Allow" and, after a request, "Quit and reopen", failure notice after 3 consecutive errors or timeouts); `RegionReader` (one slot reserved before capture, released only when the native call returns, 10 s caller timeout, stale-token drop, caller cancellation is a cancel); `DocumentTranscript` (wide items split the page into bands, columns left to right, tables stay row blocks, list items stay list blocks); `CaptaloOCR` package shared by the app and `captalo-ocr-probe` (D21); `make ocr-probe` in `make verify` and `.rpi/policy.json` (same commit); `shell-audit` forbids `CGWindowListCreateImage` in `Captalo/` and image writes in `Captalo/Services/OCR` and the `CaptaloOCR` library.
- Probe as run: two-column fixture 6 blocks, table fixture 6 blocks (title, 4 rows, closing paragraph), both in the expected order; native cancel threw 0.08 ms after a cancel 90 ms into a 450 ms run; a caller timeout freed the slot 1 ms later.
- Tests: CaptaloCore 164 (phase 5 adds RegionGeometry 7, RegionOverlay 4, DocumentTranscript 7, RegionReader 14, OcrFailureCounter 3, RegionPending 5, SetupState 1, PrivacyLog 1). Red-first evidence for the repairs: `cancelledCaptureIsACancelNotAFailure`, `narrowItemBesideWideItemIsKept`, `callerCancellationEndsTheWaitButNotTheWorker`, `dragRectIsClampedToStartDisplay` and `dragFromTheTopEdgeIsInside` failed before their fixes. Mutation checks: an image write in `Captalo/Services/OCR` and `CGWindowListCreateImage` in `Captalo/App` each fail `shell-audit`.
- Independent review (fresh context): 0 blockers, 4 should-fix, 7 nits. Dispositions: (S1) narrow items beside a wide item were dropped: fixed, bands partition the page; (S2) first press would time out after a 13.5 s cold load: premise corrected with evidence, a fresh process ran a full recognition in 0.66 s, so 13.5 s was a one-time system cache; the gate 0 wording that implied a per-process cost was corrected, the residual cold-cache risk is recorded in `phase-5.md` and goes to the owner's performance check; (S3) the race ignored caller cancellation (quit waited, superseded reads counted as timeouts): fixed, test added; (S4) `screenChangeCancels` tests the tracker, not the controller: recorded (D22), gate 0 citation narrowed; (N1) the cancel probe could pass on a fast finish: fixed, the probe now requires a mid-run cancel to throw; (N2) busy, error and timeout looked alike in the log: fixed, the event carries `failure=` and `blocks=`; (N3) Esc keyUp reaches the source app, and a nil tap has no fallback: not changed, apps act on keyDown and holding the tap past teardown adds a second lifetime path; the region press requires Accessibility, which the tap needs, and a click still cancels; (N4) drawn rectangle not clamped: fixed; (N5) top-edge start cancelled: fixed; (N6) the window opens but does not scroll to the Screen Recording row: not changed, the optional section is part of the one settings form; manual criterion 6 checks it; (N7) two quick presses can submit out of order: not changed, the same detached-source pattern as the selection path (phase 2 design, no reported failure).
- Simplify pass (four reviewers). Applied: one `units(for: ReadingContent)` chain and one `hasSpeakableText(_: ReadingContent)` (the OCR emptiness check now uses the chunker the reading uses; the dead `units(for:source:)` OCR branch is gone); one `RegionGeometry.rect(from:to:clampedTo:)` for the drawn and captured rectangle; the race timer as a local; one `pressCanSpeak()` gate, one `currentSourceOrNone()` and `quit()` for both shortcuts; `requestScreenRecording()` reused by the press; repaint only the changed rectangle; the tap port stored once; `Block.plainText` public and reused by the probe; one `switch` for the log fields; in-place column append; a stale doc comment removed. Skipped, with reason: one `captured(ReadingContent, layer:)` success case (touches the phase 2 selection path and its tests; the two cases stay explicit); dropping `.capture` or `.ocr` duplication in the log (the spec names both events); a `pressDecision` in CaptaloCore (the shared app gate removes the copy; the decision stays two lines); `regionPressRequirement` as a Bool (kept for owner decision 8 traceability and its named test); removing `globalRect` (used by the probe and the geometry tests); a fixed cancel delay in the probe (the full-run timing makes the cancel land mid-run on any machine; about 0.45 s per verify); one probe process and one `swift build` call (small, and separate processes keep each fixture isolated); computing the transcript string once per outcome (a few KB per region press).
- Not done, owner or signing required (D1): every phase 5 manual criterion (scanned PDF, PNG fixtures and code screenshot by ear, focus and Esc in TextEdit, full-screen app, second display, Screen Recording revoke and grant, permission survival after `make install`, OCR performance, network off), and gate 0 questions 1 to 3.
- Resources: none new. The probe builds in `Packages/CaptaloOCR/.build` (ignored, reproducible); the gate 0 spike stayed in the session scratchpad and is not merged.

## Validation repair handoff (2026-11-15)

- Input: the `rpi-validate` report on `b639189` (ignored `docs/agents/validation-report.md`): not ready, 11 findings (VAL-01 to VAL-04 S2, VAL-05 to VAL-11 S3) and a failed `rpi-installation` check. Repairs were made in three local worktrees (`fix/val-a` capture and app, `fix/val-b` speech and text, `fix/val-c` OCR and scripts), integrated in `fix/val-integ`, then merged into `develop`.
- Commits: `04d23e0` (RPI metadata, D23); `0588640`, `0b728de` (VAL-01, 02, 08, 10); `25e3cb6`, `9abb7d6`, `35500c6`, `03aece3`, `de38cd4` (VAL-03, 04, 05, 07); `a7ddca5`, `fa18d96`, `d5ce67a`, `b955aee`, `c6c67fb` (VAL-06, 09, 11); simplify `579d6f3`, `a73fe2c`, `85c5134`.
- Dispositions, all with a regression that failed before its fix (red output kept in the session scratchpad):
  - VAL-01 fixed: `RequestCoordinator.reservePress()` takes an ordered ticket when the shortcut fires, before the detached source lookup; a stale ticket runs no capture (`PressOrderTests`).
  - VAL-02 fixed (D24): `MenuCopyFinder` and `AXStatus` in CaptaloCore (`MenuCopyFinderTests`, `AXStatusTests`).
  - VAL-03 fixed: failed device-recovery entries leave the queue and the reading ends with `.voiceError` (two `ReadingSessionTests`).
  - VAL-04 fixed (D26): `SynthesisGate`, gated `KokoroSynthesizer`, `SynthesisLifecycleTests.replacedSessionsShareOneEngineCallAndRepairWaitsForIt`.
  - VAL-05 partly fixed, S3 residual pending owner acceptance (D28): lazy blocks, lines and sentences; `LargeParagraphPreparationTests`, `paragraphIsSegmentedOnDemand`, `normalizationEdgeCasesKeepTheirOutput`.
  - VAL-06 fixed: `completeness-test` requires the exact voice inventory, every required record and valid payloads (`CompletenessHarnessTests`, 10 invalid-payload subtests). It is still a structural check; listening remains the completeness gate.
  - VAL-07 fixed (D27): `damagedOutgoingVersionNeverReplacesValidPrevious`, `unreadableManifestRecordIsRewritten`.
  - VAL-08 fixed (D25): `EscapeContainmentTests`.
  - VAL-09 fixed: one worker owns capture, the currency check, Vision and the slot release, and the caller races the whole worker (`callerDeadlineCoversBlockedCapture`, `callerCancellationCoversBlockedCapture`). `cancelledCaptureIsACancelNotAFailure` now waits for the slot release, because the slot is freed when the capture ends, not when the caller returns.
  - VAL-10 fixed: `PressGate` refreshes a cached false before it decides (`PressGateTests.firstPressAfterGrantReads`).
  - VAL-11 fixed: `defaults-restore` verifies the domain is absent before it writes `.restored`; `is_empty` moved to `defaults-common.sh`.
- Independent review (three fresh read-only reviewers, one per area, with reverts in scratch copies): 0 blockers. Should-fix items, all repaired: the AX error mapping had no test (now `AXStatus` in CaptaloCore); completeness payloads were not validated; test plists were left behind (D29, not proven closed); first-unit cleanup cost (D28). Nits repaired: autorepeat Esc held before the overlay, silent tap failure while trusted, teardown inside the tap callback (deferred to the main queue), stale comment, test gaps for eager segmentation and gate hand-off cancellation, unreadable manifest records. Not changed, with reason: a superseded input is cancelled when the newer press submits rather than at reservation (its result is already dropped, cosmetic); a capture that never returns keeps the OCR slot and later presses report busy (design); a store from before D27 loses one rollback (unreleased app).
- Simplify pass (four reviewers). Applied: the ticket-less `submit` removed so tests use the app path; `RegionFailureState` folded into `OcrFailureCounter` with a per-category threshold, and one outcome-to-log mapping (`RegionReader.event`); `AX.Status` removed in favor of `AXStatus.classify`; `PressGate` reads `canSpeak` once; the tap callback passes non-Esc keys before any handler work; the worker returns a cancellation error instead of nil; public test counters removed from `UnitChunker` and `Paragraph` uses synthesized equality; test fakes reuse `EventLog`, `Gate` and `FakeSynthesizer`; the completeness harness uses a field guard and groups records once; `defaults-restore` checks an absent domain once. Behavior change: an overlay failure now starts its own failure streak in `OcrFailureCounter`. Skipped, with reason: one scalar normalization pass (changed output in about 5% of generated lines); `KokoroEngine: Synthesizer` (needs a public raw-engine `synthesize` that would bypass the gate); sharing one lock primitive with the clipboard `AsyncSerialLock` (changes phase 2 code outside this diff); deferring the outgoing-version hash (D27 needs the content check); reusing `RegionReader.race` in speech tests.
- Verification: `make verify` on `31453de` (all repairs, review repairs and simplify merged): 15 of 15 checks exit 0, tree unchanged during the run, recorded 2026-11-15T14:50:28Z (CaptaloCore 204 tests, CaptaloSpeech 20, script suite 31). Only this note changed afterwards; the merged `develop` was verified again before reporting.
- Still open, owner or signing required (D1): every native and manual criterion listed in the validation report's "Remaining acceptance evidence" (signed install, capture matrix, listening and performance verdicts, shell behavior, gate 0 questions 1 to 3 and the phase 5 manual list). Owner decisions: D28 (accept or redesign), deleting the empty test plists left by earlier runs, and the earlier open items (D9 fork push, final voice list, `.local/setup`).
- Resources: the repair worktrees and branches were removed after the merge; their ignored build caches went with them. Nineteen orphaned `swiftpm-testing-helper` processes from this session's earlier phase 5 runs (idle, about 30 MB each) were stopped.

## Validation re-review repair handoff (2026-11-15)

- Input: the re-review of `a995bf6` (ignored `docs/agents/validation-report.md`) closed seven findings and left four S3 gaps: VAL-05 (D28 residual described too narrowly), VAL-06 (a missing unit record still passed), VAL-08 (an Esc held past 2 s leaked its autorepeats and keyUp) and VAL-11 (a failed preference read counted as absence). The earlier handoff's "fixed" for VAL-06, VAL-08 and VAL-11 is superseded by this section.
- Commits: `ba0ec67`, `e806962` (VAL-08); `d6b25b0`, `d95cd5c`, `f1677c2` (VAL-06, VAL-11); `6186934` (D29 test comment).
- VAL-06 fixed: every run with unit records must cover the expected unit IDs exactly (runs of the same ID collapsed, record count equal to IDs plus `oversizeSplits`); a stopped run must cover exactly the units its summary says were played, in order. Regressions: `test_unit_inventory_mismatches_fail`, `test_stopped_run_units_must_cover_the_played_units`, `test_stop_before_the_requested_units_fails`, with split-unit positive cases. Not changed: a stop that lands between the two pieces of a split unit fails the check falsely (it fails safe; no real run has split so far).
- VAL-08 fixed (D25, rewritten): containment while Esc is physically held, checked every 2 s, with a 30 s cap. Regressions: `escHeldPastTheBoundStaysContained`, `releasedKeyWithoutKeyUpRemovesTheTap`, `containmentIsCappedAfterClose`.
- VAL-11 fixed: `domain_state` reports absent, present or unreadable; absent needs an empty export and either no plist file or an empty-dictionary file; a failed export, an unreadable or corrupt file, or a file holding keys is unreadable, and backup and restore then exit 1 with no state file or marker. Regressions: `test_unreadable_domain_is_never_marked_restored`, `test_backup_of_an_unreadable_domain_records_nothing`, `test_unreadable_or_inconsistent_plist_file_is_never_absent`, `test_unreadable_state_after_the_delete_aborts_restore`. Tests point the preferences folder at a temporary directory through `CAPTALO_DEFAULTS_PREFS`.
- VAL-05: D28 rewritten to name whole-selection normalization, whole-block cleanup and the absence of a worst-case first-audio or stop bound. Owner acceptance is pending; it is not fully fixed.
- Review: one fresh reviewer, then a re-review of the repair delta: 0 blockers; should-fix items repaired (physical key state and a cap for VAL-08, the stopped-run inventory for VAL-06, plist-file inspection for VAL-11, the stale D25 text). Simplify (one reviewer covering reuse, simplification, efficiency and altitude, proportional to a diff of about 200 lines): applied the key query on `KeyEventTap`, `keyCheckInterval`, one decision in `checkKey`, `domain_state` aborting its callers instead of a repeated guard, a direct export pipe, one `stub_failing` helper and `itertools.groupby`. Skipped: the second export in `defaults-backup` (one extra process, kept for clarity).
- Verification: `make verify` on `fb9be31` (round-2 repairs merged): 15 of 15 checks exit 0, tree unchanged during the run, recorded 2026-11-15T18:07:11Z (CaptaloCore 207 tests, CaptaloSpeech 20, script suite 41). Only this note changed afterwards.
- Still open: D28 owner acceptance; D29 (203 empty test plists kept; cleanup and the optional push gate unchanged, as the validator advised); every native acceptance check (D1), including gate 0 with Esc held for 5 s or more over a key-event viewer.
