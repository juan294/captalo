import Foundation
import Synchronization
import Testing
@testable import CaptaloCore

/// In-memory synthesizer: seconds of audio per text from `seconds`, with an
/// optional failure, an optional gate, and concurrency tracking.
final class FakeSynthesizer: Synthesizer, Sendable {
    let rate = 100 // samples per second keeps buffers small
    let seconds: @Sendable (String) -> Double
    let failAt: Int?
    let gate: Gate?
    let calls = Mutex<[String]>([])
    let speeds = Mutex<[Float]>([])
    let inFlight = Mutex(0)
    let maxInFlight = Mutex(0)

    init(failAt: Int? = nil, gate: Gate? = nil, seconds: @escaping @Sendable (String) -> Double = { _ in 1 }) {
        self.failAt = failAt
        self.gate = gate
        self.seconds = seconds
    }

    func synthesize(_ text: String, voice: String, speed: Float) async throws -> SynthesizedAudio {
        let index = calls.withLock { $0.append(text); return $0.count - 1 }
        speeds.withLock { $0.append(speed) }
        let now = inFlight.withLock { $0 += 1; return $0 }
        maxInFlight.withLock { $0 = max($0, now) }
        defer { inFlight.withLock { $0 -= 1 } }
        await gate?.wait()
        if index == failAt { throw CancellationError() }
        return SynthesizedAudio(samples: Array(repeating: 0.1, count: Int(seconds(text) * Double(rate))), sampleRate: rate)
    }
}

/// In-memory sink. With `autoplay`, every buffer plays as soon as it is
/// scheduled; otherwise the test calls `playNext()`. `stop()` drops buffers
/// and fires their callbacks, as AVAudioPlayerNode does.
final class FakeSink: AudioSink, Sendable {
    let autoplay: Bool
    let pending = Mutex<[(@Sendable () -> Void, Int)]>([])
    let scheduledSamples = Mutex<[Int]>([])
    let stops = Mutex(0)
    /// Schedules after this many succeed fail (engine down).
    let failAfter = Mutex<Int?>(nil)
    /// Models AVAudioSink: callbacks pass through a PlaybackGate.
    let gate = PlaybackGate()

    init(autoplay: Bool) { self.autoplay = autoplay }

    func schedule(_ samples: [Float], sampleRate: Int, played: @escaping @Sendable () -> Void) -> Bool {
        let allowed = failAfter.withLock { limit -> Bool in
            guard let remaining = limit else { return true }
            if remaining == 0 { return false }
            limit = remaining - 1
            return true
        }
        guard allowed else { return false }
        scheduledSamples.withLock { $0.append(samples.count) }
        let gated = gate.gated(played)
        if autoplay { gated() } else { pending.withLock { $0.append((gated, samples.count)) } }
        return true
    }

    /// Models an engine restart: the gate is invalidated, then the player
    /// stop completes every dropped buffer (before the session hears of it).
    func simulateConfigurationChange() {
        gate.invalidate()
        let dropped = pending.withLock { list -> [(@Sendable () -> Void, Int)] in defer { list.removeAll() }; return list }
        dropped.forEach { $0.0() }
    }

    func stop() {
        stops.withLock { $0 += 1 }
        let dropped = pending.withLock { list -> [(@Sendable () -> Void, Int)] in defer { list.removeAll() }; return list }
        dropped.forEach { $0.0() }
    }

    @discardableResult
    func playNext() -> Bool {
        guard let next = pending.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) else { return false }
        next.0()
        return true
    }

    var pendingCount: Int { pending.withLock { $0.count } }
}

func sentences(_ count: Int, paragraphEvery: Int = 1_000) -> @Sendable () -> AnyIterator<SynthesisUnit> {
    {
        let paragraphs = stride(from: 0, to: count, by: paragraphEvery).map { start in
            Paragraph(sentences: (start..<min(start + paragraphEvery, count)).map { "Sentence number \($0)." })
        }
        return AnyIterator(UnitChunker(paragraphs).makeIterator())
    }
}

func eventually(_ condition: @Sendable () async -> Bool) async {
    for _ in 0..<500 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(2))
    }
}

final class Events: Sendable {
    let list = Mutex<[ReadingEvent]>([])
    func append(_ event: ReadingEvent) { list.withLock { $0.append(event) } }
    var played: [Int] { list.withLock { $0.compactMap { if case let .played(id) = $0 { id } else { nil } } } }
    var scheduled: [ReadingEvent] { list.withLock { $0.filter { if case .scheduled = $0 { true } else { false } } } }
}

@Suite struct ReadingSessionTests {
    func session(_ units: @escaping @Sendable () -> AnyIterator<SynthesisUnit>, _ synth: FakeSynthesizer, _ sink: FakeSink,
                 events: Events = Events(), speed: Float = 1) -> ReadingSession {
        ReadingSession(units: units, synthesizer: synth, sink: sink, voice: "af_heart", speed: speed) { events.append($0) }
    }

    @Test func synthesisNeverRunsMoreThan3Ahead() async {
        let synth = FakeSynthesizer()
        let sink = FakeSink(autoplay: false)
        let reading = session(sentences(50), synth, sink)
        await reading.start()
        await eventually { sink.pendingCount == 4 }
        try? await Task.sleep(for: .milliseconds(30))
        #expect(synth.calls.withLock { $0.count } == 4) // the audible unit plus 3
        sink.playNext()
        await eventually { synth.calls.withLock { $0.count } == 5 }
        try? await Task.sleep(for: .milliseconds(30))
        #expect(synth.calls.withLock { $0.count } == 5)
        await reading.stop()
    }

    @Test func atMostOneInFlightUnit() async {
        let synth = FakeSynthesizer()
        let reading = session(sentences(200), synth, FakeSink(autoplay: true))
        #expect(await reading.outcome() == .finished)
        #expect(synth.maxInFlight.withLock { $0 } == 1)
    }

    @Test func queuedSecondsNeverExceedBound() async {
        let synth = FakeSynthesizer { _ in 34.9 }
        let sink = FakeSink(autoplay: false)
        let reading = session(sentences(20), synth, sink)
        await reading.start()
        for _ in 0..<16 {
            await eventually { sink.pendingCount >= 1 }
            sink.playNext()
        }
        await reading.stop()
        #expect(await reading.maxQueuedSeconds <= ReadingLimits().maxQueuedSeconds)
        #expect(await reading.maxRetained <= 4)
    }

    @Test func playedBuffersAreReleased() async {
        let reading = session(sentences(2_000, paragraphEvery: 7), FakeSynthesizer(), FakeSink(autoplay: true))
        #expect(await reading.outcome() == .finished)
        #expect(await reading.maxRetained <= 4)
        #expect(await reading.retainedBuffers == 0)
    }

    @Test func allUnitsPlayedExactlyOnceInOrder() async {
        let events = Events()
        let reading = session(sentences(120, paragraphEvery: 5), FakeSynthesizer(), FakeSink(autoplay: true), events: events)
        #expect(await reading.outcome() == .finished)
        #expect(events.played == Array(0..<120))
    }

    @Test func deviceChangeReplaysCurrentUnitOnly() async {
        let events = Events()
        let sink = FakeSink(autoplay: false)
        let reading = session(sentences(10), FakeSynthesizer(), sink, events: events)
        await reading.start()
        await eventually { sink.pendingCount == 4 }
        sink.playNext() // unit 0 played; unit 1 is audible
        await eventually { sink.pendingCount == 4 }
        await reading.deviceChanged()
        #expect(events.list.withLock { $0.contains(.replayed(unitID: 1)) })
        for _ in 0..<20 {
            await eventually { sink.pendingCount >= 1 || events.played.count == 10 }
            if !sink.playNext() { break }
        }
        #expect(await reading.outcome() == .finished)
        // Each unit is reported played exactly once; the replay restarted unit 1 from its beginning.
        #expect(events.played == Array(0..<10))
    }

    @Test func chunkFailureEndsSessionAndReportsVoiceError() async {
        let events = Events()
        let sink = FakeSink(autoplay: false)
        let reading = session(sentences(10), FakeSynthesizer(failAt: 3), sink, events: events)
        await reading.start()
        await eventually { sink.pendingCount == 3 }
        try? await Task.sleep(for: .milliseconds(20))
        // The failure does not silence scheduled audio: units 0-2 still play.
        #expect(sink.stops.withLock { $0 } == 0)
        #expect(sink.pendingCount == 3)
        while sink.playNext() { try? await Task.sleep(for: .milliseconds(2)) }
        #expect(await reading.outcome() == .voiceError)
        #expect(events.played == [0, 1, 2])
    }

    @Test func oversizeResultIsSplitAndReSynthesizedInOrder() async {
        let long = String(repeating: "word ", count: 60).trimmingCharacters(in: .whitespaces) + "."
        let events = Events()
        // Anything over 150 characters synthesizes to 40 s (oversize); shorter pieces to 5 s.
        let synth = FakeSynthesizer { $0.count > 150 ? 40 : 5 }
        let units: @Sendable () -> AnyIterator<SynthesisUnit> = {
            AnyIterator(UnitChunker([Paragraph(sentences: ["Short.", long, "End."])]).makeIterator())
        }
        let reading = session(units, synth, FakeSink(autoplay: true), events: events)
        #expect(await reading.outcome() == .finished)
        let calls = synth.calls.withLock { $0 }
        #expect(calls.first == "Short.")
        #expect(calls.last == "End.")
        let pieces = calls.dropFirst().dropLast().filter { $0.count <= 150 }
        #expect(pieces.joined(separator: " ") == long)
        #expect(events.list.withLock { $0.contains(.oversizeSplit(unitID: 1)) })
    }

    @Test func minimumPieceStillOversizeEndsWithVoiceError() async {
        let events = Events()
        let long = String(repeating: "word ", count: 60).trimmingCharacters(in: .whitespaces) + "."
        // The first unit is fine; every piece of the long unit stays oversize.
        let synth = FakeSynthesizer { $0 == "Short." ? 1 : 36 }
        let units: @Sendable () -> AnyIterator<SynthesisUnit> = {
            AnyIterator(UnitChunker([Paragraph(sentences: ["Short.", long])]).makeIterator())
        }
        let reading = session(units, synth, FakeSink(autoplay: true), events: events)
        #expect(await reading.outcome() == .voiceError)
        #expect(events.played == [0]) // scheduled audio played before the error
        let pieces = synth.calls.withLock { $0 }.dropFirst()
        #expect(pieces.allSatisfy { $0.count >= ReadingLimits().minimumSplitLength })
        #expect(pieces.contains { $0.count < ReadingLimits().minimumSplitLength * 2 }) // split down to the minimum
    }

    @Test func unbalancedBreakFallsBackToAMidpointSplit() async {
        // One space near the start: the preferred break would leave a 3-character head.
        let text = "abc " + String(repeating: "x", count: 150)
        let synth = FakeSynthesizer { $0.count > 100 ? 40 : 5 }
        let units: @Sendable () -> AnyIterator<SynthesisUnit> = {
            AnyIterator(UnitChunker([Paragraph(sentences: ["Short.", text])]).makeIterator())
        }
        #expect(await session(units, synth, FakeSink(autoplay: true)).outcome() == .finished)
        #expect(synth.calls.withLock { $0 }.dropFirst().filter { $0.count <= 100 }.allSatisfy { $0.count >= 40 })
    }

    @Test func sinkFailureEndsWithVoiceErrorAfterScheduledAudio() async {
        let events = Events()
        let sink = FakeSink(autoplay: true)
        sink.failAfter.withLock { $0 = 2 }
        let reading = session(sentences(6), FakeSynthesizer(), sink, events: events)
        #expect(await reading.outcome() == .voiceError)
        #expect(events.played == [0, 1])
    }

    /// Blocker regression (phase 3 review): the engine restart's player stop
    /// completes dropped buffers before the session hears of the change. The
    /// audible unit must still replay from its start.
    @Test func engineRestartCompletionsDoNotSkipTheAudibleUnit() async {
        let events = Events()
        let sink = FakeSink(autoplay: false)
        let reading = session(sentences(8), FakeSynthesizer(), sink, events: events)
        await reading.start()
        await eventually { sink.pendingCount == 4 }
        sink.playNext() // unit 0 played; unit 1 is audible
        await eventually { sink.pendingCount == 4 }
        sink.simulateConfigurationChange()
        try? await Task.sleep(for: .milliseconds(20))
        await reading.deviceChanged()
        #expect(events.list.withLock { $0.contains(.replayed(unitID: 1)) })
        for _ in 0..<20 {
            await eventually { sink.pendingCount >= 1 || events.played.count == 8 }
            if !sink.playNext() { break }
        }
        #expect(await reading.outcome() == .finished)
        #expect(events.played == Array(0..<8))
    }

    @Test func oversizeResultNeverEnqueued() async {
        let sink = FakeSink(autoplay: true)
        let synth = FakeSynthesizer { $0.count > 150 ? 40 : 5 }
        let long = String(repeating: "word ", count: 60) + "."
        let reading = session({ AnyIterator(UnitChunker([Paragraph(sentences: ["Short.", long])]).makeIterator()) }, synth, sink)
        _ = await reading.outcome()
        let maxSamples = sink.scheduledSamples.withLock { $0.max() ?? 0 }
        #expect(Double(maxSamples) / Double(synth.rate) <= ReadingLimits().maxUnitSeconds)
    }

    @Test func stopDuringFirstSynthesisSilencesAtOnceAndDropsResult() async {
        let gate = Gate()
        let sink = FakeSink(autoplay: false)
        let synth = FakeSynthesizer(gate: gate)
        let reading = session(sentences(5), synth, sink)
        await reading.start()
        await eventually { synth.calls.withLock { $0.count } == 1 }
        await reading.stop()
        #expect(sink.stops.withLock { $0 } == 1)
        await gate.open()
        #expect(await reading.outcome() == .stopped)
        #expect(sink.scheduledSamples.withLock { $0 }.isEmpty)
    }

    @Test func repeatedReplacementLeavesOneSession() async {
        let sink = FakeSink(autoplay: false)
        var sessions: [ReadingSession] = []
        for _ in 0..<5 {
            if let old = sessions.last { await old.stop() }
            let next = session(sentences(3), FakeSynthesizer(), sink)
            await next.start()
            sessions.append(next)
        }
        await eventually { sink.pendingCount == 3 }
        // Only the last session's buffers remain; every earlier one ended stopped.
        for old in sessions.dropLast() { #expect(await old.outcome() == .stopped) }
        #expect(sink.pendingCount == 3)
        await sessions.last?.stop()
    }

    @Test func staleCallbackAfterEngineRestartIgnored() async {
        let events = Events()
        let sink = FakeSink(autoplay: false)
        let reading = session(sentences(2), FakeSynthesizer(), sink, events: events)
        await reading.start()
        await eventually { sink.pendingCount == 2 }
        let stale = sink.pending.withLock { $0[0].0 }
        await reading.deviceChanged() // the stop fires the old callbacks; they must be ignored
        stale()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(events.played.isEmpty)
        while sink.playNext() { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(await reading.outcome() == .finished)
        #expect(events.played == [0, 1])
    }

    /// Regression: callbacks hop to the session through separate tasks and can
    /// arrive out of order; buffers are still released, and reported, in order.
    @Test func outOfOrderPlaybackCallbacksReleaseInOrder() async {
        let events = Events()
        let sink = FakeSink(autoplay: false)
        let reading = session(sentences(2), FakeSynthesizer(), sink, events: events)
        await reading.start()
        await eventually { sink.pendingCount == 2 }
        let callbacks = sink.pending.withLock { list in defer { list.removeAll() }; return list.map(\.0) }
        callbacks[1]()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(events.played.isEmpty)
        callbacks[0]()
        #expect(await reading.outcome() == .finished)
        #expect(events.played == [0, 1])
    }

    @Test func speedChangeAppliesFromNextReading() async {
        let synth = FakeSynthesizer()
        let first = session(sentences(3), synth, FakeSink(autoplay: true), speed: 1.0)
        _ = await first.outcome()
        let second = session(sentences(3), synth, FakeSink(autoplay: true), speed: 1.2)
        _ = await second.outcome()
        #expect(synth.speeds.withLock { $0 } == [1, 1, 1, 1.2, 1.2, 1.2])
    }

    @Test func pausesFollowSentencesAndParagraphs() async {
        let sink = FakeSink(autoplay: true)
        let units: @Sendable () -> AnyIterator<SynthesisUnit> = {
            AnyIterator(UnitChunker([Paragraph(sentences: ["One.", "Two."]), Paragraph(sentences: ["Three."])]).makeIterator())
        }
        _ = await session(units, FakeSynthesizer(), sink).outcome()
        // 1 s of audio = 100 samples; +0.30 s after a sentence; +0.35 s more after a paragraph.
        #expect(sink.scheduledSamples.withLock { $0 } == [130, 165, 165])
    }
}

@Suite struct PlaybackGateTests {
    @Test func invalidationSuppressesEarlierCallbacksOnly() {
        let gate = PlaybackGate()
        let fired = Mutex<[String]>([])
        let before = gate.gated { fired.withLock { $0.append("before") } }
        gate.invalidate()
        let after = gate.gated { fired.withLock { $0.append("after") } }
        before()
        after()
        #expect(fired.withLock { $0 } == ["after"])
    }
}
