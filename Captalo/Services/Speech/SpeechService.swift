import CaptaloCore
import CaptaloSpeech
import Foundation
import Synchronization

/// The app's speech: the bundled voice store, the Kokoro engine and one
/// AVAudioEngine sink shared by every reading (plan phase 3).
nonisolated final class SpeechService: Sendable {
    typealias PrepareResult = VoiceSetup.Result

    let store: ModelStore
    let manifest: ModelManifest?
    private let bundleModels: URL?
    private let setup: VoiceSetup?
    private let sink = AVAudioSink()
    private let current = CurrentReading()

    init(bundle: Bundle = .main) {
        let store = ModelStore()
        self.store = store
        manifest = bundle.url(forResource: "Models.manifest", withExtension: "json").flatMap { try? ModelManifest.load(from: $0) }
        bundleModels = bundle.resourceURL?.appendingPathComponent("Models", isDirectory: true)
        setup = manifest.map { VoiceSetup(store: store, manifest: $0) }
        let current = self.current
        sink.setConfigurationChangeHandler {
            guard let reading = current.value else { return }
            Task { await reading.deviceChanged() }
        }
    }

    var voices: [String] { manifest?.voices ?? [] }

    /// Takes the store's consumer lock, installs or repairs from the app bundle, starts the engine.
    func prepare() async -> PrepareResult {
        guard let setup, let bundleModels else { return .state(.bundleInvalid) }
        return await setup.prepare(bundleModels: bundleModels)
    }

    /// "Reinstall voice": the caller has stopped the current reading; end the
    /// engine and its lease, then repair from the bundle.
    func reinstall() async -> PrepareResult {
        guard let setup, let bundleModels else { return .state(.bundleInvalid) }
        return await setup.reinstall(bundleModels: bundleModels)
    }

    /// True while a reading owns the sink.
    var isReading: Bool { current.value != nil }

    /// A committed reading of captured text, with the voice and speed of this moment.
    func makeSession(
        content: ReadingContent, voice: String, speed: Float,
        finished: @escaping @Sendable () async -> Bool,
        voiceError: @escaping @Sendable () -> Void
    ) -> PlaybackSession {
        guard let synthesizer = setup?.synthesizer else { return EmptySession(finished: finished) }
        let log = ReadingLogRecorder()
        let reading = ReadingSession(
            units: { TextPreparer.units(for: content) },
            synthesizer: synthesizer, sink: sink, voice: voice, speed: speed,
            onEvent: log.observe
        )
        return ReadingPlaybackSession(reading: reading, log: log, current: current, finished: finished, voiceError: voiceError)
    }

}

/// The reading that currently owns the sink (for device-change replay).
nonisolated final class CurrentReading: Sendable {
    private let slot = Mutex<ReadingSession?>(nil)

    var value: ReadingSession? { slot.withLock { $0 } }

    func set(_ reading: ReadingSession) { slot.withLock { $0 = reading } }

    func clear(_ reading: ReadingSession) {
        slot.withLock { if $0 === reading { $0 = nil } }
    }
}

/// Adapts a `ReadingSession` to the request coordinator's session handle.
nonisolated final class ReadingPlaybackSession: PlaybackSession {
    private let reading: ReadingSession
    private let log: ReadingLogRecorder
    private let current: CurrentReading
    private let finished: @Sendable () async -> Bool
    private let voiceError: @Sendable () -> Void

    init(reading: ReadingSession, log: ReadingLogRecorder, current: CurrentReading,
         finished: @escaping @Sendable () async -> Bool, voiceError: @escaping @Sendable () -> Void) {
        self.reading = reading
        self.log = log
        self.current = current
        self.finished = finished
        self.voiceError = voiceError
    }

    func start() async {
        current.set(reading)
        await reading.start()
        let reading = self.reading
        let current = self.current
        let finished = self.finished
        let voiceError = self.voiceError
        let log = self.log
        Task {
            let outcome = await reading.outcome()
            PrivacyLog.record(log.event(outcome: outcome))
            current.clear(reading)
            guard outcome != .stopped else { return }
            if outcome == .voiceError { voiceError() }
            _ = await finished()
        }
    }

    func stop() async {
        await reading.stop()
        current.clear(reading)
    }
}

/// A session with nothing to say (no voice bundle in this build).
nonisolated struct EmptySession: PlaybackSession {
    let finished: @Sendable () async -> Bool

    func start() async {
        let finished = finished
        Task { _ = await finished() }
    }

    func stop() async {}
}
