import CaptaloCore
import CaptaloSpeech
import Foundation
import Synchronization

/// The app's speech: the bundled voice store, the Kokoro engine and one
/// AVAudioEngine sink shared by every reading (plan phase 3).
nonisolated final class SpeechService: Sendable {
    enum PrepareResult: Equatable, Sendable {
        case state(VoiceInstallState)
        case secondInstance
    }

    let store: ModelStore
    let manifest: ModelManifest?
    private let bundleModels: URL?
    private let synthesizer: KokoroSynthesizer?
    private let sink = AVAudioSink()
    private let current = CurrentReading()

    init(bundle: Bundle = .main) {
        store = ModelStore()
        manifest = bundle.url(forResource: "Models.manifest", withExtension: "json").flatMap { try? ModelManifest.load(from: $0) }
        bundleModels = bundle.resourceURL?.appendingPathComponent("Models", isDirectory: true)
        let store = self.store
        synthesizer = manifest.map { KokoroSynthesizer(store: store, manifest: $0) }
        let current = self.current
        sink.setConfigurationChangeHandler {
            guard let reading = current.value else { return }
            Task { await reading.deviceChanged() }
        }
    }

    var voices: [String] { manifest?.voices ?? [] }

    /// Installs or repairs the store from the app bundle, then starts the engine.
    func prepare() async -> PrepareResult {
        guard let manifest, let bundleModels, let synthesizer else { return .state(.bundleInvalid) }
        let installed = VoiceLoader.install(store: store, manifest: manifest, bundleModels: bundleModels)
        guard installed == .ready else { return .state(installed) }
        do {
            try await synthesizer.start()
            return .state(.ready)
        } catch KokoroSynthesizer.StartError.secondInstance {
            return .secondInstance
        } catch let KokoroSynthesizer.StartError.voice(state) {
            return .state(state)
        } catch {
            return .state(.failed)
        }
    }

    /// "Reinstall voice": end the engine and its lease, then repair from the bundle.
    func reinstall() async -> PrepareResult {
        await synthesizer?.stop()
        return await prepare()
    }

    /// A committed reading of captured text, with the voice and speed of this moment.
    func makeSession(
        text: String, source: TextSource, voice: String, speed: Float,
        finished: @escaping @Sendable () async -> Bool,
        voiceError: @escaping @Sendable () -> Void
    ) -> PlaybackSession {
        guard let synthesizer else { return EmptySession(finished: finished) }
        let blocks = source == .selection ? Array(TextPreparer.blocks(fromSelection: text)) : [Block.paragraph(text)]
        let reading = ReadingSession(
            units: { AnyIterator(UnitChunker(TextPreparer.prepare(blocks, source: source)).makeIterator()) },
            synthesizer: synthesizer, sink: sink, voice: voice, speed: speed
        )
        return ReadingPlaybackSession(reading: reading, current: current, finished: finished, voiceError: voiceError)
    }

    /// True when cleanup leaves nothing to say (plan: empty result is silence).
    static func hasSpeakableText(_ text: String) -> Bool {
        TextPreparer.prepare(TextPreparer.blocks(fromSelection: text), source: .selection).first { _ in true } != nil
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
    private let current: CurrentReading
    private let finished: @Sendable () async -> Bool
    private let voiceError: @Sendable () -> Void

    init(reading: ReadingSession, current: CurrentReading, finished: @escaping @Sendable () async -> Bool,
         voiceError: @escaping @Sendable () -> Void) {
        self.reading = reading
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
        Task {
            let outcome = await reading.outcome()
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
