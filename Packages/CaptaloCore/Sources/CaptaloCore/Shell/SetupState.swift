/// Setup items in the settings panel (plan phase 4; owner decision 8).
public enum SetupItem: String, Sendable, CaseIterable {
    case voice
    case accessibility
    case readShortcut
    case screenRecording
    case regionShortcut
}

/// What setup evaluation needs, gathered by the app.
public struct SetupEnvironment: Equatable, Sendable {
    public var voice: VoiceInstallState
    public var accessibilityTrusted: Bool
    public var readShortcutSet: Bool
    public var screenRecordingGranted: Bool
    public var regionShortcutSet: Bool
    public var lastReadingError: Bool

    public init(voice: VoiceInstallState, accessibilityTrusted: Bool, readShortcutSet: Bool,
                screenRecordingGranted: Bool = false, regionShortcutSet: Bool = false, lastReadingError: Bool = false) {
        self.voice = voice
        self.accessibilityTrusted = accessibilityTrusted
        self.readShortcutSet = readShortcutSet
        self.screenRecordingGranted = screenRecordingGranted
        self.regionShortcutSet = regionShortcutSet
        self.lastReadingError = lastReadingError
    }
}

/// Required items (voice, Accessibility, read shortcut) decide readiness;
/// optional items (Screen Recording, region shortcut) never do.
public struct SetupState: Equatable, Sendable {
    public let requiredMissing: [SetupItem]
    public let optionalMissing: [SetupItem]
    /// "The last reading stopped because of a voice error." Shown, never blocking.
    public let showsVoiceError: Bool

    public var isReady: Bool { requiredMissing.isEmpty }

    public static func evaluate(_ env: SetupEnvironment) -> SetupState {
        var required: [SetupItem] = []
        // A voice still being checked at launch is pending, not missing.
        if env.voice != .ready, env.voice != .checking { required.append(.voice) }
        if !env.accessibilityTrusted { required.append(.accessibility) }
        if !env.readShortcutSet { required.append(.readShortcut) }
        var optional: [SetupItem] = []
        if !env.screenRecordingGranted { optional.append(.screenRecording) }
        if !env.regionShortcutSet { optional.append(.regionShortcut) }
        return SetupState(requiredMissing: required, optionalMissing: optional, showsVoiceError: env.lastReadingError)
    }

    /// A region press asks for Screen Recording only when it is missing; a
    /// selection-only user never sees the request (owner decision 8).
    public static func regionPressRequirement(_ env: SetupEnvironment) -> SetupItem? {
        env.screenRecordingGranted ? nil : .screenRecording
    }
}
