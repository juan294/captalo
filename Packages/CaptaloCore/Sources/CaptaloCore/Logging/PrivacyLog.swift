import Foundation
import os

/// Typed log events for Cáptalo's own logging.
///
/// Every payload is an enum case, a count or a duration. No case carries a
/// `String`, so captured or spoken text cannot reach the log through this API.
/// This narrows leakage through Cáptalo's own logging only; it does not make
/// dependency or system logging safe.
public enum PrivacyEvent: Sendable, Equatable {
    public enum Accelerator: String, Sendable {
        case neuralEngine
        case cpuAndGPU
    }

    case voicePrewarmed(accelerator: Accelerator)
    case firstAudio(characters: Int, elapsed: Duration, accelerator: Accelerator)
    case restoreFailed
    case capture(kind: InputKind, outcome: OutcomeKind, layer: CaptureLayerKind?, characters: Int, elapsed: Duration)
    /// Debug capture probe. `changeDelta` is the pasteboard change-count delta.
    /// Provider time comes from the transaction's `clipboardSnapshot` event.
    case probe(
        result: CaptureProbe.Result, layer: CaptureLayerKind?, expectedLength: Int, capturedLength: Int,
        clipboardIntact: Bool, focusKept: Bool, elapsed: Duration, changeDelta: Int
    )
    /// Clipboard transaction snapshot: item count, bytes and materialization time.
    case clipboardSnapshot(items: Int, bytes: Int, elapsed: Duration)
    /// Debug-only silent playback seam (phase 2).
    case seamSession(state: SeamState)

    public enum SeamState: String, Sendable {
        case started, stopped, finished
    }

    /// The outcome's case name, without any payload.
    public enum OutcomeKind: String, Sendable {
        case text, nothingSelected, unsupported, permissionMissing, cancelled, failed

        public init(_ outcome: CaptureOutcome) {
            switch outcome {
            case .text: self = .text
            case .nothingSelected: self = .nothingSelected
            case .unsupported: self = .unsupported
            case .permissionMissing: self = .permissionMissing
            case .cancelled: self = .cancelled
            case .failed: self = .failed
            }
        }
    }

    /// The rendered form written to the system log. Only enum names and numbers.
    public var rendered: String {
        switch self {
        case let .voicePrewarmed(accelerator):
            "voicePrewarmed accelerator=\(accelerator.rawValue)"
        case let .firstAudio(characters, elapsed, accelerator):
            "firstAudio characters=\(characters) elapsedMs=\(PrivacyEvent.milliseconds(elapsed)) accelerator=\(accelerator.rawValue)"
        case .restoreFailed:
            "restoreFailed"
        case let .capture(kind, outcome, layer, characters, elapsed):
            "capture kind=\(kind.rawValue) outcome=\(outcome.rawValue) layer=\(layer?.rawValue ?? "none") characters=\(characters) elapsedMs=\(PrivacyEvent.milliseconds(elapsed))"
        case let .probe(result, layer, expectedLength, capturedLength, clipboardIntact, focusKept, elapsed, changeDelta):
            "probe result=\(result.rawValue) layer=\(layer?.rawValue ?? "none") expectedLength=\(expectedLength) capturedLength=\(capturedLength) clipboardIntact=\(clipboardIntact) focusKept=\(focusKept) elapsedMs=\(PrivacyEvent.milliseconds(elapsed)) changeDelta=\(changeDelta)"
        case let .clipboardSnapshot(items, bytes, elapsed):
            "clipboardSnapshot items=\(items) bytes=\(bytes) elapsedMs=\(PrivacyEvent.milliseconds(elapsed))"
        case let .seamSession(state):
            "seamSession state=\(state.rawValue)"
        }
    }

    static func milliseconds(_ duration: Duration) -> Int64 {
        Int64(duration / .milliseconds(1))
    }
}

public enum PrivacyLog {
    public static let subsystem = "com.thecreativetoken.captalo"
    private static let logger = Logger(subsystem: subsystem, category: "Events")

    public static func record(_ event: PrivacyEvent) {
        let line = event.rendered
        logger.info("\(line, privacy: .public)")
    }
}
