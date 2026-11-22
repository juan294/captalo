import Foundation
import Synchronization

/// A committed reading. `start()` must return promptly; playback continues
/// on its own until `stop()`.
public protocol PlaybackSession: Sendable {
    func start() async
    func stop() async
}

/// Owns at most one pending input and one playing session (plan phase 2,
/// review R3 and V2-3). A new press supersedes only the pending input; the
/// session changes only when an input resolves.
public actor RequestCoordinator {
    public enum Resolution: Equatable, Sendable {
        /// The input was superseded; its outcome had no effect.
        case dropped
        case promoted(SessionToken)
        case stopped
        case unchanged
    }

    /// Builds a session for promoted text. `finished` reports the natural end
    /// of playback; it returns false (and does nothing) for a stale session.
    public typealias SessionFactory = @Sendable (
        _ token: SessionToken, _ content: ReadingContent, _ finished: @escaping @Sendable () async -> Bool
    ) -> any PlaybackSession

    private struct Playing {
        let token: SessionToken
        let inputGeneration: UInt64
        let identity: ReadingIdentity
        let handle: any PlaybackSession
    }

    private let makeSession: SessionFactory
    /// The newest reserved press. Reserved synchronously when a shortcut
    /// fires, so the order of presses is the order of reservations.
    private let presses = Mutex((latest: UInt64(0), lastStop: UInt64(0)))
    private var lastStopGeneration: UInt64 { presses.withLock { $0.lastStop } }
    private var sessionGeneration: UInt64 = 0
    /// Owned input tasks by generation; the current generation's task is the pending input.
    private var inFlight: [UInt64: Task<Void, Never>] = [:]
    private var playing: Playing?
    private var isShutDown = false

    public init(makeSession: @escaping SessionFactory) {
        self.makeSession = makeSession
    }

    public var currentSession: SessionToken? { playing?.token }

    public func isCurrent(_ token: InputToken) -> Bool {
        !isShutDown && token.inputGeneration == presses.withLock { $0.latest }
    }

    public func isCurrent(_ token: SessionToken) -> Bool {
        playing?.token == token
    }

    /// Takes the next place in press order. Call it synchronously when the
    /// shortcut fires, before any source lookup: it supersedes the pending
    /// input at once (`isCurrent` turns false for it).
    public nonisolated func reservePress() -> PressTicket {
        presses.withLock {
            $0.latest += 1
            return PressTicket(inputGeneration: $0.latest)
        }
    }

    /// A Stop supersedes capture at the key press, even if actor work runs later.
    public nonisolated func reserveStop() -> PressTicket {
        presses.withLock {
            $0.latest += 1
            $0.lastStop = $0.latest
            return PressTicket(inputGeneration: $0.latest)
        }
    }

    /// Samples share the current press order without superseding pending capture.
    public nonisolated func sampleTicket() -> PressTicket {
        PressTicket(inputGeneration: presses.withLock { $0.latest })
    }

    /// Starts a new pending input and cancels the older one. Never touches the session.
    public func beginInput(kind: InputKind, source: InputSource) -> InputToken {
        begin(reservePress(), kind: kind, source: source)
    }

    private func cancelInputs(before ticket: PressTicket) {
        for (generation, task) in inFlight where generation < ticket.inputGeneration { task.cancel() }
    }

    private func begin(_ ticket: PressTicket, kind: InputKind, source: InputSource) -> InputToken {
        cancelInputs(before: ticket)
        return InputToken(inputGeneration: ticket.inputGeneration, kind: kind, source: source, startedAt: .now)
    }

    /// Begins the reserved press and runs `capture` in an owned task, then
    /// resolves it. Returns nil, and never runs `capture`, when a newer press
    /// was reserved meanwhile (or after quit): a late source lookup does no
    /// Copy, speech or overlay work.
    @discardableResult
    public func submit(
        _ ticket: PressTicket,
        kind: InputKind,
        source: InputSource,
        capture: @escaping @Sendable (InputToken) async -> CaptureOutcome
    ) -> InputToken? {
        guard !isShutDown, ticket.inputGeneration == presses.withLock({ $0.latest }) else { return nil }
        let token = begin(ticket, kind: kind, source: source)
        let task = Task { [weak self] in
            let outcome = await capture(token)
            await self?.finish(token, outcome)
        }
        inFlight[token.inputGeneration] = task
        return token
    }

    private func finish(_ token: InputToken, _ outcome: CaptureOutcome) async {
        PrivacyLog.record(.capture(
            kind: token.kind, outcome: .init(outcome), layer: outcome.capturedLayer,
            characters: outcome.capturedLength, elapsed: token.startedAt.duration(to: .now)
        ))
        await resolve(token, outcome)
        // Removed only after resolve returns, so shutdown waits for a promote in progress.
        inFlight[token.inputGeneration] = nil
    }

    /// Routes a resolved input. Superseded tokens are dropped.
    @discardableResult
    public func resolve(_ token: InputToken, _ outcome: CaptureOutcome) async -> Resolution {
        guard isCurrent(token) else { return .dropped }
        switch (token.kind, outcome) {
        case let (.selection, .text(text, _)):
            let identity = ReadingIdentity(capturedText: text)
            if let playing, playing.inputGeneration >= lastStopGeneration, playing.identity == identity {
                await stopPlaying()
                return .stopped
            }
            return await promote(.text(text), identity: identity, generation: token.inputGeneration)
        case (.selection, .nothingSelected):
            guard playing != nil else { return .unchanged }
            await stopPlaying()
            return .stopped
        case let (.region, .document(blocks)):
            // Only a successful recognition replaces the reading; a region press never stops one.
            let content = ReadingContent.document(blocks)
            return await promote(content, identity: ReadingIdentity(capturedText: content.plainText), generation: token.inputGeneration)
        default:
            return .unchanged
        }
    }

    /// A playback callback. Returns false (and does nothing) for older sessions.
    @discardableResult
    public func sessionFinished(_ token: SessionToken) -> Bool {
        guard playing?.token == token else { return false }
        playing = nil
        return true
    }

    /// Starts a reading of app-provided text (the voice sample). It is not a
    /// capture: it replaces any reading, is never a stop gesture, and leaves
    /// a pending input untouched.
    public func play(text: String, ticket: PressTicket? = nil) async {
        let ticket = ticket ?? sampleTicket()
        guard !isShutDown, ticket.inputGeneration >= lastStopGeneration else { return }
        _ = await promote(.text(text), identity: ReadingIdentity(capturedText: text), generation: ticket.inputGeneration)
    }

    /// Cancel older capture without waiting for clipboard or OCR cleanup. A
    /// later press can already be playing when this stop reaches the actor.
    public func stopReading(_ ticket: PressTicket) async {
        cancelInputs(before: ticket)
        if let playing, playing.inputGeneration < ticket.inputGeneration {
            await stopPlaying()
        }
    }

    /// Voice repair stops only playback; its pending input is untouched.
    public func stopSession() async {
        await stopPlaying()
    }

    /// Quit: cancel the pending input, let every open cleanup finish, stop the session.
    public func shutdown() async {
        isShutDown = true
        inFlight.values.forEach { $0.cancel() }
        await waitForIdle()
        await stopPlaying()
    }

    /// Waits for every in-flight input task. Used by tests and quit.
    public func waitForIdle() async {
        while let next = inFlight.first {
            await next.value.value
            inFlight[next.key] = nil
        }
    }

    private func promote(_ content: ReadingContent, identity: ReadingIdentity, generation: UInt64) async -> Resolution {
        sessionGeneration += 1
        let token = SessionToken(sessionGeneration: sessionGeneration)
        let handle = makeSession(token, content) { [weak self] in await self?.sessionFinished(token) ?? false }
        let new = Playing(token: token, inputGeneration: generation, identity: identity, handle: handle)
        let old = playing
        playing = new
        await old?.handle.stop()
        // A newer resolution may have replaced this session while the old one
        // stopped: never start a handle that is no longer current.
        guard playing?.token == token else { return .promoted(token) }
        await new.handle.start()
        if playing?.token != token { await new.handle.stop() }
        return .promoted(token)
    }

    private func stopPlaying() async {
        guard let old = playing else { return }
        playing = nil
        await old.handle.stop()
    }
}
