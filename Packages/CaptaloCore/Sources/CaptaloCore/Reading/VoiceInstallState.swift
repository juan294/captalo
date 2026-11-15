/// The bundled voice's install state (replaces the inherited download state).
public enum VoiceInstallState: Equatable, Sendable {
    case checking
    case ready
    /// "Voice files are damaged. Reinstall voice."
    case damaged
    /// The app bundle itself fails validation: "Reinstall Cáptalo".
    case bundleInvalid
    /// "Cáptalo needs N MB free to install its voice." with Retry.
    case installFailed(needBytes: Int64)
    case failed

    public var canSpeak: Bool { self == .ready }
}
