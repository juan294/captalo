import Synchronization
import Testing
@testable import CaptaloCore

@Suite struct PrivacyLogTests {
    static let allCases: [PrivacyEvent] = [
        .voicePrewarmed(accelerator: .neuralEngine),
        .voicePrewarmed(accelerator: .cpuAndGPU),
        .firstAudio(characters: 42, elapsed: .milliseconds(1_250), accelerator: .neuralEngine),
        .restoreFailed,
        .capture(kind: .selection, outcome: .text, layer: .menuCopy, characters: 12, elapsed: .milliseconds(80)),
        .capture(kind: .region, outcome: .failed, layer: nil, characters: 0, elapsed: .seconds(10)),
        .probe(result: .pass, layer: .accessibility, expectedLength: 300, capturedLength: 300,
               clipboardIntact: true, focusKept: true, elapsed: .milliseconds(12), changeDelta: 0),
        .clipboardSnapshot(items: 2, bytes: 4_096, elapsed: .milliseconds(3)),
        .seamSession(state: .started),
        .secondInstance,
        .ocr(outcome: .document, failure: nil, blocks: 4, characters: 120, elapsed: .milliseconds(900)),
        .ocr(outcome: .failed, failure: .ocrBusy, blocks: 0, characters: 0, elapsed: .milliseconds(1)),
        .ocr(outcome: .failed, failure: .captureTimedOut, blocks: 0, characters: 0, elapsed: .seconds(10)),
        .reading(outcome: .voiceError, scheduled: 2, played: 1, replays: 1,
                 firstScheduled: .milliseconds(420), elapsed: .seconds(3)),
        .reading(outcome: .stopped, scheduled: 0, played: 0, replays: 0, firstScheduled: nil, elapsed: .seconds(1)),
    ]

    @Test func eventsRenderOnlyEnumNamesAndNumbers() {
        // Allowed tokens: an event name, then key=value pairs whose value is
        // an integer or a known enum raw value.
        var enumValues = Set(["neuralEngine", "cpuAndGPU", "true", "false", "none", "started", "stopped", "finished"])
        enumValues.formUnion(["selection", "region", "text", "document", "nothingSelected", "unsupported", "permissionMissing", "cancelled", "failed"])
        enumValues.formUnion(["accessibility", "menuCopy", "syntheticCopy", "ocr", "pass", "fail"])
        enumValues.formUnion(["ocrBusy", "ocrFailed", "ocrTimedOut", "captureTimedOut", "voiceError"])
        for event in Self.allCases {
            let parts = event.rendered.split(separator: " ")
            #expect(!parts.isEmpty)
            let nameIsWord = parts[0].allSatisfy { $0.isLetter }
            #expect(nameIsWord)
            for pair in parts.dropFirst() {
                let kv = pair.split(separator: "=", maxSplits: 1)
                #expect(kv.count == 2, "\(pair)")
                guard kv.count == 2 else { continue }
                let value = String(kv[1])
                #expect(Int64(value) != nil || enumValues.contains(value), "\(pair)")
            }
        }
    }

    static func name(_ event: PrivacyEvent) -> String {
        String(event.rendered.prefix { $0 != " " })
    }

    /// Exhaustive switch: adding a case fails to compile until it is counted
    /// here, and the count must match the names sampled in `allCases`.
    static let caseCount = PrivacyEvent.voicePrewarmed(accelerator: .neuralEngine).arms

    @Test func allCasesCoversEveryCase() {
        #expect(Set(Self.allCases.map(Self.name)).count == Self.caseCount)
    }

    @Test func ocrBusyIsDistinguishable() {
        let event = PrivacyEvent.ocr(outcome: .failed, failure: .ocrBusy, blocks: 0, characters: 0, elapsed: .milliseconds(2))
        #expect(event.rendered == "ocr outcome=failed failure=ocrBusy blocks=0 characters=0 elapsedMs=2")
    }

    @Test func firstAudioRendersMilliseconds() {
        let event = PrivacyEvent.firstAudio(characters: 7, elapsed: .milliseconds(1_250), accelerator: .cpuAndGPU)
        #expect(event.rendered == "firstAudio characters=7 elapsedMs=1250 accelerator=cpuAndGPU")
    }

    @Test func readingRendersCountsAndOptionalFirstScheduled() {
        let silent = PrivacyEvent.reading(outcome: .stopped, scheduled: 2, played: 0, replays: 0,
                                          firstScheduled: .milliseconds(380), elapsed: .milliseconds(4_200))
        #expect(silent.rendered == "reading outcome=stopped scheduled=2 played=0 replays=0 firstScheduledMs=380 elapsedMs=4200")
        let empty = PrivacyEvent.reading(outcome: .finished, scheduled: 0, played: 0, replays: 0,
                                         firstScheduled: nil, elapsed: .milliseconds(5))
        #expect(empty.rendered == "reading outcome=finished scheduled=0 played=0 replays=0 firstScheduledMs=none elapsedMs=5")
    }
}

/// One reading's log line from its session events (2026-11-19: a stalled audio
/// engine left no trace because nothing logged a reading).
@Suite struct ReadingLogRecorderTests {
    final class Clock: Sendable {
        let base = ContinuousClock.now
        let offset = Mutex<Duration>(.zero)
        func now() -> ContinuousClock.Instant { base.advanced(by: offset.withLock { $0 }) }
        func advance(_ d: Duration) { offset.withLock { $0 += d } }
    }

    @Test func countsScheduledPlayedAndReplayedUnits() {
        let clock = Clock()
        let recorder = ReadingLogRecorder(now: clock.now)
        clock.advance(.milliseconds(300))
        recorder.observe(.scheduled(unitID: 0, sentenceID: 0, characters: 10, seconds: 1, queuedSeconds: 0))
        clock.advance(.milliseconds(200))
        recorder.observe(.scheduled(unitID: 1, sentenceID: 1, characters: 12, seconds: 1, queuedSeconds: 1))
        recorder.observe(.played(unitID: 0))
        recorder.observe(.replayed(unitID: 1))
        recorder.observe(.oversizeSplit(unitID: 1))
        clock.advance(.milliseconds(500))
        #expect(recorder.event(outcome: .finished)
            == .reading(outcome: .finished, scheduled: 2, played: 1, replays: 1,
                        firstScheduled: .milliseconds(300), elapsed: .seconds(1)))
    }

    /// The 2026-11-19 failure: units reach the sink, none plays, the user stops it.
    @Test func stalledReadingShowsScheduledButNotPlayed() {
        let clock = Clock()
        let recorder = ReadingLogRecorder(now: clock.now)
        recorder.observe(.scheduled(unitID: 0, sentenceID: 0, characters: 49, seconds: 3, queuedSeconds: 0))
        clock.advance(.seconds(4))
        let event = recorder.event(outcome: .stopped)
        #expect(event.rendered == "reading outcome=stopped scheduled=1 played=0 replays=0 firstScheduledMs=0 elapsedMs=4000")
    }
}

private extension PrivacyEvent {
    /// The number of cases; the switch has no default.
    var arms: Int {
        switch self {
        case .voicePrewarmed, .firstAudio, .restoreFailed, .capture, .probe, .clipboardSnapshot, .seamSession, .secondInstance, .ocr, .reading: 10
        }
    }
}
