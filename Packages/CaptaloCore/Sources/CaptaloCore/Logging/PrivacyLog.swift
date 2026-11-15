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

    /// The rendered form written to the system log. Only enum names and numbers.
    public var rendered: String {
        switch self {
        case let .voicePrewarmed(accelerator):
            "voicePrewarmed accelerator=\(accelerator.rawValue)"
        case let .firstAudio(characters, elapsed, accelerator):
            "firstAudio characters=\(characters) elapsedMs=\(PrivacyEvent.milliseconds(elapsed)) accelerator=\(accelerator.rawValue)"
        }
    }

    static func milliseconds(_ duration: Duration) -> Int64 {
        let parts = duration.components
        return parts.seconds * 1_000 + parts.attoseconds / 1_000_000_000_000_000
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
