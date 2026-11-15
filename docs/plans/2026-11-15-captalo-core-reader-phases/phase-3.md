# Phase 3: Speech

Parent: [Cáptalo core reader plan](../2026-11-15-captalo-core-reader.md).

## Goal

A pleasant Kokoro reading of any captured passage, ten minutes or longer, from voice files bundled in the app. The phase proves three claims separately and states the scope of each (review R4, V2-4):

1. The built app's bundle is complete.
2. Synthesis succeeds offline from a fresh store activated from that bundle.
3. The probe process makes no network attempt. This covers the probe process itself (it starts no child processes); transports in other processes are covered only by a source audit.

Optimized builds are exercised on the production speech code (review R5). Completeness is judged by the owner's listening audit, supported by a calibrated recognition check (V2-7). Memory and latency are bounded per synthesis unit (V2-5). The owner's ear and the owner's verdict on the measured performance are the final gates.

## Entry conditions

- Phase 2 accepted.
- Recheck FluidAudio releases. If a release newer than `v0.18.3` builds with Xcode 27 and contains both `5fff83ae` and its fix `16780f04` (or neither), stop and ask whether to use it.
- Approved downloads: the Kokoro asset set for bundling (about 92 MB). The test-only local speech-recognition model (never bundled) needs its own approval after its size is shown. Without that approval, the recognition check is skipped and recorded as not run; the listening audit is the completeness gate either way.
- A fork write (`juan294/FluidAudio` plus one branch) happens only if unit 3B step 1 fails, and only after the owner confirms in this session.

## Units

### 3A Text preparation `[batch-eligible]`

New files only: `Packages/CaptaloCore/Sources/CaptaloCore/Text/` and its tests. No overlap with 3B.

```
@ TextPreparer.prepare(blocks, source) -> lazy sequence of Paragraph   // Block = paragraph | listItem | tableRow([cell]) | codeLine
ctx: pure; source ∈ {selection, ocr}; selection text is split into Blocks lazily on blank lines, list markers, table rows
do:
  1. normalize line endings, NBSP, zero-width characters
  2. strip Markdown emphasis, heading marks, list bullets, code-fence lines, table pipes; links keep label
  3. remove ANSI sequences, box-drawing runs, separator runs (≥ 4 of -=_*~), prompt symbols at line start
  4. URLs -> host name
  5. if source == ocr: rejoin letter-hyphen-linebreak-lowercase words
  6. sentences via NLTokenizer within each Block; Block boundaries stay paragraph boundaries
br: result empty -> .nothingSelected (silence)
```

Owner decision 7 keeps paths, code operators and hashes as written. Each rule has a positive and a negative fixture, for example: `a * b` stays and `*word*` loses its asterisks; `x -> y` stays; `well-\nknown` from a selection is not rejoined; a `$` inside a line stays and a `$ ` prompt at line start is removed; a `>` Markdown quote marker is removed but `a > b` stays. The fixtures are synthetic and committed, and include upstream issue 5 (`**Hello there**`) and a Markdown table in row order (upstream issue 1).

### 3B FluidAudio pin, model store and probe `[batch-eligible]`

Files: project package references, `Package.resolved`, `Packages/CaptaloSpeech/`, `Scripts/fetch-models`, `Models.manifest.json`. No overlap with 3A.

```
@ pin FluidAudio
do:
  1. pin app + CaptaloSpeech to upstream v0.18.3 exact revision; build app Debug and Release with Xcode 27
  2. if it builds -> done; record "no fork needed"
  3. else record exact errors; owner confirms fork; fork, branch captalo/v0.18.3-xcode27 from tag
  4. patch only the failing CoreAI files (guard or exclude); build + FluidAudio TTS tests on branch
  5. push branch; pin by exact revision
risk: pin by revision only (assessment §1: inherited pin tracks main)
```

```
@ ModelStore.activate(sourceDir, manifest) -> StoreState
ctx: root ~/Library/Application Support/com.thecreativetoken.captalo/Models (injectable); flock root/.lock for activation; root/.consumer.lock held for the consumer's lifetime; in-process LeaseRegistry
do:
  1. validate sourceDir against manifest (size + sha256 per file); fail closed
  2. if root/<hash>/ exists and validates -> write root/current atomically, done
  3. check free space ≥ manifest total + 10%; copy to root/.staging-<uuid>/; validate copy
  4. if root/<hash>/ exists (damaged): rename it to root/.quarantine-<hash>-<uuid>/; rename staging -> root/<hash>/; on failure rename quarantine back (rollback) and report
  5. write root/current atomically; then reclaim per retention rule
br: free space short -> .installFailed(needBytes); staging removed
br: interrupted (crash) -> next activate removes .staging-*; restores a lone .quarantine-* if root/<hash>/ is missing, else removes it
fx: writes only under root
```

- **Single consumer per store.** One process uses a store root at a time. At engine start, `KokoroSynthesizer` takes an exclusive, non-blocking lock on `root/.consumer.lock` and holds it until the process exits. A second Cáptalo instance that cannot take the lock exits immediately and logs `PrivacyLog.secondInstance`; the first instance keeps running. The lock is taken before any operation that can repair, quarantine or reclaim production-store data. The probe always uses its own isolated root. Leases are therefore in-process only, and there is no cross-process lease machinery.
- **Reader leases.** `KokoroSynthesizer` takes a lease on its store directory for as long as it holds a `KokoroAneManager` on that directory. A damaged directory that is still leased is not quarantined until the lease ends. The current reading stops with `.voiceError`, the lease is released, and then repair runs.
- **Retention.** Keep the current version, the most recent previous valid version (for rollback), and any leased version. Reclaim only other `<hash>` directories, quarantines older than the current activation, and staging leftovers, all inside `root`. An upgrade during playback activates the new version for the next reading. The old one is reclaimed after its lease ends and it is no longer the rollback copy.
- `Models.manifest.json` is committed. It lists every file KokoroAne needs: the seven stages, vocab, the G2P assets, `us_lexicon_cache.json` and every bundled voice pack, each with path, size and sha256. `Scripts/fetch-models` downloads once into `.local/models/` with HOME redirected (as in the 2026-11-14 listening test) and **verifies against the committed manifest**. It never writes hashes. Changing the manifest is a separate, reviewed `make update-model-manifest` step that shows the diff.
- The Xcode build phase copies `.local/models/` into `Contents/Resources/Models/` before signing. `make bundle-check` validates the built and the installed app's `Resources/Models` against the manifest.
- `KokoroSynthesizer` (in `CaptaloSpeech`): before any FluidAudio call, set `ModelRegistry.baseURL` to the configured blocked endpoint (production `http://127.0.0.1:9`; the offline test uses the recorder port), validate the current store, and only then construct `KokoroAneManager(directory: current)`. With every manifest file present, `ensureEnglishLexicon` and the other ensure paths return before fetching (`KokoroAneResourceDownloader.swift:415-426`).
- Writes inside the store: phase 3 measures which files FluidAudio creates in a fresh store (for example converted voice layouts). The allowed generated set is committed in the manifest's `generated` section, and any other new file fails `make offline-test`. The stages load as precompiled `.mlmodelc` (`KokoroAneModelStore.swift:265`), so no compile cache is assumed.
- Remove the download UI and the `TtsCacheDirectory.ensure()` call (`Sotto/Services/SpeechControllerKokoro.swift:11`). The app never downloads.
- Licences: record the Kokoro weights, voices and FluidAudio conversion licences in `THIRD_PARTY_NOTICES.md` as read at fetch time. If any bundled asset does not allow redistribution, stop and report it.
- **Source audit at the pin.** Search FluidAudio's Kokoro, shared TTS and download sources for:
  - every network entry point reachable from `KokoroAneManager`, and any background or out-of-process `URLSession` configuration;
  - logger calls that interpolate input or normalized text.

  The results are recorded in this phase's evidence. A background or out-of-process transport is a stop condition: report it, and the owner decides. A content-logging call at default level is disabled through FluidAudio's logging configuration. If it cannot be disabled and no fork exists, **stop and report**; the owner decides between a fork patch and an explicit, recorded acceptance. The finding is never left implicit.

### 3C Reading pipeline (after 3A and 3B are integrated)

```
@ ReadingSession.run(sessionToken, paragraphs, voice, speed)
ctx: Synthesizer + AudioSink protocols; RequestCoordinator session token; PrivacyLog
do:
  1. UnitChunker: one unit per sentence; sentences > 400 chars split at last whitespace/pause punctuation before 400; if none, hard split at the last grapheme-cluster boundary at or before 400; first unit ≤ 160 chars by the same rules; produced lazily
  2. synthesize with lookahead ≤ 3 units beyond the audible one; check result duration ≤ 35 s before enqueue; sessionToken.isCurrent before each schedule
  3. append 0.30 s silence after each sentence end and 0.35 s more after each paragraph end (re-judged in listening)
  4. release each PCM buffer after its played-back callback; track audible unit from callbacks; keep sentence and paragraph ids per unit
  5. on AVAudioEngineConfigurationChange: restart engine, reschedule from start of audible unit (owner decision 6)
br: result > 35 s -> .oversizeResult: discard it, split the unit in two at its preferred (else hard) boundary, re-synthesize both pieces in order; repeat down to a 40-char minimum
br: a minimum-size piece still > 35 s -> end session after scheduled audio, report .voiceError (never silent truncation)
br: synthesis throws -> let scheduled audio finish, end session, report .voiceError
br: stop or replace -> player stops at once (silence); the in-flight unit result is discarded when it returns
fx: audio only; no text persisted
```

- **Bounds.** At most one in-flight synthesis call, of at most 400 characters, so every unit makes progress even through an unbroken token. Every result is checked against the 35 s limit at run time before it is enqueued (`.oversizeResult` above), for every voice and speed. At most 3 synthesized units are queued (`maxQueuedSeconds = 105`). Pending work after a replacement is at most the one in-flight unit, discarded on return.
- **What the bound covers.** The audible unit plus 3 queued units hold at most 140 s of resident playback PCM, about 13.4 MB of 24 kHz mono Float32. This is not a process-memory bound: it excludes the in-flight engine result and its intermediate copies, model memory and other allocations. Rejecting an oversize result limits what enters playback, not what the engine already allocated. The whole-process limit is the measured peak-memory gate below.
- FluidAudio's internal 510-phoneme auto-chunking still applies within a unit (`KokoroAneManager.swift:294-330`), but its concatenated result is bounded by the unit size.
- Speed is Kokoro's `speed:`, fixed per reading. `AVAudioUnitTimePitch` is removed.
- The voice picker in the existing window lists the bundled voices, with a sample button for each.

### 3D Probes (Release-built, production code)

`captalo-speech-probe` is an executable in `CaptaloSpeech`. It uses the same `ModelStore`, `KokoroSynthesizer`, `TextPreparer` and `UnitChunker` as the app. It is built and run with `-c release` (and also in Debug).

```
@ make offline-test
ctx: run dir .local/offline-test/run-<UTC>/ {HOME/, store/, recorder.log, pids.json}; recorder = python3 -I loopback HTTP logger on a free port; profile: (deny network-outbound (with send-signal SIGKILL)) + allow localhost:<recorder>
do:
  1. start recorder; write its PID and port to pids.json; positive controls: probe -ControlRecorderRequest must be logged by the recorder; probe -ControlExternalRequest must be killed (exit 137); both must hold or the test fails
  2. fresh store: probe activates store from the built app's Contents/Resources/Models into run/store, under the profile, HOME=run/HOME
  3. synthesize the speech fixture for every bundled voice; then warm run with the same store
  4. damaged runs: copy store, delete one file / corrupt one hash -> probe must refuse before engine init, with no kill and no recorder request
  5. assert: every probe exit 0 (any SIGKILL = network attempt); recorder log has 0 requests besides the control; store files ⊆ manifest ∪ generated; run/HOME/.cache absent
fx: on every exit (trap: success, failure, interrupt): stop the recorder by its recorded PID only, then keep the run dir on failure, remove it on success
```

- The probe never starts the installed app, and the installed app never touches the run directory. The fresh store therefore cannot be warmed beforehand.
- Claim wording in evidence: "no network attempt by the probe process under the deny profile, and no request through the registry route". The probe starts no child processes (the source audit checks for `Process` and `posix_spawn` use in `CaptaloSpeech`, and the harness asserts that the probe has no children when it exits). A final process-tree check cannot prove that no short-lived child ever existed; the source audit carries that part, and the evidence states this limit. Out-of-process transports are covered by the source audit only.

```
@ make completeness-test
ctx: Release probe; fixtures speech-completeness.txt and speech-long-unpunctuated.txt; optional local recognizer (test-only, pinned version) in .local/test-models/
do:
  1. probe emits per unit: unit id, sentence id, phoneme scalar count, engine normalizedText, audio duration, completed flag
  2. assert every unit completed exactly once in order; no unit audio > 35 s; queued seconds never > maxQueuedSeconds
  3. long-unpunctuated fixture (≈ 20,000 chars, no punctuation): record first-audio time, peak memory, stop latency mid-reading, replay span after a simulated device change
  4. if recognizer approved: calibrate before gating (below)
fail: missing, reordered or oversize unit, queue bound exceeded -> non-zero exit
```

**Recognition calibration (review V2-7).** The expected spoken form is the engine's `normalizedText` per unit, not the written text. Controls are built from known-good audio using recognizer word timestamps: a missing first word, a missing last word, a missing word at an internal auto-chunk edge, a repeated word, two swapped pieces, and silence. A word-aligned deletion and insertion count is computed per unit. The check becomes a gate only if a threshold passes all known-good units and detects every control, and that threshold is recorded with the recognizer version. Otherwise the check is recorded as informational, and only the listening audit gates completeness. Recognition is a measurement, not proof that every word was spoken.

## Success criteria

### Automated (`make verify`, including `bundle-check`, `offline-test`, `completeness-test`)

- [ ] `TextPreparerTests`: every positive and negative fixture matches. Removing the emphasis rule makes `markdownEmphasisNotSpoken` fail.
- [ ] `UnitChunkerTests`: `oneUnitPerShortSentence`, `longSentenceSplitAtLastBreakBefore400`, `unpunctuatedTextSplitAtWhitespace`, `unbrokenTokenOver400HardSplitAtGraphemeBoundary`, `unbrokenTokenInFirstUnitHardSplitAt160`, `hardSplitNeverBreaksAGraphemeCluster`, `firstUnitCappedAt160`, `noUnitCrossesParagraph`, `lazyProductionDoesNotPreparePastLookahead`. The phase 1 characterization tests are retired, and the retirement is noted in the commit.
- [ ] `ReadingSessionTests` (in-memory Synthesizer and AudioSink):
  - `synthesisNeverRunsMoreThan3Ahead`, `atMostOneInFlightUnit`, `queuedSecondsNeverExceedBound`
  - `playedBuffersAreReleased` (retained buffers ≤ 4 across 2,000 units)
  - `allUnitsPlayedExactlyOnceInOrder`, `deviceChangeReplaysCurrentUnitOnly`
  - `chunkFailureEndsSessionAndReportsVoiceError`
  - `oversizeResultIsSplitAndReSynthesizedInOrder`, `minimumPieceStillOversizeEndsWithVoiceError`, `oversizeResultNeverEnqueued`
  - `stopDuringFirstSynthesisSilencesAtOnceAndDropsResult`, `repeatedReplacementLeavesOneSession`
  - `staleCallbackAfterEngineRestartIgnored`, `speedChangeAppliesFromNextReading`
- [ ] `ModelStoreTests` (temp directories; disk-full injected at the owned file-copier boundary):
  - `freshInstallActivatesAtomically`, `interruptedStagingIsRemovedAndRetried`
  - `corruptExistingHashIsQuarantinedAndReplaced`, `failedReplacementRollsBackQuarantine`, `loneQuarantineRestoredAfterCrash`
  - `leasedStoreIsNotQuarantinedOrReclaimed`, `upgradeDuringPlaybackActivatesForNextReading`, `retentionKeepsCurrentPreviousAndLeased`
  - `damagedStoreRefusesBeforeEngine`, `repairReinstallsFromBundle`, `secondConsumerCannotTakeStoreLock`
  - `diskFullReportsNeededSpaceAndLeavesNoStaging`, `concurrentActivateInstallsOnce`, `fetchScriptRejectsBytesNotMatchingManifest`
- [ ] `KokoroContractTests` (real frontend, Release and Debug): a 400-character unpunctuated unit synthesizes in one result under 35 s at the slowest and fastest supported speeds for every bundled voice, or triggers the oversize split and still completes. A number, a file name, an acronym and a URL each yield non-empty phonemes and `normalizedText`.
- [ ] `make offline-test` passes for every final bundled voice, both positive controls behave as expected, and the recorder is stopped on every exit path.
- [ ] `make completeness-test` passes its structural checks. The recognition check's gating status and threshold are recorded.
- [ ] `Package.resolved` pins FluidAudio by exact revision, and the fork-or-upstream choice and the source-audit result are recorded.

### Manual (owner)

- [ ] **Ten-minute listening.** A committed synthetic fixture of about 1,500 words (numbers, a file name, an acronym, a URL, a Markdown list and a short terminal excerpt), read in every bundled voice at 1.0x, plus one voice at 1.2x, from the installed Release app. The owner confirms the voice is comfortable and the pauses are natural, and audits sentence beginnings and endings while listening. A working voice the owner dislikes fails. Listen for robotic onsets (PR #1135) and record what is heard.
- [ ] **Audible stop and replace (review V2-8).** In the six mandatory apps, repeat phase 2's stop (same text, and confirmed empty) and replace cases with real speech.
- [ ] **Cleanup intelligibility.** The owner listens to the cleanup fixtures and confirms that the conservative rules are intelligible and keep the needed detail.
- [ ] **Performance verdict.** Measured from `make install CONFIG=Release`:
  - cold first audio after launch;
  - warm first audio for a one-sentence selection;
  - stop press-to-silence;
  - memory each minute over the ten-minute reading;
  - first audio and peak memory for the long unpunctuated fixture.

  Proposed targets: warm first audio ≤ 1.0 s, stop ≤ 150 ms, memory at minute 10 ≤ 1.2 × minute 2 (plateau). The owner accepts the numbers, or the phase continues.
- [ ] Unplug or switch headphones mid-reading: playback continues on the new device, from the start of the unit that was playing.
- [ ] Wi-Fi off: a normal reading of a Safari selection works.
- [ ] Shared cache: the real `~/.cache/fluidaudio` record before and after the manual session is identical (no requirement that it not exist, review R7).
- [ ] The owner confirms the final bundled voice list. The manifest, the picker and the per-voice evidence match it.

## Handoff to phase 4

The pin choice (upstream or fork revision and patch), the source-audit result, the manifest hash and generated set, the voice list, the unit and queue limits as built, the recognition-check status, the performance numbers with the owner's verdict quoted, and the listening verdicts quoted.
