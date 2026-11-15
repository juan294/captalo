import CaptaloCore
import Foundation

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

    /// Installs from the app bundle (or repairs), then validates.
    public static func install(store: ModelStore, manifest: ModelManifest, bundleModels: URL) -> VoiceInstallState {
        do {
            try store.activate(from: bundleModels, manifest: manifest)
            return .ready
        } catch let error as StoreError {
            switch error {
            case .bundleInvalid: return .bundleInvalid
            case let .installFailed(need): return .installFailed(needBytes: need)
            case .damagedButLeased: return .damaged
            case .activationFailed: return .failed
            }
        } catch {
            return .failed
        }
    }
}
