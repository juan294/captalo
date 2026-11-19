import Foundation
import Synchronization

/// Builds one reading's `PrivacyEvent.reading` from its session events.
///
/// Added after a stalled audio engine (2026-11-19) left no trace: units were
/// handed to the sink, none played, and nothing logged the reading.
///
/// Times are measured from the session's creation, so they include the stop
/// of the reading it replaces; a stopped reading's `elapsed` can include an
/// in-flight synthesis that finishes after the stop. A unit the sink refused
/// still counts as scheduled; the reading then ends with `voiceError`.
public final class ReadingLogRecorder: Sendable {
    private struct Counts {
        /// Units, not pieces: an oversize unit is scheduled in pieces and plays once.
        var scheduled: Set<Int> = []
        var played = 0
        var replays = 0
        var firstScheduled: Duration?
    }

    private let counts = Mutex(Counts())
    private let now: @Sendable () -> ContinuousClock.Instant
    private let started: ContinuousClock.Instant

    public init(now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }) {
        self.now = now
        started = now()
    }

    public func observe(_ event: ReadingEvent) {
        let elapsed = started.duration(to: now())
        counts.withLock { counts in
            switch event {
            case let .scheduled(unitID, _, _, _, _):
                counts.scheduled.insert(unitID)
                if counts.firstScheduled == nil { counts.firstScheduled = elapsed }
            case .played:
                counts.played += 1
            case .replayed:
                counts.replays += 1
            case .oversizeSplit:
                break
            }
        }
    }

    public func event(outcome: ReadingOutcome) -> PrivacyEvent {
        let counts = counts.withLock { $0 }
        return .reading(outcome: outcome, scheduled: counts.scheduled.count, played: counts.played, replays: counts.replays,
                        firstScheduled: counts.firstScheduled, elapsed: started.duration(to: now()))
    }
}
