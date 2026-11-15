import Foundation
import Synchronization
import Testing
@testable import CaptaloCore

/// Waits until cancelled (Task.sleep throws on cancellation), as FluidAudio does at its checkpoints.
final class CancellableSynthesizer: Synthesizer {
    let started = Mutex(0)

    func synthesize(_ text: String, voice: String, speed: Float) async throws -> SynthesizedAudio {
        started.withLock { $0 += 1 }
        try await Task.sleep(for: .seconds(60))
        return SynthesizedAudio(samples: [0], sampleRate: 100)
    }
}

/// Runs its tasks' jobs only when the test calls `runAll()`, so a test can
/// act between a continuation's resumption and the moment its task runs.
final class ManualExecutor: TaskExecutor {
    private let jobs = Mutex<[UnownedJob]>([])

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        jobs.withLock { $0.append(job) }
    }

    func runAll() {
        while let job = jobs.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) {
            job.runSynchronously(on: asUnownedTaskExecutor())
        }
    }
}

@Suite struct SynthesisGateTests {
    /// Enters `gate` and records `name` once inside.
    func enter(_ gate: SynthesisGate, _ name: String, _ order: EventLog) -> Task<Bool, Never> {
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
        let order = EventLog()
        try? await gate.enter()
        let a = enter(gate, "a", order)
        await waiters(gate, 1)
        let b = enter(gate, "b", order)
        await waiters(gate, 2)
        #expect(order.events.isEmpty)
        gate.leave()
        #expect(await a.value)
        #expect(order.events == ["a"])
        gate.leave()
        #expect(await b.value)
        #expect(order.events == ["a", "b"])
        gate.leave()
        #expect(gate.waiting == 0)
    }

    @Test func cancelledWaiterIsDiscardedBeforeEntry() async {
        let gate = SynthesisGate()
        let order = EventLog()
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
        #expect(order.events == ["current"])
        gate.leave()
    }

    /// N2: `leave()` hands the engine to a waiter, which is cancelled before
    /// its task runs again. It must not enter, and must pass the engine on.
    @Test func waiterCancelledAfterHandOffPassesTheEngineOn() async {
        let gate = SynthesisGate()
        let order = EventLog()
        try? await gate.enter() // the active call
        let executor = ManualExecutor()
        let stale = Task(executorPreference: executor) { () -> Bool in
            do { try await gate.enter() } catch { return false }
            order.append("stale")
            return true
        }
        executor.runAll() // the stale reading's call starts waiting
        #expect(gate.waiting == 1)
        let next = enter(gate, "next", order)
        await waiters(gate, 2)
        gate.leave() // hands the engine to the stale waiter; its task has not run yet
        #expect(gate.waiting == 1)
        stale.cancel() // after the hand-off: no waiter left to remove
        executor.runAll()
        let staleEntered = await stale.value
        #expect(!staleEntered)
        if staleEntered { gate.leave() } // keep a failing run from hanging
        #expect(await next.value)
        #expect(order.events == ["next"])
        gate.leave()
    }

    @Test func callerCancelledBeforeArrivalNeverEnters() async {
        let gate = SynthesisGate()
        let order = EventLog()
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
        #expect(order.events.isEmpty)
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
