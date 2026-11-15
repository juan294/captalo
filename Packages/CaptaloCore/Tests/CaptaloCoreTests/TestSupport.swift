import Foundation
@testable import CaptaloCore

/// Thread-safe event log shared by fakes.
final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ event: String) {
        lock.lock(); storage.append(event); lock.unlock()
    }

    var events: [String] {
        lock.lock(); defer { lock.unlock() }; return storage
    }
}

/// An in-memory playback session that records start and stop.
struct RecordingSession: PlaybackSession {
    let name: String
    let log: EventLog

    func start() async { log.append("start \(name)") }
    func stop() async { log.append("stop \(name)") }
}

/// A session whose stop can block on a gate (models a slow stop).
struct GatedSession: PlaybackSession {
    let name: String
    let log: EventLog
    let stopGate: Gate?

    func start() async { log.append("start \(name)") }
    func stop() async {
        log.append("stop \(name)")
        await stopGate?.wait()
    }
}

/// Collects session finish callbacks so a test can fire them later.
final class FinisherBox: @unchecked Sendable {
    private let lock = NSLock()
    private var finishers: [@Sendable () async -> Bool] = []

    func append(_ finisher: @escaping @Sendable () async -> Bool) {
        lock.lock(); finishers.append(finisher); lock.unlock()
    }

    func call(_ index: Int) async -> Bool {
        let finisher = lock.withLock { finishers[index] }
        return await finisher()
    }
}

/// A gate a test opens to let a blocked task continue.
actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

let sourceA = InputSource(pid: 101, bundleID: "com.example.a", focusedElement: ElementRef("field-a"))
let sourceB = InputSource(pid: 202, bundleID: "com.example.b", focusedElement: ElementRef("field-b"))

func makeCoordinator(log: EventLog) -> RequestCoordinator {
    RequestCoordinator { token, content, _ in
        RecordingSession(name: "\(token.sessionGeneration):\(content.plainText)", log: log)
    }
}
