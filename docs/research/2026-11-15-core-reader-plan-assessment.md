# Assessment: core reader implementation plan

Date: 2026-11-15. Recommendation: revise before acceptance. The architecture and five-phase order remain reasonable; the capture safety contract and several acceptance oracles need correction.

## Scope and evidence

Reviewed the main plan and all five phase files against the accepted brief, subsequent owner decisions, current capture/speech source, resource contract and release procedure. Baseline: `develop`, `362f9eaf2630feaa27d9bb5e71701fea79b7d06f`, `/Users/juan/code/captalo`. The six plan files were untracked at entry. Local Graphify was queried for orientation, then source was read directly. Two independent read-only investigations covered capture/OCR and speech. No assessment overlay exists. No implementation, runtime acceptance test, signing operation, dependency installation or remote write was performed. Findings below are plan defects or unverified integration risks, not claims of reproduced failures in an implemented Cáptalo.

Criteria: deliberate-selection correctness, clipboard and focus preservation, local processing, bounded work, recoverable failures, maintainability and acceptance evidence that tests the actual runtime boundary. Earlier memory supplied orientation only; current files supplied the findings.

## Findings requiring correction

### R1 — High: clipboard attribution and restoration are not established

`docs/plans/2026-11-15-captalo-core-reader-phases/phase-2.md:39-46` reads any changed pasteboard, then promises a late restore if no user write occurred. The specified counter does not identify the writer. A concurrent user copy, clipboard manager or second invocation can supply unrelated text and then have its contents overwritten. A single check at 600 ms cannot cover arbitrary delayed copies. [Apple documents changeCount as an ownership-change counter](https://developer.apple.com/documentation/appkit/nspasteboard/changecount.md), not attribution of a write to a requested Copy action.

The lazy snapshot is also underspecified: supported original bytes must be materialized before replacement. Preserving types or item references alone is not a restorable snapshot. Define bounded snapshot size/time, promised-data failure, empty clipboard, cancellation and restoration failure. If preservation cannot be established, abort that copy path. Preserve newer clipboard content when ownership is uncertain; explicitly record the remaining limitation instead of promising unconditional restoration.

Required tests: concurrent user copy before read and before restore, a delayed write after timeout, overlapping capture, promised/multi-item/multi-type data and partial snapshot failure. Transient markers and the existing named-pasteboard test choice are useful, but do not solve ownership or prevent clipboard managers from observing the initial source-app copy.

### R2 — High: Copy can return text when nothing is selected

`phase-2.md:21-27` needs separate outcomes for unavailable AX selection information and a positively empty selection. An enabled Copy item and changed pasteboard do not establish deliberate selection. [VS Code documents Cmd+C with no selection as copying the current line](https://code.visualstudio.com/docs/reference/default-keybindings). This could read unselected content and break the stop gesture by starting a new reading instead.

Require no-selection cases in each matrix app, including editors and terminals. A confirmed empty range must not fall through to Copy. Where selection cannot be established, use a documented app-specific safe policy or record unsupported capture for owner disposition. Do not change another application's preferences to make the test pass.

### R3 — High: request ownership must begin before capture

`phase-2.md:17-29`, `phase-3.md:75-86` and `phase-5.md:40-59` specify replacement at speech start but not across the whole asynchronous interaction. Current `Sotto/App/SottoAppStatePlayback.swift:13` starts an untracked task per shortcut. An old OCR/copy result can arrive after a newer command and replace the newer reading. Focus can change during the 500 ms modifier wait, sending Cmd+C to another app.

Define one request generation from shortcut through capture, OCR, preparation, synthesis and playback. Reject stale results and callbacks, serialize clipboard transactions, revalidate the source immediately before external effects, and cancel pending work on stop/replace/quit. Specify behavior when modifier release times out. Tests must include rapid presses, stop during loading/OCR, app switching during capture, delayed old results, and stale audio callbacks after engine restart. This is also the principal performance safeguard against queued work.

### R4 — High: offline success is weaker than the claimed no-download guarantee

`phase-3.md:59-66` redirects one registry URL; `:99-106` installs and launches normally before running a network-denied Debug probe. A warm store can hide missing bundled files. Successful synthesis plus no error string does not prove there were no attempted requests, especially if optional failures are swallowed. Loopback redirection is not a complete network policy for an unsandboxed application.

Separate the claims: offline synthesis success; complete bundled assets; no runtime download attempts. Test first-use initialization with a fresh task-owned model root under network denial, then a warm run, all offered voices, and missing/corrupt asset paths. Use the production loading path, with explicit fail-closed asset validation before inference and a verified policy for every downloader reached by it. Instrument attempted downloads or otherwise provide a concrete oracle; do not infer their absence from JSON error text. The ordinary installed app must not initialize the test root before the deny profile applies.

This is supported by a concrete dependency path: [the pinned lexicon downloader catches a fetch failure and returns nil](https://github.com/FluidInference/FluidAudio/blob/v0.18.3/Sources/FluidAudio/TTS/KokoroAne/Assets/KokoroAneResourceDownloader.swift), permitting a different phonemization path. Successful audio alone therefore cannot detect every attempted download. These primary sources were retrieved on 2026-11-15.

### R5 — High: Release speech and completeness are not tested by the stated oracle

`phase-3.md:101-106` records duration and chunk count in Debug only. `:123` then asks that JSON to establish sentence count and order. It contains neither. Positive audio duration can pass despite omitted words. Core-package Release tests do not exercise the FluidAudio adapter; the plan explicitly excludes FluidAudio from that package (`phase-1.md:39`).

Run a real optimized speech probe using the same dependency and build settings as the Release app, in addition to Debug. Record fixture identity, expected sentence/chunk sequence and completion, and audit sentence beginnings/endings by listening to the actual output. Metadata establishes scheduling, not that every word was spoken. Cover every final bundled voice, not only the initial two; changing the accepted voice list must invalidate the relevant evidence.

### R6 — Medium: model storage has no update or interrupted-install contract

`phase-3.md:57-66` specifies a manifest and first-launch copy but not atomic staging, interruption, insufficient disk space, concurrent initialization, version changes, rollback, or compiled-cache identity. Separate immutable verified source assets from generated CoreML artifacts. Define how a new manifest activates a complete store, how an interrupted copy recovers, and when compiled artifacts are invalidated. The fetch script should verify immutable asset identities against the committed manifest, not silently bless changed upstream bytes by regenerating hashes. Test upgrade and repair as well as first install.

Verify the writable-store rationale per asset: [the legacy seven-stage loader uses MLModel(contentsOf:) on stage bundles](https://github.com/FluidInference/FluidAudio/blob/v0.18.3/Sources/FluidAudio/TTS/KokoroAne/Pipeline/KokoroAneModelStore.swift). The plan's blanket first-load compilation explanation is not established for those stages. Auxiliary assets and downloader migration may have different write requirements; a writable app-owned store remains a reasonable design.

### R7 — Medium: two validation procedures conflict with persistent user state

`phase-3.md:117` requires `~/.cache/fluidaudio` not to exist. Yet phase 1 launches inherited code: `Sotto/App/SottoAppStateKokoro.swift:6` calls `Sotto/Services/SpeechControllerKokoro.swift:11`, which invokes `TtsCacheDirectory.ensure()`. The current pinned checkout's `Sources/FluidAudio/TTS/Shared/TtsCacheDirectory.swift:38-41` creates that directory without downloading anything. Other applications may also legitimately own it. Test that Cáptalo does not access or mutate the shared cache; do not require global absence or delete it to satisfy a gate.

`phase-4.md:52` deletes the real preferences domain after earlier phases have used it. Use a disposable preferences suite for automated tests and a preserved/restorable snapshot for the fixed-identity integration check. Scope any reset explicitly. Bundle ID alone also does not prove a running process is task-owned (`phase-1.md:64-69`); record its path/PID and coordinate fixed-path installs across worktrees.

### R8 — Medium: the capture matrix can pass without useful capture

`phase-2.md:75` accepts success or unsupported for every app, without a required successful subset. The accepted brief's selection criterion includes Rex, a browser, selectable PDF and editor. The probe logs only layer, length and timing (`:58-60`), so it can also label wrong text of a plausible length as success.

Require exact fixture equality inside the probe, emitting only a pass/fail result and non-content metadata. Test plain and rich clipboard representations, not only sentinel paste. Name the mandatory successful surfaces; any unsupported mandatory surface needs an explicit owner exception. OCR is not available until phase 5 and is not automatically equivalent to exact selection reading.

### R9 — Medium: performance has measurements but no acceptance decision

`phase-3.md:78-86` bounds synthesized chunks but not preprocessing, queued requests, retained completed PCM, or stop latency during an in-flight model call. `:124` records latency and memory without requiring an owner verdict on those numbers. Use bounded, incremental preparation and release completed buffers. Add stop-during-first-synthesis, repeated replacement and a large-input memory-plateau test. Set practical thresholds or explicitly require owner acceptance of measured cold/warm latency, stop delay and memory before phase acceptance.

The uncertain phonemizer fallback at `:86` can be removed: [v0.18.3 exposes `phonemes(for:)` and `synthesizeFromPhonemesDetailed`](https://github.com/FluidInference/FluidAudio/blob/v0.18.3/Sources/FluidAudio/TTS/KokoroAne/KokoroAneManager.swift#L349). Define counting using the engine's Unicode-scalar/vocabulary semantics and pin that contract with real frontend fixtures. Avoid synthesizing merely to count, repeated whole-passage phonemization, or an additional split policy that disagrees with the engine's own high-level auto-chunking.

### R10 — Medium: OCR cancellation, bounds and overlay feasibility need gates

`phase-5.md:20-50` covers empty/cancelled regions but not capture/Vision errors, timeout, display removal or teardown on all paths. Bound image size and concurrent OCR, and measure OCR latency/memory separately from speech. Ensure panels, cursor state, image references and pending requests are released after success, error, cancellation and quit.

Probe nonactivating panels, drag tracking and Esc while keeping the source key before building the full overlay. Define whether Esc is consumed so it cannot also act on the source application. Verify full-screen Spaces, display changes and screenshot exclusion; waiting one refresh is an assumption, not evidence that overlay pixels cannot enter capture. Geometry unit tests and the planned real Vision fixture are valuable counterevidence, but do not exercise these AppKit interactions.

### R11 — Medium: shortcut recovery promises more than the library contract

The main plan's stuck-state table at `2026-11-15-captalo-core-reader.md:129` promises a warning for a shortcut taken by another app. [KeyboardShortcuts 3.1.0's recorder documents checks for system shortcuts and the app's menu, and a custom validation hook](https://github.com/sindresorhus/KeyboardShortcuts/blob/3.1.0/Sources/KeyboardShortcuts/RecorderCocoa.swift#L8). Do not assume universal conflict detection. Explicitly reject identical selection/region bindings, handle registration failure and define recovery after a conflict or unavailable hotkey. A saved shortcut is not proof of successful registration. Also cover launch-at-login registration failure and approval-required status, rather than only on/off happy paths (`phase-4.md:57`).

### R12 — Medium: signing identity is necessary evidence, not a permission-survival test

`phase-1.md:104` compares designated requirements, which is the right identity concept; the user's summary says identical code signatures, which should be corrected. A changed binary need not have identical signature bytes. [Apple distinguishes stable designated requirements from subsystem-specific trust decisions](https://developer.apple.com/library/archive/technotes/tn2206/_index.html).

Keep the designated-requirement check, add actual signature validation, then verify an existing permission grant survives a changed rebuild and fixed-path reinstall in phases 2 and 5. Record developer signing versus future Developer ID separately; do not promise all future permission prompts disappear. Simulating an empty team is not identical to testing absence of a signing identity (`phase-1.md:97`); inject the identity-discovery boundary if needed.

## Product decisions and smaller consistency fixes

- Device recovery restarts from the current chunk (`phase-3.md:82`), which can repeat its already audible portion. This conflicts with an unconditional no-repetition promise. Owner decision: accept bounded replay on device change, or preserve a playback offset and verify it.
- Speed through Kokoro is reasonable, but define whether a setting change affects only the next reading or replaces queued audio. Synthesis-time speed cannot change already synthesized buffers the way the inherited time-pitch control does.
- Text cleanup is deliberately lossy (`phase-3.md:27-30`). The earlier assessment supports URL shortening and noise cleanup; new path truncation, code/operator stripping and hyphen joining still need negative fixtures and an explicit intelligibility/fidelity verdict. Do not flatten OCR tables into punctuation before preserving boundaries needed by cleanup.
- Removing voice-app pause, silent empty OCR and the chosen stop gesture fit the recorded direction. Stop still depends on fixing R2/R3. Clarify what canceling an OCR drag does to an already playing passage.
- Phase 5 makes Screen Recording and the region shortcut part of global setup readiness (`phase-4.md:20`, `phase-5.md:58`). Decide whether a selection-only user must configure OCR or can decline it without repeated settings windows.
- The typed `PrivacyLog` API narrows leakage through that API; it does not make all application/dependency logging compiler-safe. Audit speech errors, dependency logs, screenshots and retained text lifetimes too. The proposed test of existing enum cases cannot by itself guarantee every future case is covered.
- Keep the verification runner synchronized when offline and OCR probes arrive. Phase 1 edits only steps 3–6 (`phase-1.md:80`), while phase 5 adds an extra command outside `make verify` (`phase-5.md:63`). Record exact candidate/build identity for runtime results and rerun affected capture probes after the shell/Swift 6 changes.
- Reproduce the app dependency failure before creating/pushing a fork. A standalone package build can exercise targets the app does not use (`phase-3.md:46-51`). Retain the upstream-pin path if the actual dependency builds. This avoids an unnecessary external write without changing the authorized fallback decision.
- macOS 26 is a supported minimum, but this plan's real-Mac evidence is on 27. Record macOS 26 runtime compatibility as unverified until tested; this need not expand the present task to hardware procurement.

## Recommended disposition and handoff

Retain the native architecture, phase order, exact pins, synthetic fixtures, real pasteboard/Vision probes and owner voice judgment. Correct R1–R5 before accepting the implementation contract; resolve R6–R12 in the affected phase specifications. Treat clipboard ambiguity, unsupported mandatory apps, device-change replay and optional OCR setup as explicit decisions where technical evidence alone cannot choose the product behavior. Do not introduce a new backend, test framework or release gate merely for this review.

All findings remain open; this assessment does not modify or accept the plan. Next action is a plan revision and focused rereview, followed by separately authorized phase 1 implementation. The independent investigations completed; runtime behavior remains untested. No app/services/model assets were allocated, and existing caches/preferences were preserved. Only this assessment document was added, uncommitted. Source baseline and all six original plan files remain unchanged.

## Revision 2 focused rereview — 2026-11-15

This section supersedes the original disposition above for revision 2. All six revised files were read. The same two independent reviewers rechecked capture/OCR and speech; the parent checked foundation, shell and cross-phase consistency. Baseline remains `362f9eaf2630feaa27d9bb5e71701fea79b7d06f` on `develop`. The revised plan and this assessment remain uncommitted. No runtime experiment, model download, permission change or implementation occurred during this rereview.

Recommendation: another focused correction is needed before acceptance. Several original findings are addressed at the specification level, but the disposition table's blanket “Fixed” labels overstate closure. These are proposed contracts, not verified implementations.

### V2-1 — High: install writes into the bundle after signing

`phase-1.md:59-63` builds signed, verifies the signature, then writes `Contents/Resources/build-info.json` during installation. This changes the sealed bundle and invalidates the signature the preceding step verified. [Apple's code-signing guidance explicitly requires bundle changes before signing](https://developer.apple.com/library/archive/technotes/tn2206/_index.html).

Generate build-info as a build input/resource before signing. Copy the finished bundle unchanged and verify the installed copy. Keep the external install record outside the bundle. Also make build/install configuration selectable: the phase 3 performance gate requires an installed Release app (`phase-3.md:140`), while the only specified signed install always builds Debug.

### V2-2 — High: clipboard residual risk is disclosed, but the stronger guarantee still contradicts it

`phase-2.md:81` now candidly says a foreign write can be spoken and overwritten. That is a possible owner-accepted limitation, not a fix proving attribution. It conflicts with the phase goal (`:7`) and the main plan's statement that newer content is never overwritten. Label R1 mitigated with a proposed explicit exception, and align the product claims with it. The four confirmed product decisions do not separately establish acceptance of this privacy/data-loss exception.

Two additional races are not covered by that disclosure. At `phase-2.md:66`, the counter is captured after materialization, without a before/after stability check; a write during the snapshot can leave old or mixed saved bytes paired with a newer counter. Fence the snapshot and recheck immediately before Copy, aborting if it changed. At `:69`, the final check and restore are separate operations; another process can write between them. A process-local lock cannot make this cross-process sequence atomic. Narrow the absolute preservation test at `:106` to the exact races it detects, and disclose the remaining final-check race or choose a capture policy that avoids destructive restoration when that risk is unacceptable.

The token rule at `:24` also prohibits stale-token pasteboard writes, while `:74` requires cancellation cleanup to restore. Define a narrowly scoped transaction-cleanup authority that survives cancellation when the clipboard checks permit restoration; do not bypass the new request's normal effect checks wholesale.

### V2-3 — High: opening OCR invalidates the reading it promises to preserve

`phase-2.md:22-25` cancels previous synthesis and rejects its schedules/callbacks whenever a generation begins. `phase-5.md:67` begins that generation on a region press while promising the current reading continues if the drag is cancelled. With the shared token checked at `phase-3.md:81`, only already queued audio may continue; further synthesis is invalidated.

Separate pending capture/region ownership from the committed playback session, promoting a replacement only at the chosen transition. Specify whether replacement occurs on rectangle commit or successful recognition: the phase says commit, but the main stuck-state table says failed/timed-out regions leave the previous reading playing. Test opening the overlay, waiting beyond the entire lookahead, then cancelling; also test empty OCR, timeout and a superseding selection command while a passage plays.

### V2-4 — High: the network recorder proves a narrower claim than “nothing attempts a download”

`phase-3.md:100-106` counts HTTP requests that reach the redirected registry endpoint. A request to any other endpoint is blocked by the sandbox and never reaches that recorder; if its error is swallowed, the test can still pass. The sandbox demonstrates blocked egress, while zero recorder requests establishes no observed request through that route. Neither alone proves no attempted networking anywhere.

Keep this useful test, but name its scope accurately. Audit all reachable download routes at the exact dependency revision, or instrument a common transport boundary that counts attempts before networking. Add a positive control that deliberately makes a request and proves the recorder/runner fails; an unavailable or unobserved recorder must not look like zero requests. Test a swallowed attempted request as a negative control. These are oracle gaps, not evidence that the app currently leaks data.

Use the actual built app's bundled model directory as the fresh-store source. The current probe reads `.local/models` (`:102`), so it does not exercise runtime activation from the shipped bundle. The separate bundle hash check is helpful, but does not exercise that loading path. Record and finish the recorder process/port lifecycle on success, failure and interruption under the resource contract.

### V2-5 — High: sentence lookahead is not a memory or latency bound

`phase-3.md:80-90` allows arbitrarily long sentences, relying on internal auto-chunking. [The pinned manager accumulates internal chunk results and concatenates them before returning from synthesizeDetailed](https://github.com/FluidInference/FluidAudio/blob/v0.18.3/Sources/FluidAudio/TTS/KokoroAne/KokoroAneManager.swift). A large punctuation-free selection can therefore produce a very large app-visible PCM buffer and delay first audio until the entire selection has synthesized. Limiting the number of sentence buffers to four does not bound bytes or duration. Replaying that sentence after a device change can also repeat far more than a few words.

Specify a finite bound on app-visible synthesis work, queued PCM bytes/duration and pending work during replacement. Either expose bounded engine pieces to the scheduler or define a reviewed long-sentence/input-size policy. Retain sentence metadata for the desired recovery behavior. Add a large punctuation-free fixture and verify first-audio, peak memory, cancellation and replay behavior; 2,000 short fake chunks do not cover this case.

### V2-6 — High: same-version model repair and active-store retention are missing

`phase-3.md:57-60` skips reuse when the existing hash directory is corrupt, but then renames staging to that same existing nonempty directory without specifying its replacement. “Repair reinstalls from bundle” is a test name, not a repair algorithm. Define the locked damaged-directory quarantine/replacement operation and rollback on failure.

The next step deletes all older stores. The activation lock does not establish that a synthesizer has stopped using an old store, and immediate deletion removes rollback material. Retain any store with a live reader and the required recovery copy; reclaim only verified owned, unused versions under an explicit retention rule. Test repair of a corrupt existing hash, upgrade during active playback, failed activation and rollback. Atomic activation itself is a good improvement and should remain.

### V2-7 — Medium: the ASR oracle can pass the specific internal-boundary loss it aims to catch

`phase-3.md:116-122` permits 10% word error and checks only sentence first/last words. An internally split 100-word sentence can lose several internal boundary words, retain its outer endpoints, and still pass. Recognition is also a fallible measurement: it can misrecognize correct speech or infer words that were not audible. Do not describe this alone as proof that every sentence is complete.

Keep the Release production probe and listening audit. Calibrate the proposed ASR check with known-good audio and deliberately corrupted outputs: missing first/last words, missing internal chunk-edge words, repeated words, reordered pieces and silence. Define normalized spoken expectations for numbers/acronyms rather than comparing only raw written forms. Pin the test recognizer and record whether each negative control is detected before adopting thresholds. A new test-model download remains a separately approved choice; it is not necessary merely to declare the original review closed.

### V2-8 — Medium: phase 2 requires playback before the plan supplies a voice

`phase-1.md:85` prohibits model download until phase 3, but `phase-2.md:96` requires a playing reading for its stop matrix. Its Debug probe explicitly plays no speech (`:94`). On the described clean machine these conditions cannot all be satisfied.

Use a clearly labelled deterministic playback test seam for phase 2 routing, then repeat real audible stop/replace cases after the bundled voice exists in phase 3. Alternatively, explicitly plan an earlier authorized voice setup. Do not count a no-speech capture probe as real playback evidence.

### V2-9 — Medium: a timeout does not itself stop Vision or release its image

`phase-5.md:53-55` promises a ten-second timeout, one OCR at a time and image release on every path, but does not state how the native request is cancelled or joined. A task racing a timer can continue using the image after its caller returns; a structured task group can instead wait for the slow child and defeat the timeout. The gate's real Vision probe should cover the chosen cancellation mechanism. Keep the one-request slot occupied until native work has actually terminated, reject stale results, and describe any limit on prompt teardown honestly. Use a deterministic blocked recognizer to test caller timeout versus worker lifetime, plus a native cancellation probe.

### Smaller corrections and decisions

- In `phase-2.md:94`, clipboard byte equality needs to specify whether the two deliberately added restore-marker types are excluded. “All original representations preserved, only these markers added” is testable; strict type-set equality conflicts with the restore design. Likewise label fixture text equality after whitespace normalization accurately.
- A 150 ms snapshot budget (`phase-2.md:66`) needs an enforcement strategy for a slow synchronous promised-data provider. Checking elapsed time after it returns does not bound UI blocking. Avoid main-thread materialization where the API contract permits, and distinguish a target budget from a guaranteed deadline.
- The model log audit (`phase-3.md:72`) has no resolution when logging cannot be disabled and upstream compiled successfully, so no fork exists. Add an explicit stop/decision path; do not leave a privacy finding implicitly accepted because the fork condition was unrelated.
- Preserve/restore preferences with the app stopped and an interruption-safe restoration procedure (`phase-4.md:58`). Keep the backup until restored values are verified. Define the originally absent domain case.
- Silent transient OCR errors are a product choice. Persistent capture/Vision failures would otherwise leave an invisible feature doing nothing indefinitely. Record the chosen behavior for repeated failure; a nonintrusive diagnostic in existing settings is an option, not an instruction to add a new window.

### Updated original-finding disposition

| Original finding | Revision 2 assessment |
| --- | --- |
| R1 | Partial; honest residual disclosure, but snapshot/final-check races and conflicting absolute claims remain (V2-2). |
| R2 | Addressed at plan level by empty-selection classification, Copy policy and per-app tests. Runtime compatibility remains for implementation. |
| R3 | Partial; stale-result design improved, but cancellation cleanup and pending-region behavior conflict (V2-2/V2-3). |
| R4 | Partial; cold/warm/damaged stores and every voice are specified; recorder claim and bundle-source path remain (V2-4). |
| R5 | Release production-code coverage addressed; semantic oracle still needs negative controls (V2-7). |
| R6 | Partial; versioning and activation improved; repair/reader lifetime/retention remain (V2-6). |
| R7 | Shared-cache absence and preference destruction concerns substantially addressed; finish the operational details above. |
| R8 | Addressed at plan level by mandatory surfaces, waivers and fixture comparison; phase-order contradiction remains (V2-8). |
| R9 | Partial; thresholds and owner verdict added, but actual work units are unbounded (V2-5). |
| R10 | Feasibility/exclusion/teardown plan substantially improved; actual cancellation lifetime remains (V2-9). |
| R11 | Addressed at plan level by scoped conflict claims, an entry probe and login states. |
| R12 | Permission-survival tests addressed; new post-signing mutation must be fixed (V2-1). |

The mandatory capture set, conservative cleanup, next-reading speed change and optional OCR setup are consistent decisions. Sentence restart and region-cancel behavior are also coherent product choices once the lifecycle/bounds contradictions above are resolved. Preserve these decisions rather than reopening the architecture.

Handoff: V2-1 through V2-9 remain open. Revise the affected contracts and original disposition labels, then rereview those changes only. The six plan files were not changed by this review. Both independent reviewers completed; no required reviewer result is missing. Only this assessment was extended. No task service was started, and no application data or remote state was changed.

## Revision 3 focused rereview — 2026-11-15

This section supersedes revision 2's open-finding list. All six revision 3 files were read, with the same independent capture/OCR and speech reviewers. The review stayed at the planning boundary. No app, recorder, sandbox experiment or model was run/downloaded by this review. The plan's sandbox experiments remain author-reported evidence, with executable positive controls required in phase 3. The installed `ditto(1)` manual was read to check the revised install operation.

The earlier contradictions are substantially resolved. V2-2 is now an explicitly accepted residual-risk disposition under owner decision 9; this review does not reopen that tradeoff. V2-3, V2-6, V2-7, V2-8 and V2-9 have adequate plan-level remedies. V2-1 fixes post-signing writes and adds Release installation; V2-4 fixes the main-process swallowed-network-error oracle with kill-on-deny and controls. These are specification closures, not runtime passes.

Four localized corrections remain. No architecture revision is recommended.

### V3-1 — Medium: complete and enforce the synthesis bounds (V2-5 partial)

`phase-3.md:92` splits only at whitespace or pause punctuation. A preserved hash, identifier or other unbroken token longer than 400 characters has no defined outcome. Specify a guaranteed-progress hard split at a safe string boundary when no preferred boundary exists, or an explicit rejection policy. Test a long token with no whitespace, including the first-unit 160-character limit.

At `phase-3.md:102`, an audio result over 35 seconds fails a contract test, but production behavior is unspecified. Written character count does not itself guarantee spoken duration across normalization, voices and speeds. Enforce duration/frame limits in the production adapter/scheduler before enqueueing; define an oversize-result outcome that does not silently truncate speech. Test an injected oversize result and the supported speed range. Keep the existing single-in-flight rule and long unpunctuated fixture.

The 13.4 MB arithmetic is reasonable for 140 seconds of 24 kHz mono Float32 resident playback PCM, but it is not a total process-memory bound. It excludes the in-flight engine result, intermediate concatenation/copies, model memory and other allocations. Label it accordingly. Rejecting an oversized result after synthesis bounds admission to playback, not the allocation already made by the engine. Preserve the measured peak-memory gate rather than claiming that a character cap proves that whole-process limit.

### V3-2 — Medium: reject cancelled input before Copy

`phase-2.md:67-79` checks pasteboard state, PID and focus, but does not check whether the input is still current before invoking Copy. An input cancelled while waiting for the serial lock or a promised-data snapshot can still meet those checks and send Copy.

Check current input ownership when acquiring the transaction and immediately before `copyAction`. Add cancellation-while-waiting and cancellation-during-snapshot tests proving no Copy occurs. Keep the separately authorized cleanup after Copy exactly as designed; this correction applies only before that effect starts.

### V3-3 — Medium: reserve the OCR slot before capture awaits

`phase-5.md:53-54` checks the slot, awaits capture, and only then takes the slot. Another input can begin during capture and also observe it free; a superseded capture can finish late and start native work.

Reserve atomically before capture, release on capture failure/cancellation, and recheck the token before starting Vision. Extend the existing blocked-recognizer tests with a blocked capturer whose stale completion arrives after another input. The worker's post-timeout ownership of image/slot is otherwise correctly specified.

### V3-4 — Medium: replace the installed bundle rather than merge it

`phase-1.md:61` uses `ditto` directly onto the existing app path. The installed `ditto(1)` DESCRIPTION states that existing destination directories are merged. Removed resources can survive an upgrade, so the installed bundle is not necessarily the unchanged built bundle; strict verification can then fail. The plan correctly refuses to launch a failed copy, but it can leave the working install replaced by an invalid one.

Copy to a fresh task-owned staging path, verify it, then replace the known installed bundle with the staged bundle while preserving a recoverable previous copy until installed verification succeeds. Scope replacement to the recorded app identity/path. Add an install check in which a resource present in the previous build is removed in the next; it must not remain installed. This is a small correction to the existing install procedure, not a new distribution mechanism.

### Implementation-scope notes, not additional redesign requests

- The store lease registry is in-process (`phase-3.md:60`). Explicitly enforce a single production-store consumer process or account for reader leases across processes before reclamation. Probe stores are already isolated; do not add cross-process machinery if a verified single-consumer contract suffices.
- If the network evidence retains “and its children” (`phase-3.md:124`), the harness must observe denied child termination too, or the source audit must establish that no child performs network work. A child being killed does not by itself force its parent to fail. This does not invalidate the improved main-process oracle.
- Clean up two stale labels: the main architecture/consumer sweep still says `SentenceChunker` instead of `UnitChunker`, and the final handoff still says rereview revision 2. These are documentation nits.

### Disposition and handoff

| Revision 2 finding | Revision 3 disposition |
| --- | --- |
| V2-1 signing | Post-signing mutation closed at plan level; V3-4 covers the newly concrete copy operation. |
| V2-2 clipboard | Mitigated with explicit owner-accepted residual risk; no renewed approval requested. |
| V2-3 region/playback | Closed at plan level; pending input and committed playback are separate. V3-2/V3-3 tighten effect admission. |
| V2-4 network oracle | Main-process oracle specified adequately with controls and source audit; retain the stated scope and child-accounting note. |
| V2-5 bounds | Partially addressed; V3-1 remains. |
| V2-6 model repair/retention | Closed at plan level for the stated in-process consumer model; make that scope explicit. |
| V2-7 recognition | Closed at plan level; calibrated informational/gating distinction and listening gate are truthful. |
| V2-8 voice phase ordering | Closed at plan level; silent routing seam followed by real audible checks. |
| V2-9 OCR lifetime | Closed at plan level; timeout and native lifetime are separate. V3-3 corrects slot admission. |

Recommendation: make V3-1 through V3-4 explicit, then the plan can proceed to owner acceptance without another broad review. Verify these localized edits only. No implementation or phase acceptance is granted by this review. The same reviewers completed the focused assignments; all six plan files remain unchanged by the reviewer, and only this assessment was extended. No task resources were allocated or cleaned up.

## Revision 4 localized check — 2026-11-15

Recommendation: ready for owner acceptance. No remaining blocking plan finding was identified in the requested localized check. This disposition supersedes revision 3's open-finding list. The parent checked the four affected phase contracts and the main plan's scope/disposition updates against the completed independent revision 3 reviews; no new independent broad review was run or needed.

Baseline remains `develop` at `362f9eaf2630feaa27d9bb5e71701fea79b7d06f`. The plan files and this assessment are uncommitted. This was a document review, not execution of the planned gates.

| Finding | Revision 4 disposition |
| --- | --- |
| V3-1 synthesis bounds | Closed at plan level. Phase 3 specifies hard splitting when no preferred break exists, runtime duration admission, bounded subdivision with a visible terminal error, and tests for these cases. Resident playback PCM is distinguished from engine and whole-process allocations. |
| V3-2 cancellation before Copy | Closed at plan level. Phase 2 checks input currency on lock acquisition and immediately before Copy; cancellation tests cover waiting and snapshotting. Post-Copy cleanup remains separately scoped. |
| V3-3 OCR admission | Closed at plan level. Phase 5 reserves before asynchronous capture, releases on failed/cancelled capture and rechecks the input before Vision. Blocked-capturer tests cover stale completion. |
| V3-4 install replacement | Closed at plan level. Phase 1 verifies an empty staged bundle, replaces rather than merges the installed copy, retains rollback and verifies the installed result. The removed-resource check directly covers the previous defect. |
| Store consumer scope | Closed at plan level by the lifetime exclusive consumer lock and isolated probe roots. Implementation must acquire this lock before any operation that can repair or reclaim production-store data, and retain it for the promised lifetime. |
| Network claim scope | Closed at plan level: the dynamic claim is restricted to the probe, with no intentional child processes and a source audit for delegated transports. A final process-tree snapshot alone cannot prove historical absence of short-lived children; keep that evidence limitation explicit when implementing the audit/harness. |

The accepted clipboard exception in decision 9 remains an accepted limitation, not a claim of perfect clipboard preservation. Native OCR cancellation, signing/permission survival, real-app capture, network controls, voice quality and performance remain phase acceptance tests. No runtime result is implied by closing a plan finding.

One nonblocking wording correction remains: the main plan's final `Next` bullet at line 233 still says “focused re-review of revision 2.” It should refer to owner acceptance of revision 4 and then phase 1. `UnitChunker` and the revision 4 disposition labels are otherwise updated. This wording does not require another review cycle.

Handoff: the plan is ready for Juan's acceptance and a fresh phase 1 implementation session under its stated prerequisites. This review does not itself authorize account changes, package installation, implementation, publication or release. Only this assessment was extended; the six plan files were left unchanged. No model, app, task service or signing operation was run, and no remote state or persistent application data was changed.
