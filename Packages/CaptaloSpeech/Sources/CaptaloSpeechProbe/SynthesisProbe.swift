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
    /// Plays instantly: the pipeline is exercised at engine speed.
    final class InstantSink: AudioSink, Sendable {
        let maxSeconds = Mutex(0.0)
        let firstScheduled = Mutex<ContinuousClock.Instant?>(nil)

        func schedule(_ samples: [Float], sampleRate: Int, played: @escaping @Sendable () -> Void) -> Bool {
            let seconds = Double(samples.count) / Double(max(sampleRate, 1))
            maxSeconds.withLock { $0 = max($0, seconds) }
            firstScheduled.withLock { if $0 == nil { $0 = .now } }
            played()
            return true
        }

        func stop() {}
    }

    /// Plays at `pace` times real time on a timer, so the queue and a device
    /// change behave as in the app, only faster.
    final class PacedSink: AudioSink, Sendable {
        let pace: Double
        let maxSeconds = Mutex(0.0)
        let firstScheduled = Mutex<ContinuousClock.Instant?>(nil)
        private let state = Mutex<(busyUntil: ContinuousClock.Instant, generation: Int)>((.now, 0))
        /// Same rule as the app's AVAudioSink: buffers dropped by a stop are not reported as played.
        private let gate = PlaybackGate()

        init(pace: Double) { self.pace = pace }

        func schedule(_ samples: [Float], sampleRate: Int, played: @escaping @Sendable () -> Void) -> Bool {
            let played = gate.gated(played)
            let seconds = Double(samples.count) / Double(max(sampleRate, 1))
            maxSeconds.withLock { $0 = max($0, seconds) }
            firstScheduled.withLock { if $0 == nil { $0 = .now } }
            let due = state.withLock { s -> ContinuousClock.Instant in
                let start = max(s.busyUntil, .now)
                s.busyUntil = start.advanced(by: .seconds(seconds / pace))
                return s.busyUntil
            }
            Task.detached {
                try? await Task.sleep(until: due, clock: .continuous)
                played()
            }
            return true
        }

        func stop() {
            gate.invalidate()
            state.withLock { $0 = (.now, $0.generation + 1) }
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
            let seconds = Double(audio.samples.count) / Double(max(audio.sampleRate, 1))
            calls.withLock { $0.append(Call(text: text, normalizedText: audio.normalizedText, phonemes: audio.phonemeCount, seconds: seconds)) }
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

        for voice in voices {
            let recorder = RecordingSynthesizer(engine)
            let pace = arguments.values["pace"].flatMap(Double.init)
            let paced = pace.map(PacedSink.init(pace:))
            let instant = InstantSink()
            let sink: AudioSink = paced ?? instant
            let maxUnitSeconds = { paced?.maxSeconds.withLock { $0 } ?? instant.maxSeconds.withLock { $0 } }
            let firstScheduled = { paced?.firstScheduled.withLock { $0 } ?? instant.firstScheduled.withLock { $0 } }
            let log = Mutex<[ReadingEvent]>([])
            let blocks = Array(TextPreparer.blocks(fromSelection: fixture))
            let started = ContinuousClock.now
            let peak = PeakMemory()
            let session = ReadingSession(
                units: { AnyIterator(UnitChunker(TextPreparer.prepare(blocks, source: .selection)).makeIterator()) },
                synthesizer: recorder, sink: sink, voice: voice, speed: speed
            ) { event in log.withLock { $0.append(event) } }

            let deviceChangeAfter = arguments.values["device-change-after-units"].flatMap(Int.init)
            let playedCount = { log.withLock { $0.count(where: { if case .played = $0 { true } else { false } }) } }
            let outcome: ReadingOutcome
            if let deviceChangeAfter {
                await session.start()
                while playedCount() < deviceChangeAfter { try await Task.sleep(for: .milliseconds(2)) }
                await session.deviceChanged()
                outcome = await session.outcome()
                let replayed = log.withLock { $0.compactMap { if case let .replayed(id) = $0 { id } else { nil } } }
                let seconds = log.withLock { events in
                    events.compactMap { event -> Double? in
                        guard case let .scheduled(unit, _, seconds, _) = event, replayed.contains(unit) else { return nil }
                        return seconds
                    }
                }
                try emit(["kind": "deviceChange", "voice": voice, "afterUnits": deviceChangeAfter,
                          "replayedUnits": replayed, "replaySpanSeconds": seconds.reduce(0, +)])
            } else if let stopAfter {
                await session.start()
                while playedCount() < stopAfter { try await Task.sleep(for: .milliseconds(2)) }
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
            let expectedUnits = Array(UnitChunker(TextPreparer.prepare(blocks, source: .selection)))
            let calls = recorder.calls.withLock { $0 }
            let scheduled = events.compactMap { event -> (unit: Int, sentence: Int, seconds: Double, queued: Double)? in
                guard case let .scheduled(unit, sentence, seconds, queued) = event else { return nil }
                return (unit, sentence, seconds, queued)
            }
            // One scheduled event per successfully synthesized piece, in call order
            // (oversize results are re-synthesized and never scheduled).
            let accepted = calls.filter { $0.seconds <= ReadingLimits().maxUnitSeconds }
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
                "maxUnitSeconds": maxUnitSeconds(),
                "maxQueuedSeconds": await session.maxQueuedSeconds,
                "maxRetained": await session.maxRetained,
                "firstAudioMs": firstScheduled().map { milliseconds(started.duration(to: $0)) } ?? -1,
                "totalMs": milliseconds(started.duration(to: .now)),
                "peakFootprintMB": peak.stop(),
                "oversizeSplits": events.count(where: { if case .oversizeSplit = $0 { true } else { false } }),
            ])
        }
        await engine.stop()
    }

    static func milliseconds(_ duration: Duration) -> Int {
        Int(duration / .milliseconds(1))
    }
}

/// Samples the process footprint every 50 ms and keeps the peak (MB).
final class PeakMemory: Sendable {
    private let task: Task<Void, Never>

    init() {
        let shared = SharedPeak()
        self.shared = shared
        task = Task.detached {
            while !Task.isCancelled {
                shared.update(PeakMemory.footprintMB())
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private let shared: SharedPeak

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
}

final class SharedPeak: Sendable {
    private let peak = Mutex(0.0)
    func update(_ value: Double) { peak.withLock { $0 = max($0, value) } }
    var value: Double { peak.withLock { $0 } }
}
