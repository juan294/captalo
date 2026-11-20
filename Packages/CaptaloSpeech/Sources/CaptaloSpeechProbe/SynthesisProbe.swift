import CaptaloCore
import CaptaloSpeech
import Darwin
import Foundation
import Synchronization

/// `synthesize`: fresh store from the bundle, then the production text
/// pipeline (TextPreparer, UnitChunker, ReadingSession) on the real Kokoro
/// engine for every requested voice. Writes one JSON line per piece and unit
/// and one summary line per voice to `--out`.
enum SynthesisProbe {
    /// Plays instantly (no pace) or at `pace` times real time on a timer, so
    /// the queue and a device change behave as in the app, only faster.
    ///
    /// A paced sink starts its clock once `prefill` buffers are scheduled, so
    /// playback is the bottleneck even when synthesis is slower than the pace
    /// (CI run 44721202345). The paced runs therefore test the queue, stop and
    /// replay logic, not startup timing (the app plays at once). When no new
    /// buffer arrives for `flushAfter` (synthesis failed early), the held
    /// buffers play, so the reading still ends.
    final class ProbeSink: AudioSink, Sendable {
        private struct Clock {
            /// nil until the clock starts.
            var busyUntil: ContinuousClock.Instant?
            var held: [(seconds: Double, played: @Sendable () -> Void)] = []
            /// Changes on every hold and stop, so a stale flush does nothing.
            var holds = 0

            /// Starts the clock if needed and gives each held buffer its due time, in order.
            mutating func release(pace: Double) -> [(ContinuousClock.Instant, @Sendable () -> Void)] {
                defer { held.removeAll() }
                return held.map { buffer in
                    let until = max(busyUntil ?? .now, .now).advanced(by: .seconds(buffer.seconds / pace))
                    busyUntil = until
                    return (until, buffer.played)
                }
            }
        }

        let pace: Double?
        let prefill: Int
        let flushAfter: Duration
        let maxSeconds = Mutex(0.0)
        let firstScheduled = Mutex<ContinuousClock.Instant?>(nil)
        private let clock = Mutex(Clock())
        /// Same rule as the app's AVAudioSink: buffers dropped by a stop are not reported as played.
        private let gate = PlaybackGate()

        init(pace: Double?, prefill: Int = 1, flushAfter: Duration = .seconds(30)) {
            self.pace = pace
            self.prefill = max(1, prefill)
            self.flushAfter = flushAfter
        }

        func schedule(_ samples: [Float], sampleRate: Int, played: @escaping @Sendable () -> Void) -> Bool {
            let seconds = audioSeconds(samples: samples.count, sampleRate: sampleRate)
            maxSeconds.withLock { $0 = max($0, seconds) }
            firstScheduled.withLock { if $0 == nil { $0 = .now } }
            guard let pace else {
                played()
                return true
            }
            let played = gate.gated(played)
            let (due, hold) = clock.withLock { clock -> ([(ContinuousClock.Instant, @Sendable () -> Void)], Int?) in
                clock.held.append((seconds, played))
                if clock.busyUntil == nil, clock.held.count < prefill {
                    clock.holds += 1
                    return ([], clock.holds)
                }
                return (clock.release(pace: pace), nil)
            }
            play(due)
            if let hold {
                Task.detached { [self] in
                    try? await Task.sleep(for: flushAfter)
                    play(clock.withLock { clock in
                        clock.holds == hold && clock.busyUntil == nil ? clock.release(pace: pace) : []
                    })
                }
            }
            return true
        }

        private func play(_ due: [(ContinuousClock.Instant, @Sendable () -> Void)]) {
            for (until, played) in due {
                Task.detached {
                    try? await Task.sleep(until: until, clock: .continuous)
                    played()
                }
            }
        }

        func stop() {
            gate.invalidate()
            clock.withLock { clock in
                clock.held.removeAll()
                clock.holds += 1
                if clock.busyUntil != nil { clock.busyUntil = .now }
            }
        }
    }

    /// Records the engine's view of each synthesized piece.
    final class RecordingSynthesizer: Synthesizer, Sendable {
        struct Call: Sendable {
            let text: String
            let normalizedText: String?
            let phonemes: Int
            let seconds: Double
        }

        let engine: Synthesizer
        let calls = Mutex<[Call]>([])

        init(_ engine: Synthesizer) { self.engine = engine }

        func synthesize(_ text: String, voice: String, speed: Float) async throws -> SynthesizedAudio {
            let audio = try await engine.synthesize(text, voice: voice, speed: speed)
            calls.withLock { $0.append(Call(text: text, normalizedText: audio.normalizedText, phonemes: audio.phonemeCount, seconds: audio.seconds)) }
            return audio
        }
    }

    static func run(_ arguments: Arguments) async throws {
        let bundle = try arguments.url("bundle")
        let storeRoot = try arguments.url("store")
        let manifest = try ModelManifest.load(from: try arguments.url("manifest"))
        let fixture = try String(contentsOf: try arguments.url("fixture"), encoding: .utf8)
        let voices = arguments.list("voices") ?? manifest.voices
        let speed = Float(arguments.values["speed"] ?? "1") ?? 1
        let registry = arguments.values["registry"] ?? KokoroSynthesizer.blockedRegistry
        let stopAfter = arguments.values["stop-after-units"].flatMap(Int.init)
        let out = try arguments.url("out")
        FileManager.default.createFile(atPath: out.path, contents: nil)
        let output = try FileHandle(forWritingTo: out)
        defer { try? output.close() }
        func emit(_ object: [String: Any]) throws {
            output.write(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) + Data("\n".utf8))
        }

        // --no-activate: use the existing store only, so a damaged one is refused, not repaired.
        let setup = VoiceSetup(store: ModelStore(root: storeRoot), manifest: manifest, registry: registry)
        switch await setup.prepare(bundleModels: arguments.values["no-activate"] == nil ? bundle : nil) {
        case .state(.ready): break
        case .state(.damaged): fail("store damaged; refused before the engine", code: 4)
        case let other: fail("voice not ready (\(other))", code: 3)
        }
        let engine = setup.synthesizer

        let expectedUnits = Array(AnySequence { TextPreparer.units(for: .text(fixture)) })
        for voice in voices {
            let recorder = RecordingSynthesizer(engine)
            let sink = ProbeSink(pace: arguments.values["pace"].flatMap(Double.init),
                                 prefill: prefill(expectedUnits: expectedUnits.count))
            let log = Mutex<[ReadingEvent]>([])
            let started = ContinuousClock.now
            let peak = PeakMemory()
            let session = ReadingSession(
                units: { TextPreparer.units(for: .text(fixture)) },
                synthesizer: recorder, sink: sink, voice: voice, speed: speed
            ) { event in log.withLock { $0.append(event) } }

            let deviceChangeAfter = arguments.values["device-change-after-units"].flatMap(Int.init)
            /// Starts the reading and returns once `count` units have played.
            func start(untilPlayed count: Int) async throws {
                await session.start()
                while log.withLock({ $0.count(where: { if case .played = $0 { true } else { false } }) }) < count {
                    try await Task.sleep(for: .milliseconds(2))
                }
            }
            let outcome: ReadingOutcome
            if let deviceChangeAfter {
                try await start(untilPlayed: deviceChangeAfter)
                await session.deviceChanged()
                outcome = await session.outcome()
                let replayed = log.withLock { $0.compactMap { if case let .replayed(id) = $0 { id } else { nil } } }
                let seconds = log.withLock { events in
                    events.compactMap { event -> Double? in
                        guard case let .scheduled(unit, _, _, seconds, _) = event, replayed.contains(unit) else { return nil }
                        return seconds
                    }
                }
                try emit(["kind": "deviceChange", "voice": voice, "afterUnits": deviceChangeAfter,
                          "replayedUnits": replayed, "replaySpanSeconds": seconds.reduce(0, +)])
            } else if let stopAfter {
                try await start(untilPlayed: stopAfter)
                let stopStarted = ContinuousClock.now
                await session.stop() // the sink is silenced inside this call
                let silenceMs = milliseconds(stopStarted.duration(to: .now))
                outcome = await session.outcome() // waits for the in-flight unit to return and be discarded
                let idleMs = milliseconds(stopStarted.duration(to: .now))
                try emit(["kind": "stop", "voice": voice, "afterUnits": stopAfter,
                          "stopToSilenceMs": silenceMs, "stopToIdleMs": idleMs])
            } else {
                outcome = await session.outcome()
            }

            let events = log.withLock { $0 }
            let played = events.compactMap { if case let .played(id) = $0 { id } else { nil } }
            var calls = recorder.calls.withLock { $0 }[...]
            let scheduled = events.compactMap { event -> (unit: Int, sentence: Int, characters: Int, seconds: Double, queued: Double)? in
                guard case let .scheduled(unit, sentence, characters, seconds, queued) = event else { return nil }
                return (unit, sentence, characters, seconds, queued)
            }
            // Each scheduled piece pairs with the next call of the same length;
            // calls in between were oversize results that were split.
            var accepted: [RecordingSynthesizer.Call] = []
            for record in scheduled {
                while let call = calls.popFirst() {
                    if call.text.count == record.characters { accepted.append(call); break }
                }
            }
            for (record, call) in zip(scheduled, accepted) {
                try emit(["kind": "unit", "voice": voice, "unit": record.unit, "sentence": record.sentence,
                          "seconds": record.seconds, "queuedSeconds": record.queued,
                          "characters": call.text.count, "phonemes": call.phonemes,
                          "normalizedText": call.normalizedText ?? NSNull(),
                          "completed": played.contains(record.unit)])
            }
            let squeeze = { (text: String) in text.filter { !$0.isWhitespace } }
            let reassembles = squeeze(accepted.map(\.text).joined()) == squeeze(expectedUnits.map(\.text).joined())
            try emit([
                "kind": "summary", "voice": voice, "outcome": "\(outcome)",
                "units": played.count,
                "expectedUnits": expectedUnits.count,
                "playedExactlyOnceInOrder": played == Array(0..<expectedUnits.count),
                "textReassembles": reassembles,
                "playedInOrder": played == played.sorted() && Set(played).count == played.count,
                "maxUnitSeconds": sink.maxSeconds.withLock { $0 },
                "maxQueuedSeconds": await session.maxQueuedSeconds,
                "maxRetained": await session.maxRetained,
                "firstAudioMs": sink.firstScheduled.withLock { $0 }.map { milliseconds(started.duration(to: $0)) } ?? -1,
                "totalMs": milliseconds(started.duration(to: .now)),
                "peakFootprintMB": peak.stop(),
                "oversizeSplits": events.count(where: { if case .oversizeSplit = $0 { true } else { false } }),
            ])
        }
        await engine.stop()
    }

    /// The audible buffer plus a full lookahead, or the whole text when it is
    /// shorter. The probe's sessions use the default limits, as here.
    static func prefill(expectedUnits: Int) -> Int {
        min(ReadingLimits().lookahead + 1, expectedUnits)
    }

    static func milliseconds(_ duration: Duration) -> Int {
        Int(duration / .milliseconds(1))
    }
}

/// Samples the process footprint every 50 ms and keeps the peak (MB).
final class PeakMemory: Sendable {
    private let task: Task<Void, Never>

    init() {
        let peak = Peak()
        self.shared = peak
        task = Task.detached {
            while !Task.isCancelled {
                peak.update(PeakMemory.footprintMB())
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private let shared: Peak

    func stop() -> Double {
        task.cancel()
        shared.update(PeakMemory.footprintMB())
        return (shared.value * 10).rounded() / 10
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    /// The peak, shared with the sampling task.
    final class Peak: Sendable {
        private let value_ = Mutex(0.0)
        func update(_ value: Double) { value_.withLock { $0 = max($0, value) } }
        var value: Double { value_.withLock { $0 } }
    }
}
