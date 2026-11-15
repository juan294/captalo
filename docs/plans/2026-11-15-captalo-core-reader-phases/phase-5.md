# Phase 5: Region OCR

Parent: [Cáptalo core reader plan](../2026-11-15-captalo-core-reader.md).

## Goal

For text that cannot be selected: press the region shortcut, drag a rectangle on any display, and hear the text inside it in sensible reading order. Focus stays in the source app, the overlay never appears in the capture, the image is released right after recognition, and every exit path tears down cleanly. OCR is optional at setup (owner decision 8).

## Entry conditions

- Phase 4 accepted.
- The owner grants Screen Recording when first asked (on the first region press or from the optional settings row).

## Gate 0: overlay feasibility probe (first task, review R10)

A throwaway Debug spike, not merged. It answers these questions on this Mac before 5A starts:

1. Can a borderless `.nonactivatingPanel` on each screen track a drag and receive Esc while the source app stays frontmost and its window stays key? If the panel cannot receive Esc without activation, test a temporary Carbon hotkey for Esc registered only while the overlay is visible, and confirm the source app does not receive the Esc.
2. Does the overlay appear over full-screen Spaces apps, and does a display connect or disconnect during selection deliver `NSApplication.didChangeScreenParametersNotification`?
3. Does `SCScreenshotManager.captureImage(contentFilter:configuration:)` with a filter that excludes Cáptalo's own windows and `configuration.sourceRect` capture the region without overlay pixels, while the overlay is still on screen? Confirm the API's availability on the macOS 26 SDK.
4. Native cancellation (review V2-9): run `RecognizeDocumentsRequest` on a large synthetic image inside a `Task`, cancel it mid-run, and measure when the call returns and whether it throws `CancellationError` or completes anyway. Record the time from cancel to return.

The probe results choose one Esc mechanism, one capture call and the OCR lifetime contract below. Both choices are recorded in this file before 5A and 5B start ("one code path per action"). If question 1 or 3 has no working answer, stop and report: the region interaction then needs a new owner decision.

### Gate 0 results (2026-11-15, this Mac, Xcode 27.0 SDK)

The spike ran as scratch probes outside the repository. Without Screen Recording and without a signed install (notes D1), only the API questions and question 4 could run; questions 1 to 3 need the owner at the installed app (notes D20).

| Question | Result | Evidence |
| --- | --- | --- |
| 1 Esc without activation | Pending (runtime). Chosen: borderless `.nonactivatingPanel` per screen with `canBecomeKey == false`; Esc through a session `CGEventTap` that swallows key code 53 while the overlay is visible (Accessibility is already a required grant). No Carbon hotkey. | Owner check: Manual criterion 3 |
| 2 Full-screen Spaces and screen changes | Pending (runtime). Panels use `.canJoinAllSpaces` and `.fullScreenAuxiliary` at `.screenSaver` level; the controller cancels on `didChangeScreenParametersNotification`. Automated coverage is the tracker only (`RegionOverlayTests.screenChangeCancels`); the controller's observer and teardown have no automated test (notes D22). | Manual criteria 4 and 5 |
| 3 Overlay-free capture | API confirmed in the macOS 26 SDK: `SCScreenshotManager.captureImage(contentFilter:configuration:)` and `SCStreamConfiguration.sourceRect`. Chosen: `SCContentFilter(display:excludingApplications:exceptingWindows:)` excluding Cáptalo, `sourceRect` from `RegionGeometry`, output size at the display's native scale. Pixel check pending (runtime). | Manual criterion 2 |
| 4 Native cancellation | `RecognizeDocumentsRequest` honours cancellation: cancelled at 50 ms and 300 ms into a 0.66 s warm run, it threw `VisionError.requestCancelled` 0.15 ms and 0.18 ms after the cancel. A cancel after the request finished returned its result. The very first recognition on this Mac after the SDK install took 13.5 s (a one-time system model cache); a later fresh process ran the same full recognition in 0.66 s, so a cold launch does not by itself reach the 10 s timeout. | Scratch probe, rerun 2026-11-15; `make ocr-probe` cancels a direct Vision call mid-run (it must throw) and checks the slot is free within 1 s of a caller timeout |

OCR lifetime contract: the caller waits at most 10 s; the worker that owns the image and the Vision call releases the slot when the native call returns or throws. Measured release after cancel: under 1 ms on this Mac. A cancelled caller (a newer press, or quit) stops waiting at once and reports a cancel, not a timeout. Residual risk: if the system model cache is cold (after an OS or SDK update), the first region press may exceed 10 s, read nothing and count one failure; the owner's OCR performance check measures the installed app.

## Units

### 5A Overlay and geometry `[batch-eligible]`

Files: `Captalo/UI/RegionOverlay/` and `Packages/CaptaloCore/Sources/CaptaloCore/OCR/RegionGeometry.swift` with its tests. No overlap with 5B.

```
@ RegionOverlay.select(token) -> CGRect? (global, top-left origin, points)
ctx: one panel per NSScreen; Esc mechanism chosen in gate 0
do:
  1. show panels without activating app; push crosshair cursor
  2. track drag; draw the rectangle only
  3. Esc, click without drag, rect < 8x8 pt, screen-parameter change, or token superseded -> nil
  4. clamp to the display containing the drag start; convert via RegionGeometry
fx: on every exit (defer): order panels out, pop cursor, unregister temporary Esc hotkey if used
```

`RegionGeometryTests`: `bottomLeftToTopLeftOnPrimary`, `secondaryDisplayLeftOfPrimary`, `secondaryDisplayAbove`, `retinaAndNonRetinaMixed`, `zeroSizeRectIsCancel`, `crossDisplayDragClampedToStartDisplay`. `RegionOverlayTests.screenChangeCancels` posts the notification to the controller and checks the result and the teardown.

### 5B OCR adapter and transcript `[batch-eligible]`

Files: `Captalo/Services/OCR/` and `Packages/CaptaloCore/Sources/CaptaloCore/OCR/DocumentTranscript.swift` with its tests. No overlap with 5A.

```
@ RegionReader.read(inputToken, rect) -> CaptureOutcome
ctx: capture call chosen in gate 0 (content filter excludes Cáptalo windows); OCRWorker owns the image and the Vision call; one OCR slot; PrivacyLog
pre: CGPreflightScreenCaptureAccess() (else .permissionMissing -> settings window on the optional row)
do:
  1. reserve the OCR slot atomically (actor); if already reserved -> silent, PrivacyLog.ocrBusy
  2. capture rect at most at native display scale of one display (bounded size); on capture failure or cancellation -> release the slot, silent
  2a. recheck inputToken before starting Vision; if superseded -> drop image, release the slot, silent
  2b. hand image and the reservation to OCRWorker
  3. caller waits up to 10 s; on timeout: cancel the worker's Task, return .ocrTimedOut to the coordinator
  4. worker: run RecognizeDocumentsRequest; map to DocumentTranscript Blocks; drop image reference; release slot when the native call has returned (or thrown)
  5. result delivered only if inputToken still current and caller has not timed out; else discarded
  6. PrivacyLog.ocr(blocks:, characters:, duration:, outcome:)
br: no text, Vision error, timeout, cancelled -> silent; session untouched (plan decision)
fx: nothing written to disk
risk: if gate 0 shows Vision ignores cancellation, the image lives until the native call returns; the slot stays occupied for that time
```

- The caller's timeout and the worker's lifetime are separate. The caller returns at 10 s at most. The image and the slot are released only when the native call actually ends, and gate 0 measures how long that takes. Evidence states this release time; it is not described as immediate.
- A failure counter in `CaptaloCore` counts consecutive region errors and timeouts (not empty regions), and resets on any successful recognition. At 3, the settings window's optional OCR row shows the failure category the next time the window is opened.

- The OCR `Block`s go straight into `TextPreparer.prepare(blocks, source: .ocr)`. Table rows and list items keep their boundaries, and they are not flattened into punctuation first (review, smaller items).
- `DocumentTranscriptTests` use hand-built transcript values, because Vision is not owned code. `make ocr-probe` is the contract probe. It runs real Vision through `RegionReader`'s recognition step on committed synthetic PNG fixtures (`Fixtures/ocr-two-column.png`, `Fixtures/ocr-table.png`, generated from text we wrote) and checks block order, block kinds and first words.

### 5C Integration (after 5A and 5B)

- `Name.readRegion` with no default, plus identical-binding validation against `readSelection`. The recorder and the Screen Recording row go in the settings window's optional section. `CGRequestScreenCaptureAccess()` is called only from that row's button or on the first region press.
- A region press is a `PendingInput` (phase 2 `RequestCoordinator`). It never touches the playing session. Only `.text` from a successful recognition promotes a new session that replaces the reading. Cancel, empty, error and timeout leave the session playing and synthesizing normally. A selection press while a region is pending supersedes the region input.
- `make ocr-probe` is added to `make verify` and `.rpi/policy.json` in the same commit.

## Success criteria

### Automated (`make verify`, including `ocr-probe`)

- [x] `RegionGeometryTests`, `RegionOverlayTests.screenChangeCancels` and `DocumentTranscriptTests` pass, including `tableRowsStayRowBlocksInOrder` and `twoColumnsLeftColumnFirst`.
- [x] `RegionReaderTests` (deterministic blocked capturer and blocked recognizer that return only when released by the test): `slotReservedBeforeCaptureAwaits`, `overlappingPressesCannotBothReserve`, `captureFailureReleasesSlot`, `staleCaptureCompletingAfterNewerInputNeverStartsVision`, `everyExitPathTearsDown` (success, no text, error, cancel), `callerTimesOutAt10sWhileWorkerStillRuns`, `slotHeldUntilBlockedWorkerReturns`, `secondPressWhileSlotHeldIsSilent`, `lateWorkerResultAfterTimeoutIsDiscarded`, `supersededTokenDropsResult`, `oversizeRectIsBoundedToDisplayScale`.
- [x] `RegionPendingTests` (with the phase 2 seam session): `cancelAfterLookaheadLeavesSessionComplete` (overlay open longer than the 3-unit lookahead, then cancel: every unit still plays once), `emptyOcrLeavesSession`, `timeoutLeavesSession`, `successfulOcrReplacesSession`, `selectionPressSupersedesPendingRegion`.
- [x] `OcrFailureCounterTests`: `threeConsecutiveFailuresSurfaceCategory`, `emptyRegionDoesNotCount`, `successResetsCounter`.
- [x] Gate 0 records the native cancellation result. `make ocr-probe` also cancels one recognition mid-run and checks that the slot is freed within the time gate 0 measured.
- [x] `SetupStateTests.screenRecordingIsOptionalButRequestedOnRegionPress`.
- [x] `make ocr-probe` matches the expected block order for both fixtures.
- [x] Code search: no `CGWindowListCreateImage`, and no image write (`write(to:`, `pngData`, `CGImageDestination`) in `Captalo/Services/OCR`.

### Manual (owner)

- [ ] A scanned-PDF passage in Preview (the capture fixture printed to PDF, then exported image-only) is read intelligibly in order. OCR mistakes are recorded.
- [ ] The PNG fixtures, a two-column page and a code screenshot are read, and the owner judges the order.
- [ ] After every drag, Esc and cancel, the source app is frontmost and key. Esc never reaches the source app (check in TextEdit: no Esc side effect).
- [ ] A full-screen app: the overlay appears and the capture works.
- [ ] On a second display, if available, the rectangle and capture match. If no second display is available, record N/A with that reason.
- [ ] Revoke Screen Recording: a region press opens the settings window on the optional row. A selection press still works without any prompt. After granting (and relaunching only if the row says so), a region press works.
- [ ] Permission survival (review R12): after a changed rebuild and `make install`, region capture still works without re-granting.
- [ ] OCR performance recorded separately from speech (press-to-first-audio and peak memory for a full-screen-height region) and accepted by the owner.
- [ ] Network off: OCR plus speech still work.

## Handoff after phase 5

The core reader is complete. Next workflows: a separate own-voice plan, and a first-release plan (Developer Program, Developer ID, notarization, evidence analyzer and runtime evidence per `.rpi/release-profile.json`). Neither is authorized by this plan.
