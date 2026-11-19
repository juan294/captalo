import CoreGraphics
import Foundation
import Synchronization
import Testing
@testable import CaptaloCore

struct TestFailure: Error {}

func blankImage(_ width: Int = 8, _ height: Int = 8) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return context.makeImage()!
}

/// Returns an image when released by the test (or fails).
final class BlockedCapturer: RegionCapturer, Sendable {
    let gate = Gate()
    let fail: Bool
    let calls = Mutex(0)
    init(blocked: Bool = false, fail: Bool = false) {
        self.fail = fail
        if !blocked { Task { [gate] in await gate.open() } }
    }
    func capture(_ selection: RegionSelection) async throws -> CGImage {
        calls.withLock { $0 += 1 }
        await gate.wait()
        if fail { throw TestFailure() }
        return blankImage()
    }
}

/// Returns `items` when released by the test; ignores cancellation, like a native call that runs on.
final class BlockedRecognizer: DocumentRecognizer, Sendable {
    let gate = Gate()
    let items: [TranscriptItem]
    let fail: Bool
    let calls = Mutex(0)
    let returned = Mutex(false)
    init(items: [TranscriptItem] = [], blocked: Bool = false, fail: Bool = false) {
        self.items = items
        self.fail = fail
        if !blocked { Task { [gate] in await gate.open() } }
    }
    func recognize(_ image: CGImage) async throws -> [TranscriptItem] {
        calls.withLock { $0 += 1 }
        await gate.wait()
        returned.withLock { $0 = true }
        if fail { throw TestFailure() }
        return items
    }
}

let selection = RegionSelection(displayID: 1, globalRect: CGRect(x: 0, y: 0, width: 100, height: 50),
                                localRect: CGRect(x: 0, y: 0, width: 100, height: 50), pixelSize: CGSize(width: 200, height: 100))
let regionToken = InputToken(inputGeneration: 1, kind: .region, source: sourceA, startedAt: .now)
let words = [TranscriptItem(.paragraph("Read this region."), bounds: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.1))]

@Suite struct RegionReaderTests {
    func reader(_ capturer: RegionCapturer, _ recognizer: DocumentRecognizer, slot: OCRSlot = OCRSlot(),
                current: Flag = Flag(true), timeout: Duration = .seconds(10)) -> RegionReader {
        RegionReader(capturer: capturer, recognizer: recognizer, slot: slot, isCurrent: { _ in current.get() }, timeout: timeout)
    }

    @Test func slotReservedBeforeCaptureAwaits() async {
        let slot = OCRSlot()
        let capturer = BlockedCapturer(blocked: true)
        let first = Task { await reader(capturer, BlockedRecognizer(items: words), slot: slot).read(regionToken, selection) }
        await eventually { capturer.calls.withLock { $0 } == 1 }
        #expect(await slot.isReserved)
        #expect(await reader(BlockedCapturer(), BlockedRecognizer(), slot: slot).read(regionToken, selection) == .failed(.ocrBusy))
        await capturer.gate.open()
        #expect(await first.value == .document([.paragraph("Read this region.")]))
    }

    @Test func overlappingPressesCannotBothReserve() async {
        let slot = OCRSlot()
        let results = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<20 { group.addTask { await slot.reserve() } }
            return await group.reduce(into: [Bool]()) { $0.append($1) }
        }
        #expect(results.filter { $0 }.count == 1)
    }

    @Test func captureFailureReleasesSlot() async {
        let slot = OCRSlot()
        #expect(await reader(BlockedCapturer(fail: true), BlockedRecognizer(), slot: slot).read(regionToken, selection) == .failed(.ocrFailed))
        #expect(await !slot.isReserved)
    }

    /// A capture cancelled by a newer input is a cancel, so it never counts as an OCR failure.
    @Test func cancelledCaptureIsACancelNotAFailure() async {
        let capturer = BlockedCapturer(blocked: true, fail: true)
        let slot = OCRSlot()
        let read = Task { await reader(capturer, BlockedRecognizer(), slot: slot).read(regionToken, selection) }
        await eventually { capturer.calls.withLock { $0 } == 1 }
        read.cancel()
        await capturer.gate.open()
        #expect(await read.value == .cancelled)
        // The worker releases the slot when the capture ends, not when the caller returns.
        await eventually { await !slot.isReserved }
        #expect(await !slot.isReserved)
    }

    /// Cancelling the caller (a newer press, or quit) ends the wait at once as a
    /// cancel; the worker still holds the slot until the native call returns.
    @Test func callerCancellationEndsTheWaitButNotTheWorker() async {
        let recognizer = BlockedRecognizer(items: words, blocked: true)
        let slot = OCRSlot()
        let read = Task { await reader(BlockedCapturer(), recognizer, slot: slot, timeout: .seconds(60)).read(regionToken, selection) }
        await eventually { recognizer.calls.withLock { $0 } == 1 }
        let cancelled = ContinuousClock.now
        read.cancel()
        #expect(await read.value == .cancelled)
        #expect(cancelled.duration(to: .now) < .seconds(1))
        #expect(await slot.isReserved)
        await recognizer.gate.open()
        await eventually { await !slot.isReserved }
    }

    /// VAL-09: the caller deadline covers screenshot acquisition. A blocked capture
    /// times the caller out on schedule; the slot stays held until the capture
    /// ends, and an image that arrives after the caller gave up never reaches Vision.
    @Test func callerDeadlineCoversBlockedCapture() async {
        let capturer = BlockedCapturer(blocked: true)
        let recognizer = BlockedRecognizer(items: words)
        let slot = OCRSlot()
        let read = Task { await reader(capturer, recognizer, slot: slot, timeout: .milliseconds(50)).read(regionToken, selection) }
        await eventually { capturer.calls.withLock { $0 } == 1 }
        let watchdog = Self.openAfterTwoSeconds(capturer.gate) // a regression fails instead of hanging
        defer { watchdog.cancel() }
        let started = ContinuousClock.now
        let outcome = await read.value
        // A blocked screenshot (for example, a macOS screen-access prompt) is its own category.
        #expect(outcome == .failed(.captureTimedOut))
        #expect(started.duration(to: .now) < .seconds(1))
        #expect(await slot.isReserved) // the capture is still running
        await capturer.gate.open()
        await eventually { await !slot.isReserved }
        #expect(await !slot.isReserved)
        #expect(recognizer.calls.withLock { $0 } == 0)
    }

    /// VAL-09: cancelling the caller during a blocked capture ends the wait at
    /// once; the slot stays held until the capture ends, and Vision never starts.
    @Test func callerCancellationCoversBlockedCapture() async {
        let capturer = BlockedCapturer(blocked: true)
        let recognizer = BlockedRecognizer(items: words)
        let slot = OCRSlot()
        let read = Task { await reader(capturer, recognizer, slot: slot, timeout: .seconds(60)).read(regionToken, selection) }
        await eventually { capturer.calls.withLock { $0 } == 1 }
        let watchdog = Self.openAfterTwoSeconds(capturer.gate) // a regression fails instead of hanging
        defer { watchdog.cancel() }
        let cancelled = ContinuousClock.now
        read.cancel()
        #expect(await read.value == .cancelled)
        #expect(cancelled.duration(to: .now) < .seconds(1))
        #expect(await slot.isReserved) // the capture is still running
        await capturer.gate.open()
        await eventually { await !slot.isReserved }
        #expect(await !slot.isReserved)
        #expect(recognizer.calls.withLock { $0 } == 0)
    }

    static func openAfterTwoSeconds(_ gate: Gate) -> Task<Void, Never> {
        Task {
            guard (try? await Task.sleep(for: .seconds(2))) != nil else { return }
            await gate.open()
        }
    }

    /// A caller already cancelled before the race starts never waits.
    @Test func raceStartedCancelledReturnsNil() async {
        let worker = Task<Int, Never> { try? await Task.sleep(for: .seconds(60)); return 1 }
        let started = ContinuousClock.now
        let race = Task { await RegionReader.race(worker, timeout: .seconds(60)) }
        race.cancel()
        #expect(await race.value == nil)
        #expect(started.duration(to: .now) < .seconds(1))
        worker.cancel()
    }

    @Test func staleCaptureCompletingAfterNewerInputNeverStartsVision() async {
        let capturer = BlockedCapturer(blocked: true)
        let recognizer = BlockedRecognizer(items: words)
        let current = Flag(true)
        let slot = OCRSlot()
        let read = Task { await reader(capturer, recognizer, slot: slot, current: current).read(regionToken, selection) }
        await eventually { capturer.calls.withLock { $0 } == 1 }
        current.set(false) // a newer press
        await capturer.gate.open()
        #expect(await read.value == .cancelled)
        #expect(recognizer.calls.withLock { $0 } == 0)
        #expect(await !slot.isReserved)
    }

    @Test func everyExitPathTearsDown() async {
        let empty = [TranscriptItem(.paragraph("  "), bounds: CGRect(x: 0, y: 0, width: 0.1, height: 0.1))]
        let cases: [(DocumentRecognizer, Bool, CaptureOutcome)] = [
            (BlockedRecognizer(items: words), true, .document([.paragraph("Read this region.")])),
            (BlockedRecognizer(items: empty), true, .nothingSelected),
            (BlockedRecognizer(fail: true), true, .failed(.ocrFailed)),
            (BlockedRecognizer(items: words, blocked: true), false, .cancelled),
        ]
        for (recognizer, current, expected) in cases {
            let slot = OCRSlot()
            let flag = Flag(true)
            let read = Task { await reader(BlockedCapturer(), recognizer, slot: slot, current: flag).read(regionToken, selection) }
            if !current {
                let blocked = recognizer as! BlockedRecognizer
                await eventually { blocked.calls.withLock { $0 } == 1 }
                flag.set(false) // superseded while recognizing
                await blocked.gate.open()
            }
            #expect(await read.value == expected)
            #expect(await !slot.isReserved)
        }
    }

    @Test func callerTimesOutAt10sWhileWorkerStillRuns() async {
        #expect(RegionReader.defaultTimeout == .seconds(10))
        let recognizer = BlockedRecognizer(items: words, blocked: true)
        let slot = OCRSlot()
        let outcome = await reader(BlockedCapturer(), recognizer, slot: slot, timeout: .milliseconds(50)).read(regionToken, selection)
        #expect(outcome == .failed(.ocrTimedOut))
        #expect(!recognizer.returned.withLock { $0 }) // the worker is still running
        await recognizer.gate.open()
    }

    @Test func slotHeldUntilBlockedWorkerReturns() async {
        let recognizer = BlockedRecognizer(items: words, blocked: true)
        let slot = OCRSlot()
        _ = await reader(BlockedCapturer(), recognizer, slot: slot, timeout: .milliseconds(30)).read(regionToken, selection)
        #expect(await slot.isReserved)
        await recognizer.gate.open()
        await eventually { await !slot.isReserved }
        #expect(await !slot.isReserved)
    }

    @Test func secondPressWhileSlotHeldIsSilent() async {
        let recognizer = BlockedRecognizer(items: words, blocked: true)
        let slot = OCRSlot()
        _ = await reader(BlockedCapturer(), recognizer, slot: slot, timeout: .milliseconds(30)).read(regionToken, selection)
        let capturer = BlockedCapturer()
        #expect(await reader(capturer, BlockedRecognizer(items: words), slot: slot).read(regionToken, selection) == .failed(.ocrBusy))
        #expect(capturer.calls.withLock { $0 } == 0)
        await recognizer.gate.open()
    }

    @Test func lateWorkerResultAfterTimeoutIsDiscarded() async {
        let recognizer = BlockedRecognizer(items: words, blocked: true)
        let log = EventLog()
        let coordinator = makeCoordinator(log: log)
        let slot = OCRSlot()
        let regionReader = RegionReader(capturer: BlockedCapturer(), recognizer: recognizer, slot: slot,
                                        isCurrent: { await coordinator.isCurrent($0) }, timeout: .milliseconds(30))
        await coordinator.submit(coordinator.reservePress(), kind: .region, source: sourceA) { token in await regionReader.read(token, selection) }
        await coordinator.waitForIdle()
        await recognizer.gate.open()
        await eventually { await !slot.isReserved }
        #expect(log.events.isEmpty) // the late result never became a reading
    }

    @Test func supersededTokenDropsResult() async {
        let recognizer = BlockedRecognizer(items: words, blocked: true)
        let current = Flag(true)
        let read = Task { await reader(BlockedCapturer(), recognizer, current: current).read(regionToken, selection) }
        await eventually { recognizer.calls.withLock { $0 } == 1 }
        current.set(false)
        await recognizer.gate.open()
        #expect(await read.value == .cancelled)
    }

    @Test func oversizeRectIsBoundedToDisplayScale() throws {
        let display = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), scale: 2)
        let huge = try #require(RegionGeometry.selection(from: CGPoint(x: -5000, y: -5000), to: CGPoint(x: 9000, y: 9000), displays: [display])
            ?? RegionGeometry.selection(from: CGPoint(x: 1, y: 1), to: CGPoint(x: 9000, y: 9000), displays: [display]))
        #expect(huge.pixelSize.width <= 1512 * 2)
        #expect(huge.pixelSize.height <= 982 * 2)
    }
}

@Suite struct OcrFailureCounterTests {
    @Test func threeConsecutiveFailuresSurfaceCategory() {
        var counter = OcrFailureCounter()
        counter.record(.failed(.ocrFailed))
        counter.record(.failed(.ocrTimedOut))
        #expect(counter.surfacedCategory == nil)
        counter.record(.failed(.ocrTimedOut))
        #expect(counter.surfacedCategory == .ocrTimedOut)
    }

    /// A blocked screenshot usually means macOS is asking for screen access:
    /// say so after the first one, and clear it on the next success.
    @Test func blockedScreenshotIsNoticedAtOnce() {
        var counter = OcrFailureCounter()
        counter.record(.failed(.captureTimedOut))
        #expect(counter.surfacedCategory == .captureTimedOut)
        counter.record(.document([]))
        #expect(counter.surfacedCategory == nil)
    }

    @Test func emptyRegionDoesNotCount() {
        var counter = OcrFailureCounter()
        for _ in 0..<5 { counter.record(.nothingSelected) }
        counter.record(.failed(.ocrFailed))
        #expect(counter.consecutive == 1)
    }

    /// The Esc tap could not be created while Accessibility still looks
    /// granted: the press must not fail silently (review of VAL-08).
    @Test func overlayFailureIsNoticedAtOnce() {
        var counter = OcrFailureCounter()
        counter.record(.failed(.overlayUnavailable))
        #expect(counter.surfacedCategory == .overlayUnavailable)
        // A cancel proves nothing about the tap; the notice stays.
        counter.record(.cancelled)
        #expect(counter.surfacedCategory == .overlayUnavailable)
        // An overlay that opened clears it, even with nothing found.
        counter.record(.nothingSelected)
        #expect(counter.surfacedCategory == nil)
        counter.record(.failed(.overlayUnavailable))
        counter.record(.document([.paragraph("read")]))
        #expect(counter.surfacedCategory == nil)
    }

    /// The log line names the failure and carries no text.
    @Test func overlayFailureLogLine() {
        let event = RegionReader.event(for: .failed(.overlayUnavailable), elapsed: .milliseconds(3))
        #expect(event.rendered == "ocr outcome=failed failure=overlayUnavailable blocks=0 characters=0 elapsedMs=3")
    }

    @Test func successResetsCounter() {
        var counter = OcrFailureCounter()
        for _ in 0..<3 { counter.record(.failed(.ocrFailed)) }
        counter.record(.document([.paragraph("ok")]))
        #expect(counter.consecutive == 0)
        #expect(counter.surfacedCategory == nil)
    }
}

/// A playing session made of a real ReadingSession on the in-memory engine.
struct ReadingPlayback: PlaybackSession {
    let reading: ReadingSession
    func start() async { await reading.start() }
    func stop() async { await reading.stop() }
}

@Suite struct RegionPendingTests {
    func readingCoordinator(units: Int, sink: FakeSink, events: Events) -> RequestCoordinator {
        RequestCoordinator { _, _, _ in
            ReadingPlayback(reading: ReadingSession(units: sentences(units), synthesizer: FakeSynthesizer(), sink: sink,
                                                    voice: "af_heart", speed: 1) { events.append($0) })
        }
    }

    @Test func cancelAfterLookaheadLeavesSessionComplete() async {
        let sink = FakeSink(autoplay: false)
        let events = Events()
        let coordinator = readingCoordinator(units: 8, sink: sink, events: events)
        let selectionToken = await coordinator.beginInput(kind: .selection, source: sourceA)
        _ = await coordinator.resolve(selectionToken, .text("playing", layer: .accessibility))
        await eventually { sink.pendingCount == 4 } // the lookahead is full
        // The overlay stays open longer than the lookahead, then is cancelled.
        let gate = Gate()
        await coordinator.submit(coordinator.reservePress(), kind: .region, source: sourceA) { _ in await gate.wait(); return .cancelled }
        sink.playNext()
        await eventually { sink.pendingCount == 4 }
        await gate.open()
        await coordinator.waitForIdle()
        for _ in 0..<20 {
            await eventually { sink.pendingCount >= 1 || events.played.count == 8 }
            if !sink.playNext() { break }
        }
        await eventually { events.played.count == 8 }
        #expect(events.played == Array(0..<8)) // every unit still played once
    }

    @Test func emptyOcrLeavesSession() async {
        let log = EventLog()
        let coordinator = makeCoordinator(log: log)
        let selectionToken = await coordinator.beginInput(kind: .selection, source: sourceA)
        _ = await coordinator.resolve(selectionToken, .text("playing", layer: .accessibility))
        let region = await coordinator.beginInput(kind: .region, source: sourceA)
        #expect(await coordinator.resolve(region, .nothingSelected) == .unchanged)
        #expect(log.events == ["start 1:playing"])
    }

    @Test func timeoutLeavesSession() async {
        let log = EventLog()
        let coordinator = makeCoordinator(log: log)
        let selectionToken = await coordinator.beginInput(kind: .selection, source: sourceA)
        _ = await coordinator.resolve(selectionToken, .text("playing", layer: .accessibility))
        let region = await coordinator.beginInput(kind: .region, source: sourceA)
        #expect(await coordinator.resolve(region, .failed(.ocrTimedOut)) == .unchanged)
        #expect(log.events == ["start 1:playing"])
    }

    @Test func successfulOcrReplacesSession() async {
        let log = EventLog()
        let coordinator = makeCoordinator(log: log)
        let selectionToken = await coordinator.beginInput(kind: .selection, source: sourceA)
        _ = await coordinator.resolve(selectionToken, .text("playing", layer: .accessibility))
        let region = await coordinator.beginInput(kind: .region, source: sourceA)
        #expect(await coordinator.resolve(region, .document([.paragraph("From the screen.")])) == .promoted(SessionToken(sessionGeneration: 2)))
        #expect(log.events == ["start 1:playing", "stop 1:playing", "start 2:From the screen."])
    }

    @Test func selectionPressSupersedesPendingRegion() async throws {
        let log = EventLog()
        let coordinator = makeCoordinator(log: log)
        let gate = Gate()
        let region = try #require(await coordinator.submit(coordinator.reservePress(), kind: .region, source: sourceA) { _ in
            await gate.wait(); return .document([.paragraph("late region")])
        })
        let selection = await coordinator.beginInput(kind: .selection, source: sourceA)
        #expect(await !coordinator.isCurrent(region))
        _ = await coordinator.resolve(selection, .text("selected", layer: .accessibility))
        await gate.open()
        await coordinator.waitForIdle()
        #expect(log.events == ["start 1:selected"])
    }
}
