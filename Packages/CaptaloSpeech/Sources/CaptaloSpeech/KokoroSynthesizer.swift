import CaptaloCore
import FluidAudio
import Foundation

/// The production Kokoro engine (plan phase 3, unit 3B). Before any FluidAudio
/// call it points the model registry at a blocked endpoint, validates the
/// store, takes the store's consumer lock and a lease, and only then builds
/// `KokoroAneManager` on the validated directory.
public actor KokoroSynthesizer: Synthesizer {
    /// Production registry: a closed loopback port, so a fetch can never succeed.
    public static let blockedRegistry = "http://127.0.0.1:9"
    public static let sampleRate = 24_000

    public enum StartError: Error, Equatable {
        case secondInstance
        case voice(VoiceInstallState)
    }

    private let store: ModelStore
    private let manifest: ModelManifest
    private let registry: String
    private var consumerLock: FileLock?
    private var lease: LeaseRegistry.Lease?
    private var manager: KokoroAneManager?

    public init(store: ModelStore, manifest: ModelManifest, registry: String = KokoroSynthesizer.blockedRegistry) {
        self.store = store
        self.manifest = manifest
        self.registry = registry
    }

    /// Prepares the engine. Throws `.secondInstance` when another process holds the store.
    public func start() async throws {
        guard manager == nil else { return }
        // Source audit at the pin: G2P failures log single words at warning
        // level. Only errors (which carry no text) reach the log, never the console.
        AppLogger.minimumLevel = .error
        AppLogger.mirrorsToConsole = false
        ModelRegistry.baseURL = registry
        if consumerLock == nil {
            guard let lock = try FileLock.tryAcquire(store.consumerLockURL) else {
                PrivacyLog.record(.secondInstance)
                throw StartError.secondInstance
            }
            consumerLock = lock
        }
        var directory: URL?
        let state = VoiceLoader.prepare(store: store, manifest: manifest) { directory = $0 }
        guard state == .ready, let directory else { throw StartError.voice(state) }
        let lease = store.leases.lease(directory)
        let manager = KokoroAneManager(defaultVoice: manifest.voices.first, directory: directory)
        do {
            try await manager.initialize(preloadVoices: Set(manifest.voices))
        } catch {
            lease.release()
            throw StartError.voice(.failed)
        }
        self.lease = lease
        self.manager = manager
    }

    /// Ends the engine and its lease (before a repair of a damaged store).
    public func stop() async {
        await manager?.cleanup()
        manager = nil
        lease?.release()
        lease = nil
    }

    public func synthesize(_ text: String, voice: String, speed: Float) async throws -> SynthesizedAudio {
        if manager == nil { try await start() }
        guard let manager else { throw StartError.voice(.failed) }
        let result = try await manager.synthesizeDetailed(text: text, voice: voice, speed: speed)
        return SynthesizedAudio(
            samples: result.samples, sampleRate: result.sampleRate,
            normalizedText: result.normalizedText, phonemeCount: result.phonemes.unicodeScalars.count
        )
    }

    /// Development only (the probe's `fetch`): downloads every file the bundled
    /// voices need into `directory`, then synthesizes once per voice so that
    /// lazily converted voice packs and the lexicon are present.
    public static func fetchModels(into directory: URL, voices: [String]) async throws {
        let manager = KokoroAneManager(defaultVoice: voices.first, directory: directory)
        try await manager.initialize(preloadVoices: Set(voices))
        for voice in voices {
            _ = try await manager.synthesizeDetailed(text: "Ready. Version 3 at example.com.", voice: voice)
        }
        await manager.cleanup()
    }
}
