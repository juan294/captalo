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

/// Region OCR (plan phase 5, unit 5B). The caller waits at most `timeout`;
/// the worker that owns the image and the Vision call ends on its own time,
/// and the slot stays held until it does.
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
        PrivacyLog.record(.ocr(outcome: .init(outcome), characters: outcome.capturedLength, elapsed: started.duration(to: .now)))
        return outcome
    }

    private func recognizeRegion(_ token: InputToken, _ selection: RegionSelection) async -> CaptureOutcome {
        // 1. Reserve the slot before anything awaits.
        guard await slot.reserve() else { return .failed(.ocrBusy) }
        // 2. Capture; a failure or cancellation releases the slot.
        let image: CGImage
        do {
            image = try await capturer.capture(selection)
        } catch {
            await slot.release()
            // A capture cut short by a newer input is a cancel, not an OCR failure.
            return Task.isCancelled ? .cancelled : .failed(.ocrFailed)
        }
        // 2a. A newer input superseded this one: drop the image, never start Vision.
        guard await isCurrent(token) else {
            await slot.release()
            return .cancelled
        }
        // 2b, 4. The worker owns the image and the reservation; it releases the
        // slot when the native call has returned or thrown.
        let slot = self.slot
        let recognizer = self.recognizer
        let worker = Task { () -> Result<[TranscriptItem], any Error> in
            let result: Result<[TranscriptItem], any Error>
            do {
                result = .success(try await recognizer.recognize(image))
            } catch {
                result = .failure(error)
            }
            await slot.release()
            return result
        }
        // 3. The caller waits up to `timeout`, then cancels the worker and
        // returns. A task group would wait for the worker; this race does not.
        let first = await Self.race(worker, timeout: timeout)
        guard let first else {
            worker.cancel()
            return .failed(.ocrTimedOut)
        }
        // 5. Deliver only to a current input.
        guard await isCurrent(token) else { return .cancelled }
        switch first {
        case .failure:
            return .failed(.ocrFailed)
        case let .success(items):
            let blocks = DocumentTranscript.blocks(items)
            guard TextPreparer.prepare(blocks, source: .ocr).first(where: { _ in true }) != nil else { return .nothingSelected }
            return .document(blocks)
        }
    }
}

extension RegionReader {
    /// The worker's result, or nil when `timeout` passes first. Returns at
    /// whichever comes first; the worker keeps running on its own.
    static func race<Value: Sendable>(_ worker: Task<Value, Never>, timeout: Duration) async -> Value? {
        let race = Race<Value>()
        let value: Value? = await withCheckedContinuation { continuation in
            race.start(continuation)
            Task { race.finish(await worker.value) }
            race.setTimer(Task {
                try? await Task.sleep(for: timeout)
                race.finish(nil)
            })
        }
        race.cancelTimer()
        return value
    }
}

/// Resumes its continuation exactly once: with the worker's value or with nil at the timeout.
private final class Race<Value: Sendable>: Sendable {
    private let state = Mutex<(continuation: CheckedContinuation<Value?, Never>?, done: Bool)>((nil, false))
    private let timer = Mutex<Task<Void, Never>?>(nil)

    func start(_ continuation: CheckedContinuation<Value?, Never>) {
        state.withLock { $0.continuation = continuation }
    }

    func finish(_ value: Value?) {
        let continuation = state.withLock { s -> CheckedContinuation<Value?, Never>? in
            guard !s.done else { return nil }
            s.done = true
            defer { s.continuation = nil }
            return s.continuation
        }
        continuation?.resume(returning: value)
    }

    func setTimer(_ task: Task<Void, Never>) {
        timer.withLock { $0 = task }
    }

    func cancelTimer() {
        timer.withLock { $0?.cancel() }
    }
}

/// Consecutive region failures (errors and timeouts; not empty regions).
/// At `threshold`, the settings window's optional OCR row shows the category.
public struct OcrFailureCounter: Equatable, Sendable {
    public static let threshold = 3

    public private(set) var consecutive = 0
    public private(set) var lastCategory: CaptureFailure?

    public init() {}

    public var surfacedCategory: CaptureFailure? {
        consecutive >= Self.threshold ? lastCategory : nil
    }

    public mutating func record(_ outcome: CaptureOutcome) {
        switch outcome {
        case .document:
            consecutive = 0
            lastCategory = nil
        case let .failed(failure) where failure == .ocrFailed || failure == .ocrTimedOut:
            consecutive += 1
            lastCategory = failure
        default:
            break
        }
    }
}
