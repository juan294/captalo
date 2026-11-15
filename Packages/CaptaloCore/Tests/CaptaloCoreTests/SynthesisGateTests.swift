import Foundation
import Synchronization
import Testing
@testable import CaptaloCore

/// Synthesizes at once until call `holdFrom`; later calls wait for
/// `releaseAll()` and ignore cancellation (the worst case for an engine).
/// Tracks calls and concurrency; `arrival(_:)` is a deterministic barrier.
final class HoldingSynthesizer: Synthesizer, Sendable {
    private struct State {
        var calls: [String] = []
        var inFlight = 0
        var maxInFlight = 0
        var released = false
        var held: [CheckedContinuation<Void, Never>] = []
        var arrivals: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    }

    let holdFrom: Int
    let rate = 100
    private let state = Mutex(State())

    init(holdFrom: Int = 0) { self.holdFrom = holdFrom }

    func synthesize(_ text: String, voice: String, speed: Float) async throws -> SynthesizedAudio {
        let (index, arrived) = state.withLock { s -> (Int, [CheckedContinuation<Void, Never>]) in
            s.calls.append(text)
            s.inFlight += 1
            s.maxInFlight = max(s.maxInFlight, s.inFlight)
            let count = s.calls.count
            let arrived = s.arrivals.filter { $0.count <= count }.map(\.continuation)
            s.arrivals.removeAll { $0.count <= count }
            return (count - 1, arrived)
        }
        arrived.forEach { $0.resume() }
        if index >= holdFrom {
            await withCheckedContinuation { continuation in
                let go = state.withLock { s -> Bool in
                    if s.released { return true }
                    s.held.append(continuation)
                    return false
                }
                if go { continuation.resume() }
            }
        }
        state.withLock { $0.inFlight -= 1 }
        return SynthesizedAudio(samples: Array(repeating: 0.1, count: rate), sampleRate: rate)
    }

    /// Returns once call `index` (zero-based) has started.
    func arrival(_ index: Int) async {
        await withCheckedContinuation { continuation in
            let now = state.withLock { s -> Bool in
                if s.calls.count > index { return true }
                s.arrivals.append((index + 1, continuation))
                return false
            }
            if now { continuation.resume() }
        }
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
}

/// Waits until cancelled (Task.sleep throws on cancellation), as FluidAudio does at its checkpoints.
final class CancellableSynthesizer: Synthesizer {
    let started = Mutex(0)

    func synthesize(_ text: String, voice: String, speed: Float) async throws -> SynthesizedAudio {
        started.withLock { $0 += 1 }
        try await Task.sleep(for: .seconds(60))
        return SynthesizedAudio(samples: [0], sampleRate: 100)
    }
}

/// Names in the order they entered the gate.
final class EntryOrder: Sendable {
    let names = Mutex<[String]>([])
    func append(_ name: String) { names.withLock { $0.append(name) } }
    var list: [String] { names.withLock { $0 } }
}

@Suite struct SynthesisGateTests {
    /// Enters `gate` and records `name` once inside.
    func enter(_ gate: SynthesisGate, _ name: String, _ order: EntryOrder) -> Task<Bool, Never> {
        Task {
            do {
                try await gate.enter()
            } catch {
                return false
            }
            order.append(name)
            return true
        }
    }

    func waiters(_ gate: SynthesisGate, _ count: Int) async {
        await eventually { gate.waiting == count }
    }

    @Test func oneHolderAtATimeInArrivalOrder() async {
        let gate = SynthesisGate()
        let order = EntryOrder()
        try? await gate.enter()
        let a = enter(gate, "a", order)
        await waiters(gate, 1)
        let b = enter(gate, "b", order)
        await waiters(gate, 2)
        #expect(order.list.isEmpty)
        gate.leave()
        #expect(await a.value)
        #expect(order.list == ["a"])
        gate.leave()
        #expect(await b.value)
        #expect(order.list == ["a", "b"])
        gate.leave()
        #expect(gate.waiting == 0)
    }

    @Test func cancelledWaiterIsDiscardedBeforeEntry() async {
        let gate = SynthesisGate()
        let order = EntryOrder()
        try? await gate.enter()
        let stale = enter(gate, "stale", order)
        await waiters(gate, 1)
        let current = enter(gate, "current", order)
        await waiters(gate, 2)
        stale.cancel()
        #expect(await stale.value == false)
        #expect(gate.waiting == 1)
        gate.leave()
        #expect(await current.value)
        #expect(order.list == ["current"])
        gate.leave()
    }

    @Test func callerCancelledBeforeArrivalNeverEnters() async {
        let gate = SynthesisGate()
        let order = EntryOrder()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do { try await gate.enter() } catch { return false }
            order.append("entered")
            return true
        }
        #expect(await task.value == false)
        // The gate stayed free.
        try? await gate.enter()
        gate.leave()
        #expect(order.list.isEmpty)
    }

    @Test func uncancellableEntryWaitsForTheActiveCall() async {
        let gate = SynthesisGate()
        try? await gate.enter() // the active engine call
        let ended = Mutex(false)
        let shutdown = Task {
            await gate.enterUncancellable()
            ended.withLock { $0 = true }
            gate.leave()
        }
        await waiters(gate, 1)
        shutdown.cancel()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(!ended.withLock { $0 })
        gate.leave()
        await shutdown.value
        #expect(ended.withLock { $0 })
    }

    /// VAL-04: stop or replace cancels the reading's pipeline, so its waiting
    /// or in-flight synthesis ends without waiting for the engine, and the
    /// reading ends stopped at once.
    @Test func stopCancelsTheInFlightSynthesis() async {
        let synth = CancellableSynthesizer()
        let sink = FakeSink(autoplay: true)
        let reading = ReadingSession(units: sentences(3), synthesizer: synth, sink: sink, voice: "af_heart", speed: 1)
        await reading.start()
        await eventually { synth.started.withLock { $0 } == 1 }
        await reading.stop()
        let outcome = Mutex<ReadingOutcome?>(nil)
        Task { let value = await reading.outcome(); outcome.withLock { $0 = value } }
        await eventually { outcome.withLock { $0 } != nil }
        let ended = outcome.withLock { $0 }
        #expect(ended == .stopped)
        #expect(synth.started.withLock { $0 } == 1)
        #expect(sink.scheduledSamples.withLock { $0 }.isEmpty)
    }
}
