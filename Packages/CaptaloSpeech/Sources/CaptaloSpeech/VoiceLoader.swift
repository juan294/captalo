import CaptaloCore
import Foundation
import Synchronization

/// Validates the active store before any engine is built (review R4, R6).
public enum VoiceLoader {
    /// Returns `.ready` only after `makeEngine` ran on a validated store directory.
    public static func prepare(
        store: ModelStore,
        manifest: ModelManifest,
        makeEngine: (URL) throws -> Void
    ) -> VoiceInstallState {
        switch store.currentDirectory(for: manifest) {
        case nil, .failure?:
            return .damaged
        case let .success(directory)?:
            do {
                try makeEngine(directory)
                return .ready
            } catch {
                return .failed
            }
        }
    }

    /// Installs from the app bundle (or repairs), returning the validated directory.
    static func install(store: ModelStore, manifest: ModelManifest, bundleModels: URL) -> Result<URL, VoiceSetupFailure> {
        do {
            return .success(try store.activate(from: bundleModels, manifest: manifest))
        } catch let error as StoreError {
            switch error {
            case .bundleInvalid: return .failure(VoiceSetupFailure(.bundleInvalid))
            case let .installFailed(need): return .failure(VoiceSetupFailure(.installFailed(needBytes: need)))
            case .damagedButLeased: return .failure(VoiceSetupFailure(.damaged))
            case .activationFailed: return .failure(VoiceSetupFailure(.failed))
            }
        } catch {
            return .failure(VoiceSetupFailure(.failed))
        }
    }
}

struct VoiceSetupFailure: Error {
    let state: VoiceInstallState
    init(_ state: VoiceInstallState) { self.state = state }
}

/// The one way a process prepares the voice (plan phase 3, "single consumer
/// per store"): take the store's consumer lock first, before any operation
/// that can repair, quarantine or reclaim store data; hold it for the
/// process lifetime; then install or validate, then start the engine.
public final class VoiceSetup: Sendable {
    public enum Result: Equatable, Sendable {
        case state(VoiceInstallState)
        /// Another process holds the store; this one must exit.
        case secondInstance
    }

    public let store: ModelStore
    public let manifest: ModelManifest
    public let synthesizer: KokoroSynthesizer
    private let consumer = Mutex<FileLock?>(nil)

    public init(store: ModelStore, manifest: ModelManifest, registry: String = KokoroSynthesizer.blockedRegistry) {
        self.store = store
        self.manifest = manifest
        synthesizer = KokoroSynthesizer(store: store, manifest: manifest, registry: registry)
    }

    /// - Parameter bundleModels: the app bundle's voice files to install or
    ///   repair from; nil uses the existing store only (a damaged store is refused).
    public func prepare(bundleModels: URL?) async -> Result {
        guard holdsConsumerLock() else {
            PrivacyLog.record(.secondInstance)
            return .secondInstance
        }
        let directory: URL
        if let bundleModels {
            switch VoiceLoader.install(store: store, manifest: manifest, bundleModels: bundleModels) {
            case let .success(url): directory = url
            case let .failure(failure): return .state(failure.state)
            }
        } else {
            guard case let .success(url)? = store.currentDirectory(for: manifest) else { return .state(.damaged) }
            directory = url
        }
        do {
            try await synthesizer.start(validatedDirectory: directory)
            return .state(.ready)
        } catch {
            return .state(.failed)
        }
    }

    /// "Reinstall voice": end the engine and its lease, then repair from the bundle.
    public func reinstall(bundleModels: URL) async -> Result {
        await synthesizer.stop()
        return await prepare(bundleModels: bundleModels)
    }

    private func holdsConsumerLock() -> Bool {
        consumer.withLock { lock in
            if lock != nil { return true }
            guard let acquired = try? FileLock.tryAcquire(store.consumerLockURL) else { return false }
            lock = acquired
            return true
        }
    }
}
