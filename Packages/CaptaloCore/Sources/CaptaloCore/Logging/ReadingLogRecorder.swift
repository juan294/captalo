import Foundation
import Synchronization

/// Builds one reading's `PrivacyEvent.reading` from its session events.
///
/// Added after a stalled audio engine (2026-11-19) left no trace: units were
/// handed to the sink, none played, and nothing logged the reading.
public final class ReadingLogRecorder: Sendable {
    private struct Counts {
        var scheduled = 0
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
            case .scheduled:
                counts.scheduled += 1
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
        return .reading(outcome: outcome, scheduled: counts.scheduled, played: counts.played, replays: counts.replays,
                        firstScheduled: counts.firstScheduled, elapsed: started.duration(to: now()))
    }
}
