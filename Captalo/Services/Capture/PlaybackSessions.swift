import CaptaloCore
import Foundation
import Synchronization

/// Phase 2 adapter from a committed reading to the inherited speech
/// controller. Phase 3 replaces it with `ReadingSession`.
nonisolated struct SpeechPlaybackSession: PlaybackSession {
    let token: SessionToken
    let text: String
    let speech: SpeechController
    let finished: @Sendable () async -> Bool
    let begin: @MainActor @Sendable (SpeechPlaybackSession) -> Void

    func start() async {
        await begin(self)
    }

    func stop() async {
        await speech.stop(session: token.sessionGeneration)
    }
}

#if DEBUG
/// Debug-only playback seam for the phase 2 matrix: a silent "reading" of a
/// fixed 30 s that logs its state transitions. Labelled as a seam in all evidence.
nonisolated final class SilentTimedSession: PlaybackSession, Sendable {
    static let length = Duration.seconds(30)

    /// Reports the end of the seam reading; returns false for a stale session.
    private let finished: @Sendable () async -> Bool
    private let timer = Mutex<Task<Void, Never>?>(nil)

    init(finished: @escaping @Sendable () async -> Bool) {
        self.finished = finished
    }

    func start() async {
        PrivacyLog.record(.seamSession(state: .started))
        let finished = finished
        let task = Task {
            try? await Task.sleep(for: Self.length)
            guard !Task.isCancelled else { return }
            if await finished() {
                PrivacyLog.record(.seamSession(state: .finished))
            }
        }
        timer.withLock { $0 = task }
    }

    func stop() async {
        let task = timer.withLock { current -> Task<Void, Never>? in
            defer { current = nil }
            return current
        }
        guard let task else { return }
        task.cancel()
        PrivacyLog.record(.seamSession(state: .stopped))
    }
}
#endif
