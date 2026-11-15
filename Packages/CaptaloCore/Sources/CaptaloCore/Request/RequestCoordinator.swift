import Foundation

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
        _ token: SessionToken, _ text: String, _ finished: @escaping @Sendable () async -> Bool
    ) -> any PlaybackSession

    private struct Playing {
        let token: SessionToken
        let identity: ReadingIdentity
        let handle: any PlaybackSession
    }

    private let makeSession: SessionFactory
    private var inputGeneration: UInt64 = 0
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
        !isShutDown && token.inputGeneration == inputGeneration
    }

    public func isCurrent(_ token: SessionToken) -> Bool {
        playing?.token == token
    }

    /// Starts a new pending input and cancels the older one. Never touches the session.
    public func beginInput(kind: InputKind, source: InputSource) -> InputToken {
        inFlight[inputGeneration]?.cancel()
        inputGeneration += 1
        return InputToken(inputGeneration: inputGeneration, kind: kind, source: source, startedAt: .now)
    }

    /// Begins an input and runs `capture` in an owned task, then resolves it.
    @discardableResult
    public func submit(
        kind: InputKind,
        source: InputSource,
        capture: @escaping @Sendable (InputToken) async -> CaptureOutcome
    ) -> InputToken {
        let token = beginInput(kind: kind, source: source)
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
            if let playing, playing.identity == identity {
                await stopPlaying()
                return .stopped
            }
            return await promote(text, identity: identity)
        case (.selection, .nothingSelected):
            guard playing != nil else { return .unchanged }
            await stopPlaying()
            return .stopped
        case let (.region, .text(text, _)):
            return await promote(text, identity: ReadingIdentity(capturedText: text))
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
    public func play(text: String) async {
        _ = await promote(text, identity: ReadingIdentity(capturedText: text))
    }

    /// An explicit stop (inherited menu control). Pending input is untouched.
    public func stopSession() async {
        await stopPlaying()
    }

    /// Quit: cancel the pending input, let every open cleanup finish, stop the session.
    public func shutdown() async {
        isShutDown = true
        inFlight[inputGeneration]?.cancel()
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

    private func promote(_ text: String, identity: ReadingIdentity) async -> Resolution {
        sessionGeneration += 1
        let token = SessionToken(sessionGeneration: sessionGeneration)
        let handle = makeSession(token, text) { [weak self] in await self?.sessionFinished(token) ?? false }
        let new = Playing(token: token, identity: identity, handle: handle)
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
