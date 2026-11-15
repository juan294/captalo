import CaptaloCore
import FluidAudio
import Foundation

/// The engine calls `KokoroSynthesizer` makes: `KokoroAneManager` in
/// production, an in-memory engine in tests.
protocol KokoroEngine: Sendable {
    func synthesizeAudio(_ text: String, voice: String, speed: Float) async throws -> SynthesizedAudio
    func cleanup() async
}

extension KokoroAneManager: KokoroEngine {
    func synthesizeAudio(_ text: String, voice: String, speed: Float) async throws -> SynthesizedAudio {
        let result = try await synthesizeDetailed(text: text, voice: voice, speed: speed)
        return SynthesizedAudio(
            samples: result.samples, sampleRate: result.sampleRate,
            normalizedText: result.normalizedText, phonemeCount: result.phonemes.unicodeScalars.count
        )
    }
}

/// The production Kokoro engine (plan phase 3, unit 3B). Before any FluidAudio
/// call it points the model registry at a blocked endpoint, validates the
/// store, takes the store's consumer lock and a lease, and only then builds
/// `KokoroAneManager` on the validated directory.
///
/// Every reading shares this synthesizer. FluidAudio does not serialize whole
/// calls, so a `SynthesisGate` admits one engine call at a time; a stopped or
/// replaced reading's waiting call never enters, and `stop()` waits for the
/// active call before it ends the engine and its lease (VAL-04).
public actor KokoroSynthesizer: Synthesizer {
    /// Production registry: a closed loopback port, so a fetch can never succeed.
    public static let blockedRegistry = "http://127.0.0.1:9"
    public static let sampleRate = 24_000

    public enum StartError: Error, Equatable {
        case notStarted
        case engineFailed
    }

    typealias EngineFactory = @Sendable (_ directory: URL, _ manifest: ModelManifest) async throws -> any KokoroEngine

    private let store: ModelStore
    private let manifest: ModelManifest
    private let registry: String
    private let makeEngine: EngineFactory
    private var lease: LeaseRegistry.Lease?
    private var engine: (any KokoroEngine)?
    private var starting: Task<Void, Error>?
    private let gate = SynthesisGate()

    public init(store: ModelStore, manifest: ModelManifest, registry: String = KokoroSynthesizer.blockedRegistry) {
        self.init(store: store, manifest: manifest, registry: registry, makeEngine: Self.kokoroEngine)
    }

    init(store: ModelStore, manifest: ModelManifest, registry: String, makeEngine: @escaping EngineFactory) {
        self.store = store
        self.manifest = manifest
        self.registry = registry
        self.makeEngine = makeEngine
    }

    private static func kokoroEngine(_ directory: URL, _ manifest: ModelManifest) async throws -> any KokoroEngine {
        let manager = KokoroAneManager(defaultVoice: manifest.voices.first, directory: directory)
        try await manager.initialize(preloadVoices: Set(manifest.voices))
        return manager
    }

    /// Builds the engine on `directory`, which the caller (`VoiceSetup`)
    /// validated while holding the store's consumer lock. Concurrent calls
    /// share one start.
    public func start(validatedDirectory directory: URL) async throws {
        if engine != nil { return }
        if let starting { return try await starting.value }
        let task = Task { try await self.build(directory) }
        starting = task
        defer { starting = nil }
        try await task.value
    }

    private func build(_ directory: URL) async throws {
        // Before any FluidAudio call: the registry points at a closed port.
        ModelRegistry.baseURL = registry
        // Source audit at the pin: G2P failures log single words at warning
        // level. Only errors (which carry no text) reach the log, never the console.
        AppLogger.minimumLevel = .error
        AppLogger.mirrorsToConsole = false
        let lease = store.leases.lease(directory)
        let engine: any KokoroEngine
        do {
            engine = try await makeEngine(directory, manifest)
        } catch {
            lease.release()
            throw StartError.engineFailed
        }
        self.lease = lease
        self.engine = engine
    }

    /// Ends the engine and its lease (before a repair of a damaged store),
    /// after the active engine call has returned.
    public func stop() async {
        _ = try? await starting?.value
        await gate.enterUncancellable()
        defer { gate.leave() }
        await engine?.cleanup()
        engine = nil
        lease?.release()
        lease = nil
    }

    public func synthesize(_ text: String, voice: String, speed: Float) async throws -> SynthesizedAudio {
        try await gate.enter()
        defer { gate.leave() }
        guard let engine else { throw StartError.notStarted }
        return try await engine.synthesizeAudio(text, voice: voice, speed: speed)
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
