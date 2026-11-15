import CaptaloCore
import Foundation
import Synchronization
import Testing
@testable import CaptaloSpeech

/// A deterministic arrival barrier: `wait(for:)` returns once `arrive()` ran that many times.
final class Arrivals: Sendable {
    private let state = Mutex((count: 0, waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)]()))

    func arrive() {
        let ready = state.withLock { s -> [CheckedContinuation<Void, Never>] in
            s.count += 1
            let count = s.count
            defer { s.waiters.removeAll { $0.count <= count } }
            return s.waiters.filter { $0.count <= count }.map(\.continuation)
        }
        ready.forEach { $0.resume() }
    }

    func wait(for count: Int) async {
        await withCheckedContinuation { continuation in
            let now = state.withLock { s -> Bool in
                if s.count >= count { return true }
                s.waiters.append((count, continuation))
                return false
            }
            if now { continuation.resume() }
        }
    }
}

/// An engine whose calls block until `releaseAll()`, ignoring cancellation
/// (a CoreML prediction does not stop midway). It records concurrency, and
/// whether the store lease was still held when each call returned and when
/// cleanup ran.
final class BlockedEngine: KokoroEngine {
    private struct State {
        var calls: [String] = []
        var inFlight = 0
        var maxInFlight = 0
        var released = false
        var held: [CheckedContinuation<Void, Never>] = []
        var leaseHeldOnReturn: [Bool] = []
        var cleanups: [(inFlight: Int, leaseHeld: Bool)] = []
    }

    private let state = Mutex(State())
    let entered = Arrivals()
    let leaseHeld: @Sendable () -> Bool

    init(leaseHeld: @escaping @Sendable () -> Bool) { self.leaseHeld = leaseHeld }

    func synthesizeAudio(_ text: String, voice: String, speed: Float) async throws -> SynthesizedAudio {
        state.withLock { s in
            s.calls.append(text)
            s.inFlight += 1
            s.maxInFlight = max(s.maxInFlight, s.inFlight)
        }
        entered.arrive()
        await withCheckedContinuation { continuation in
            let go = state.withLock { s -> Bool in
                if s.released { return true }
                s.held.append(continuation)
                return false
            }
            if go { continuation.resume() }
        }
        let held = leaseHeld()
        state.withLock { s in
            s.inFlight -= 1
            s.leaseHeldOnReturn.append(held)
        }
        return SynthesizedAudio(samples: Array(repeating: 0.1, count: 2_400), sampleRate: KokoroSynthesizer.sampleRate)
    }

    func cleanup() async {
        let held = leaseHeld()
        state.withLock { $0.cleanups.append(($0.inFlight, held)) }
    }

    func releaseAll() {
        let held = state.withLock { s -> [CheckedContinuation<Void, Never>] in
            s.released = true
            defer { s.held.removeAll() }
            return s.held
        }
        held.forEach { $0.resume() }
    }

    var calls: [String] { state.withLock { $0.calls } }
    var maxInFlight: Int { state.withLock { $0.maxInFlight } }
    var leaseHeldOnReturn: [Bool] { state.withLock { $0.leaseHeldOnReturn } }
    var cleanups: [(inFlight: Int, leaseHeld: Bool)] { state.withLock { $0.cleanups } }
}

/// Forwards to the shared synthesizer and marks each call's arrival.
final class ArrivingSynthesizer: Synthesizer {
    let inner: Synthesizer
    let arrived = Arrivals()

    init(_ inner: Synthesizer) { self.inner = inner }

    func synthesize(_ text: String, voice: String, speed: Float) async throws -> SynthesizedAudio {
        arrived.arrive()
        return try await inner.synthesize(text, voice: voice, speed: speed)
    }
}

/// Accepts every buffer and never plays it.
final class SilentSink: AudioSink {
    let stops = Mutex(0)
    func schedule(_ samples: [Float], sampleRate: Int, played: @escaping @Sendable () -> Void) -> Bool { true }
    func stop() { stops.withLock { $0 += 1 } }
}

@Suite(.serialized) struct SynthesisLifecycleTests {
    /// VAL-04: rapid replacements share one synthesizer whose first call is
    /// blocked. One engine call runs at a time, replaced readings never enter
    /// the engine, playback stop stays immediate, and a repair (engine stop)
    /// keeps the store lease until the blocked call has returned.
    @Test func replacedSessionsShareOneEngineCallAndRepairWaitsForIt() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let store = ModelStore(root: f.root)
        let directory = try store.activate(from: f.bundle, manifest: f.manifest)
        let leases = store.leases
        let engine = BlockedEngine { leases.isLeased(directory) }
        let synthesizer = KokoroSynthesizer(
            store: store, manifest: f.manifest, registry: KokoroSynthesizer.blockedRegistry) { _, _ in engine }
        try await synthesizer.start(validatedDirectory: directory)
        #expect(leases.isLeased(directory))

        let shared = ArrivingSynthesizer(synthesizer)
        let sink = SilentSink()
        var sessions: [ReadingSession] = []
        for index in 0..<6 {
            if let old = sessions.last { await old.stop() } // returns while the engine call is blocked
            let text = "Session \(index)."
            let session = ReadingSession(
                units: { AnyIterator(UnitChunker([Paragraph(sentences: [text])]).makeIterator()) },
                synthesizer: shared, sink: sink, voice: "af_heart", speed: 1)
            await session.start()
            await shared.arrived.wait(for: index + 1) // this reading's first call has been made
            if index == 0 { await engine.entered.wait(for: 1) } // and the first one is in the engine
            sessions.append(session)
        }
        #expect(sink.stops.withLock { $0 } == 5)

        // "Reinstall voice": the app stops the reading, then ends the engine and its lease.
        await sessions.last?.stop()
        let repair = Task { await synthesizer.stop() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(leases.isLeased(directory))
        engine.releaseAll()
        await repair.value

        #expect(engine.maxInFlight == 1)
        #expect(engine.calls == ["Session 0."]) // stale waiters never entered the engine
        #expect(engine.leaseHeldOnReturn == [true])
        let cleanups = engine.cleanups
        #expect(cleanups.count == 1)
        #expect(cleanups.first?.inFlight == 0)
        #expect(cleanups.first?.leaseHeld == true)
        #expect(!leases.isLeased(directory))
        for session in sessions { #expect(await session.outcome() == .stopped) }
    }
}
