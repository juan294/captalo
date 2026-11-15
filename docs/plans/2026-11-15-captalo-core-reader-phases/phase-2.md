# Phase 2: Capture

Parent: [Cáptalo core reader plan](../2026-11-15-captalo-core-reader.md).

## Goal

Replace the inherited reader (baseline §3, `Sotto/Services/SelectionReader.swift:18-93`) with the approved layered reader (assessment §3). Cáptalo speaks only text that the evidence shows is the user's selection. When Copy is needed, a fenced clipboard transaction restores the user's clipboard whenever its checks show that this is safe. The races the checks cannot detect are the owner-accepted exception in decision 9. The phase produces a whitespace-normalized exact-text matrix over 12 apps, with a mandatory subset (owner decision 5).

## Entry conditions

- Phase 1 accepted. The fixed install has a stable designated requirement.
- The owner grants Accessibility to `/Applications/Captalo.app` once.

## Design

### Pending input and committed playback (review R3, V2-3)

```
@ RequestCoordinator
ctx: actor; at most one PendingInput and one PlaybackSession; owned Task handles
do:
  1. beginInput(kind, source) -> InputToken: cancels the older PendingInput only (never the session)
  2. InputToken = {inputGeneration, kind, sourcePID, sourceBundleID, focusedElementRef, startedAt}
  3. resolve(token, outcome): drop if token superseded; else route:
       .text -> promote: stop current session, start new PlaybackSession (sessionGeneration += 1)
       .stopGesture -> stop current session
       .nothingSelected / .unsupported / failures from region -> no session change
  4. session stages check sessionToken.isCurrent before each audio schedule; callbacks of older sessions dropped
br: quit -> cancel PendingInput, let any open ClipboardTransaction finish its cleanup, stop session
```

- `speakSelection()` (the untracked `Task` at `Sotto/App/SottoAppStatePlayback.swift:13`, renamed in phase 1) becomes `beginInput(.selection)` followed by capture and `resolve`.
- The selection stop gesture is decided in `resolve`. `.text` equal to the current session's captured text (by hash) and `.nothingSelected` from a confirmed empty selection both map to `.stopGesture`.
- Phase 2 has no voice yet. A playing session in this phase uses `SilentTimedSynthesizer`, a Debug-only seam that produces silent buffers of a fixed 30 s length and logs state transitions. It is labelled as a seam in all evidence. Audible stop and replace are repeated in phase 3 (review V2-8).

### Selection evidence (review R2)

```
@ AXSelectionLayer.read(token) -> SelectionEvidence
ctx: AXUIElement of token.focusedElementRef
do:
  1. AXSelectedText; then AXSelectedTextRange + AXStringForRange; then WebKit text-marker range + string
  2. Chromium/Electron (bundle list): set AXManualAccessibility once per app launch, retry step 1
  3. classify result
br: non-empty text -> .selected(text)
br: range attribute supported and length 0, or AXSelectedText supported and "" -> .confirmedEmpty
br: attributes unsupported, AX error, no focused element -> .unavailable
risk: never set AXEnhancedUserInterface (assessment §3)
```

```
@ CaptureCoordinator.capture(token) -> CaptureOutcome
do:
  1. if not AX-trusted -> .permissionMissing (no layer runs)
  2. evidence = AXSelectionLayer.read
  3. .selected -> .text(layer: ax); .confirmedEmpty -> .nothingSelected (never Copy)
  4. .unavailable and CopyPolicy.allowsCopy(bundleID) -> menu Copy layer, else synthetic Copy (only when the app has no Copy item)
  5. .unavailable and copy not allowed -> .unsupported(.copyMayNotReflectSelection)
br: Copy menu item disabled -> .nothingSelected (no key event)
```

`CopyPolicy` is a committed list of bundle IDs where Copy can produce content without a selection. It is seeded with `com.microsoft.VSCode` (documented `editor.emptySelectionClipboard`, default on), and any matrix app that shows this behavior is added. Other apps' preferences are never changed.

### Clipboard transaction (review R1, V2-2)

```
@ ClipboardTransaction.run(inputToken, copyAction) -> ClipboardResult
ctx: NSPasteboard.general; process-wide serial lock; runs off the main thread where the pasteboard API permits (checked against Apple docs at implementation)
do:
  0. on acquiring the serial lock: inputToken still current, else return .cancelled (no snapshot, no Copy)
  1. fence snapshot: c0 = changeCount; materialize data for every type of every item; c0' = changeCount; target budget 8 MB and 150 ms
  2. recheck right before Copy: inputToken still current, changeCount == c0, frontmost PID == token.sourcePID, focused element unchanged; then copyAction()
  3. window W = 1 s: wait for changeCount > c0; attribute only if exactly c0 + 1 when read
  4. read .string; then the final check: changeCount still c0 + 1 -> restore snapshot with transient + auto-generated markers
  5. return .copied(text) only after the restore write succeeded
br: c0 != c0' (write during snapshot), budget exceeded, or a type fails to materialize -> .notPreservable; copyAction never runs
br: input cancelled at step 0 or 2 -> .cancelled; copyAction never runs; nothing to clean up
br: change before Copy at step 2 -> .ownershipUncertain; copyAction never runs
br: no change within W -> .noCopyResult; nothing restored
br: changeCount > c0 + 1, or changed between read and final check -> .ownershipUncertain; no speech, no restore
fail: restore write fails -> .restoreFailed; no speech; PrivacyLog.restoreFailed
risk: final check and restore are two operations; a foreign write between them is overwritten (decision 9b)
```

- **Cleanup authority.** Before `copyAction`, cancellation always wins, and no Copy is sent. Once `copyAction` has run, the transaction holds a cleanup capability that is separate from the input token. It authorizes only steps 3-4 of this transaction (attribution and one restore write, under the same checks). It survives cancellation and quit, and it grants no other effect. If the input is cancelled, the text is discarded after cleanup.
- **Snapshot budget.** 150 ms is a target, not a guaranteed deadline. A synchronous promised-data provider in the source app can block materialization for longer. The elapsed time is checked after materialization returns, and an over-budget snapshot aborts before Copy. The time the source app's provider takes is recorded in the matrix.
- **Accepted residual risk (decision 9).** (a) A single foreign write inside W is attributed to Cáptalo, spoken and then overwritten. (b) A foreign write between the final check and the restore write is overwritten. (c) A source-app Copy that lands after W replaces the previous clipboard. In addition, clipboard managers can observe the source app's Copy before the restore. The transient markers only ask them to ignore the restore write.

### Synthetic copy

Synthetic Copy is used only when the app has no Copy menu item and `CopyPolicy` allows Copy. Wait up to 500 ms for the shortcut's modifiers to be released (`CGEventSource.flagsState`). On timeout, return `.unsupported(.modifiersHeld)` and post nothing. The transaction's step 2 recheck runs right before the post.

## Tasks

1. TDD in `CaptaloCore`: `RequestCoordinator`, `SelectionEvidence` classification, `CaptureCoordinator`, `CopyPolicy` and `ClipboardTransaction`. Accessibility and the event poster use fakes, because they are not owned code. Pasteboard tests use a real uniquely named `NSPasteboard`, and a second writer task injects foreign writes at each checkpoint: during the snapshot, before Copy, inside W, and between read and final check.
2. App adapters for the AX layer, the menu Copy press, the synthetic Copy and the pasteboard, using SelectedTextKit 2.6.7 (MIT) as a read-only reference only.
3. Probe mode (Debug only; `-CaptureProbe YES`): the expected fixture text is embedded in the probe build. Each press compares the captured text with the fixture **after whitespace normalization** (runs of whitespace collapsed, ends trimmed) and logs only `PrivacyLog.probe(result: pass|fail|nothingSelected|unsupported, layer:, lengths:, clipboardIntact:, focusKept:, providerMs:)`. Clipboard check: every original item and type is present and byte-equal afterwards, and the only added types are `org.nspasteboard.TransientType` and `org.nspasteboard.AutoGeneratedType`.
4. Fixtures (committed, synthetic): `Fixtures/capture-matrix.txt` has three paragraphs with a Markdown line, a URL and a number. `make clipboard-sentinel` (Debug helper) writes plain text, RTF, a custom type and a file URL. A PDF fixture is generated with print-to-PDF into `.local/fixtures/`.
5. Matrix run. In each of the 12 apps: (a) select the whole fixture and press; (b) select nothing (caret only) and press; (c) with a seam session playing, select nothing and press (expect the stop transition), then select the fixture and press (expect replacement). Record each app's name and version, the layer, pass or fail, clipboard intact, focus kept, the copy delta, latency and provider time where Copy ran, and the no-selection and stop outcomes.
6. Evidence: raw JSON under `.local/capture/`, one file per run named with its ISO date. A curated summary goes in `docs/research/`, named with the run date and the slug `capture-matrix`, and includes decision 9's exception text.
7. Permission survival (review R12): after a changed rebuild and `make install`, capture still works without re-granting Accessibility. Record the before and after designated requirements.

## Success criteria

### Automated (`make verify`)

- [x] `RequestCoordinatorTests`: `rapidPressesOnlyLastResolves`, `newInputDoesNotTouchPlayingSession`, `textOutcomePromotesAndStopsOldSession`, `stopGestureStopsSession`, `failedInputLeavesSession`, `delayedOldResultIsDropped`, `staleSessionCallbackDropped`, `quitLetsOpenCleanupFinish`.
- [x] `CaptureCoordinatorTests`: `axTextWinsAndPasteboardUntouched`, `confirmedEmptyNeverReachesCopy`, `unavailableUsesMenuCopyWhenPolicyAllows`, `copyPolicyBlocksVSCodeWithUnsupported`, `disabledCopyItemMeansNothingSelectedAndNoKeyEvent`, `syntheticCopyOnlyWhenNoCopyItem`, `modifierTimeoutAbortsSyntheticCopy`, `sourceChangedBeforeCopyAborts`, `chromiumGetsManualAccessibilityOnce`, `neverSetsEnhancedUserInterface`, `untrustedReturnsPermissionMissingBeforeAnyLayer`.
- [x] `ClipboardTransactionTests` (real named pasteboard), each checking the race its name states:
  - `unchangedPasteboardIsNeverRead`
  - `copiedTextReturnedAndOriginalRepresentationsRestored` (multi-item, multi-type, custom type; only the two marker types added)
  - `writeDuringSnapshotAborts`, `writeBeforeCopyAborts`
  - `secondChangeMeansUncertainNoSpeakNoRestore`, `writeBetweenReadAndFinalCheckIsPreserved`
  - `cancelWhileWaitingForLockSendsNoCopy`, `cancelDuringSnapshotSendsNoCopy`
  - `noChangeWithinWindowRestoresNothing`, `overlappingTransactionsAreSerialized`, `cancelAfterCopyStillRunsScopedCleanup`, `cleanupAuthorityGrantsNoOtherEffect`, `emptyOriginalClipboardIsRestoredEmpty`, `restoreFailureDoesNotSpeak`
  - Not testable, documented under decision 9: a single foreign write inside W, and a write between the final check and the restore write.
- [x] `ReadingIdentityTests.sameCapturedTextTogglesStop` (fixes baseline §2: the comparison uses captured text, held as a hash).
- [x] `make log-audit` passes for `Captalo/Services/Capture`.

### Manual (owner and agent)

- [ ] Each mandatory app (Rex, Safari, Chrome, Preview, TextEdit, Word) reads the fixture (probe `pass` after whitespace normalization), keeps the clipboard intact and keeps focus. Any failure blocks acceptance unless the owner approves a recorded waiver for that app.
- [ ] Every one of the 12 apps has recorded no-selection and seam stop and replace results. In no app does a no-selection press produce a `.text` outcome or change the clipboard. Any app that would is added to `CopyPolicy` and retested.
- [ ] Non-mandatory results are recorded as pass, unsupported (with reason) or fail.
- [ ] Revoke Accessibility, press, and the window opens with the permission row. Grant it, press again, and capture works without a relaunch.
- [ ] Permission survives the changed rebuild (task 7).

## Handoff to phase 3

The matrix document path, the waivers granted (quoted), the `CopyPolicy` list, the measured Copy latencies and provider times (any Copy over 300 ms flagged), and the designated requirement under test. The stop and replace results in this phase are seam evidence only.
