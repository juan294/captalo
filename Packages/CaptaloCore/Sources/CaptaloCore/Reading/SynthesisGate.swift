import Synchronization

/// One engine call at a time across every reading that shares a synthesizer
/// (VAL-04). Callers enter in arrival order. A caller cancelled while it
/// waits (a stopped or replaced reading) is discarded and never enters, and
/// an engine shutdown enters only after the active call has left.
public final class SynthesisGate: Sendable {
    private struct Waiter {
        let ticket: UInt64
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var busy = false
        var nextTicket: UInt64 = 0
        var waiters: [Waiter] = []
    }

    private let state = Mutex(State())

    public init() {}

    /// Waits for the engine. Throws `CancellationError`, without entering,
    /// when the caller is cancelled before its turn. Call `leave()` after.
    public func enter() async throws {
        try await wait(cancellable: true)
    }

    /// Waits for the engine whatever the caller's cancellation (engine
    /// shutdown before a repair). Call `leave()` after.
    public func enterUncancellable() async {
        try? await wait(cancellable: false)
    }

    /// Hands the engine to the next waiter, or frees it.
    public func leave() {
        let next = state.withLock { state -> CheckedContinuation<Void, any Error>? in
            guard !state.waiters.isEmpty else {
                state.busy = false
                return nil
            }
            return state.waiters.removeFirst().continuation
        }
        next?.resume()
    }

    /// Callers waiting for their turn (tests).
    var waiting: Int { state.withLock { $0.waiters.count } }

    private func wait(cancellable: Bool) async throws {
        let ticket = state.withLock { state -> UInt64 in
            state.nextTicket += 1
            return state.nextTicket
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let admitted = state.withLock { state -> Bool? in
                    if cancellable, Task.isCancelled { return nil }
                    if !state.busy {
                        state.busy = true
                        return true
                    }
                    state.waiters.append(Waiter(ticket: ticket, continuation: continuation))
                    return false
                }
                switch admitted {
                case nil: continuation.resume(throwing: CancellationError())
                case true?: continuation.resume()
                case false?: break
                }
            }
        } onCancel: {
            guard cancellable else { return }
            let removed = state.withLock { state -> CheckedContinuation<Void, any Error>? in
                guard let index = state.waiters.firstIndex(where: { $0.ticket == ticket }) else { return nil }
                return state.waiters.remove(at: index).continuation
            }
            removed?.resume(throwing: CancellationError())
        }
        // Cancelled after being handed the engine: still never enter it.
        if cancellable, Task.isCancelled {
            leave()
            throw CancellationError()
        }
    }
}
