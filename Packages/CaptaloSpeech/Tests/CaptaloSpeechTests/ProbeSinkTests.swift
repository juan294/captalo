import CaptaloCore
import Foundation
import Synchronization
import Testing
@testable import CaptaloSpeechProbe

/// Synthesis slower than paced playback, as on a hosted CI runner: each call
/// waits `delay` and returns one second of audio.
final class SlowSynthesizer: Synthesizer, Sendable {
    let delay: Duration
    init(delay: Duration) { self.delay = delay }

    func synthesize(_ text: String, voice: String, speed: Float) async throws -> SynthesizedAudio {
        try await Task.sleep(for: delay)
        return SynthesizedAudio(samples: Array(repeating: 0.1, count: 100), sampleRate: 100)
    }
}

/// Returns one second of audio for the first `succeed` calls, then throws.
final class FailingSynthesizer: Synthesizer, Sendable {
    let succeed: Int
    let calls = Mutex(0)
    init(succeed: Int) { self.succeed = succeed }

    func synthesize(_ text: String, voice: String, speed: Float) async throws -> SynthesizedAudio {
        let index = calls.withLock { $0 += 1; return $0 - 1 }
        if index >= succeed { throw CancellationError() }
        return SynthesizedAudio(samples: Array(repeating: 0.1, count: 100), sampleRate: 100)
    }
}

@Suite(.timeLimit(.minutes(1))) struct ProbeSinkTests {
    /// The completeness test's paced device-change run (run 44721202345): the
    /// queue must fill and a unit must be audible at the change, however slow
    /// synthesis is relative to the paced playback. Each unit (1 s of audio
    /// plus 0.65 s of pauses) plays for 165 ms and takes 250 ms to synthesize,
    /// so synthesis is the bottleneck, as on the hosted runner.
    @Test func pacedDeviceChangeReplaysOneUnitWhenSynthesisIsSlow() async throws {
        let fixture = (1...8).map { "Paragraph \($0) has one short sentence for the probe." }.joined(separator: "\n\n")
        let expected = Array(AnySequence { TextPreparer.units(for: .text(fixture)) }).count
        try #require(expected >= 6)
        let sink = SynthesisProbe.ProbeSink(pace: 10, prefill: SynthesisProbe.prefill(expectedUnits: expected))
        let events = Mutex<[ReadingEvent]>([])
        let session = ReadingSession(
            units: { TextPreparer.units(for: .text(fixture)) },
            synthesizer: SlowSynthesizer(delay: .milliseconds(250)), sink: sink, voice: "v", speed: 1
        ) { event in events.withLock { $0.append(event) } }

        await session.start()
        while events.withLock({ $0.count(where: { if case .played = $0 { true } else { false } }) }) < 3 {
            try await Task.sleep(for: .milliseconds(1))
        }
        await session.deviceChanged()
        #expect(await session.outcome() == .finished)

        let log = events.withLock { $0 }
        #expect(log.compactMap { if case let .replayed(id) = $0 { id } else { nil } }.count == 1)
        #expect(await session.maxQueuedSeconds > 0)
        #expect(log.compactMap { if case let .played(id) = $0 { id } else { nil } } == Array(0..<expected))
    }

    /// Synthesis fails before the prefill is reached: the held buffers play once
    /// no new buffer arrives, and the reading ends with a voice error, not a hang.
    @Test func synthesisFailureBeforePrefillEndsWithVoiceError() async throws {
        let fixture = (1...8).map { "Paragraph \($0) has one short sentence for the probe." }.joined(separator: "\n\n")
        let sink = SynthesisProbe.ProbeSink(pace: 10, prefill: 4, flushAfter: .milliseconds(200))
        let events = Mutex<[ReadingEvent]>([])
        let session = ReadingSession(
            units: { TextPreparer.units(for: .text(fixture)) },
            synthesizer: FailingSynthesizer(succeed: 2), sink: sink, voice: "v", speed: 1
        ) { event in events.withLock { $0.append(event) } }

        #expect(await session.outcome() == .voiceError)
        #expect(events.withLock { $0 }.compactMap { if case let .played(id) = $0 { id } else { nil } } == [0, 1])
    }

    /// A text shorter than the lookahead still plays: the prefill never waits
    /// for more buffers than the text has.
    @Test func prefillIsCappedByTheUnitCount() {
        #expect(SynthesisProbe.prefill(expectedUnits: 2) == 2)
        #expect(SynthesisProbe.prefill(expectedUnits: 50) == ReadingLimits().lookahead + 1)
    }
}
