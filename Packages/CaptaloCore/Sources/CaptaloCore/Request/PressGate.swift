/// The gate both shortcuts share (plan phase 4), without AppKit.
public enum PressGate {
    public enum Decision: Equatable, Sendable {
        /// The voice is still being prepared at launch: the press is ignored (not a failure).
        case ignore
        /// The voice or the Accessibility permission is missing: show setup.
        case requireSetup
        case proceed
    }

    /// `refreshTrust` reads the current Accessibility trust and updates the
    /// cache. A cached false is refreshed before deciding, so the first press
    /// after a grant in System Settings reads (VAL-10).
    public static func decide(
        voice: VoiceInstallState, cachedTrust: Bool, refreshTrust: () -> Bool
    ) -> Decision {
        if voice == .checking { return .ignore }
        let canSpeak = voice.canSpeak
        if canSpeak, cachedTrust { return .proceed }
        // A failing press always refreshes the permission row.
        let trusted = refreshTrust()
        return canSpeak && trusted ? .proceed : .requireSetup
    }
}
