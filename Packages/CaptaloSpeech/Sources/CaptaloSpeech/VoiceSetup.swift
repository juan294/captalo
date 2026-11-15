import CaptaloCore
import Foundation
import Synchronization

extension VoiceInstallState: Error {}

extension StoreError {
    /// The settings-window state for an activation failure.
    var installState: VoiceInstallState {
        switch self {
        case .bundleInvalid: .bundleInvalid
        case let .installFailed(need): .installFailed(needBytes: need)
        case .damagedButLeased: .damaged
        case .activationFailed: .failed
        }
    }
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
            do {
                directory = try store.activate(from: bundleModels, manifest: manifest)
            } catch let error as StoreError {
                return .state(error.installState)
            } catch {
                return .state(.failed)
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
