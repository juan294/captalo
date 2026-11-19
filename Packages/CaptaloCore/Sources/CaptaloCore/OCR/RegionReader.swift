import CoreGraphics
import Foundation
import Synchronization

/// Captures the selected region (ScreenCaptureKit in the app).
public protocol RegionCapturer: Sendable {
    func capture(_ selection: RegionSelection) async throws -> CGImage
}

/// Recognizes document structure (Vision `RecognizeDocumentsRequest` in the app).
public protocol DocumentRecognizer: Sendable {
    func recognize(_ image: CGImage) async throws -> [TranscriptItem]
}

/// The single OCR slot: reserved atomically before capture, released only
/// when the native recognition call has returned (plan phase 5, review V3-3).
public actor OCRSlot {
    private var reserved = false

    public init() {}

    public func reserve() -> Bool {
        guard !reserved else { return false }
        reserved = true
        return true
    }

    public func release() {
        reserved = false
    }

    public var isReserved: Bool { reserved }
}

/// Region OCR (plan phase 5, unit 5B). The caller waits at most `timeout`,
/// screenshot acquisition included; the worker that owns the capture, the
/// image and the Vision call ends on its own time, and the slot stays held
/// until it does.
public final class RegionReader: Sendable {
    public static let defaultTimeout = Duration.seconds(10)

    private let capturer: RegionCapturer
    private let recognizer: DocumentRecognizer
    private let slot: OCRSlot
    private let isCurrent: @Sendable (InputToken) async -> Bool
    private let timeout: Duration

    public init(
        capturer: RegionCapturer,
        recognizer: DocumentRecognizer,
        slot: OCRSlot = OCRSlot(),
        isCurrent: @escaping @Sendable (InputToken) async -> Bool,
        timeout: Duration = RegionReader.defaultTimeout
    ) {
        self.capturer = capturer
        self.recognizer = recognizer
        self.slot = slot
        self.isCurrent = isCurrent
        self.timeout = timeout
    }

    public func read(_ token: InputToken, _ selection: RegionSelection) async -> CaptureOutcome {
        let started = ContinuousClock.now
        let outcome = await recognizeRegion(token, selection)
        PrivacyLog.record(Self.event(for: outcome, elapsed: started.duration(to: .now)))
        return outcome
    }

    /// The `ocr` log event for a region outcome: counts and the failure name, never text.
    public static func event(for outcome: CaptureOutcome, elapsed: Duration) -> PrivacyEvent {
        let (failure, blocks): (CaptureFailure?, Int) = switch outcome {
        case let .failed(category): (category, 0)
        case let .document(recognized): (nil, recognized.count)
        default: (nil, 0)
        }
        return .ocr(outcome: .init(outcome), failure: failure, blocks: blocks,
                    characters: outcome.capturedLength, elapsed: elapsed)
    }

    private func recognizeRegion(_ token: InputToken, _ selection: RegionSelection) async -> CaptureOutcome {
        // 1. Reserve the slot before anything awaits.
        guard await slot.reserve() else { return .failed(.ocrBusy) }
        // 2, 4. The worker owns the capture, the image and the reservation; it
        // releases the slot only when the capture and any Vision call have ended.
        let (slot, capturer, recognizer, isCurrent) = (self.slot, self.capturer, self.recognizer, self.isCurrent)
        let captured = Atomic(false)
        let worker = Task { () -> Result<[TranscriptItem], any Error> in
            let result: Result<[TranscriptItem], any Error>
            do {
                let image = try await capturer.capture(selection)
                captured.store(true, ordering: .sequentiallyConsistent)
                // 2a. The caller gave up (timeout, cancel) or a newer input
                // superseded this one: drop the image, never start Vision.
                let current = await isCurrent(token)
                result = current && !Task.isCancelled
                    ? .success(try await recognizer.recognize(image)) : .failure(CancellationError())
            } catch {
                result = .failure(error)
            }
            await slot.release()
            return result
        }
        // 3. The caller waits up to `timeout` across capture and recognition,
        // then cancels the worker and returns. A task group would wait for the
        // worker; this race does not.
        guard let finished = await Self.race(worker, timeout: timeout) else {
            worker.cancel()
            // A cancelled caller (newer press, quit) is a cancel, never a timeout.
            // A screenshot that never arrived is told apart from a slow recognition.
            guard !Task.isCancelled else { return .cancelled }
            return .failed(captured.load(ordering: .sequentiallyConsistent) ? .ocrTimedOut : .captureTimedOut)
        }
        // 5. Deliver only to a current input. A dropped image (CancellationError)
        // happens only for an input that is no longer current, so it ends here.
        guard await isCurrent(token) else { return .cancelled }
        switch finished {
        case .failure:
            // A capture or recognition error is an OCR failure, unless the
            // caller was cancelled after the worker returned: that is a cancel.
            return Task.isCancelled ? .cancelled : .failed(.ocrFailed)
        case let .success(items):
            let blocks = DocumentTranscript.blocks(items)
            guard TextPreparer.hasSpeakableText(.document(blocks)) else { return .nothingSelected }
            return .document(blocks)
        }
    }
}

extension RegionReader {
    /// The worker's result, or nil when `timeout` passes or the caller is
    /// cancelled first. Returns at whichever comes first; the worker keeps
    /// running on its own.
    static func race<Value: Sendable>(_ worker: Task<Value, Never>, timeout: Duration) async -> Value? {
        let race = Race<Value>()
        let timer = Task {
            try? await Task.sleep(for: timeout)
            race.finish(nil)
        }
        defer { timer.cancel() }
        Task { race.finish(await worker.value) }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { race.start($0) }
        } onCancel: {
            race.finish(nil)
        }
    }
}

/// Resumes its continuation exactly once: with the worker's value, or with nil
/// at the timeout or on caller cancellation.
private final class Race<Value: Sendable>: Sendable {
    private let state = Mutex<(continuation: CheckedContinuation<Value?, Never>?, done: Bool, value: Value?)>((nil, false, nil))

    /// A race that finished before the caller waits resumes at once with that result.
    func start(_ continuation: CheckedContinuation<Value?, Never>) {
        let finished = state.withLock { s -> (Bool, Value?) in
            if !s.done { s.continuation = continuation }
            return (s.done, s.value)
        }
        if finished.0 { continuation.resume(returning: finished.1) }
    }

    func finish(_ value: Value?) {
        let continuation = state.withLock { s -> CheckedContinuation<Value?, Never>? in
            guard !s.done else { return nil }
            s.done = true
            s.value = value
            defer { s.continuation = nil }
            return s.continuation
        }
        continuation?.resume(returning: value)
    }
}

/// Consecutive region failures (not empty regions), for the settings
/// window's optional OCR row. Recognition errors and timeouts show after
/// three in a row; an overlay that could not open (no Esc tap) shows at once.
public struct OcrFailureCounter: Equatable, Sendable {
    public private(set) var consecutive = 0
    public private(set) var lastCategory: CaptureFailure?

    public init() {}

    /// How many consecutive failures of this category surface it; nil when it is not counted.
    public static func threshold(for failure: CaptureFailure) -> Int? {
        switch failure {
        case .ocrFailed, .ocrTimedOut: 3
        case .overlayUnavailable, .captureTimedOut: 1
        default: nil
        }
    }

    public var surfacedCategory: CaptureFailure? {
        guard let lastCategory, let threshold = Self.threshold(for: lastCategory) else { return nil }
        return consecutive >= threshold ? lastCategory : nil
    }

    public mutating func record(_ outcome: CaptureOutcome) {
        switch outcome {
        case .document:
            self = OcrFailureCounter()
        case let .failed(failure) where Self.threshold(for: failure) != nil:
            // Recognition failures count together; an overlay failure is its own streak.
            let sameStreak = lastCategory.map { ($0 == .overlayUnavailable) == (failure == .overlayUnavailable) } ?? false
            consecutive = sameStreak ? consecutive + 1 : 1
            lastCategory = failure
        case .cancelled:
            break // can come before the overlay opened: it proves nothing
        default:
            // Any other outcome means the overlay opened.
            if lastCategory == .overlayUnavailable { self = OcrFailureCounter() }
        }
    }
}
