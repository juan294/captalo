/// The sections of the menu-bar panel (monochrome popover plan, phase 1).
public enum PanelTab: String, Sendable, CaseIterable {
    case read
    case voice
    case setup
}

/// The status pill in a pane's header.
public struct PanelPill: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Green: nothing to do.
        case positive
        /// Grey: the user has something to do.
        case neutral
        /// Grey: Cáptalo is working; nothing to do yet.
        case pending
    }

    public let text: String
    public let kind: Kind

    public init(text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }
}

/// Everything the panel shows, gathered by the app (or by a render fixture).
public struct PanelInput: Equatable, Sendable {
    public var environment: SetupEnvironment
    /// The bundled voice IDs, in display order.
    public var voices: [String]
    public var voice: String
    public var speed: Float
    /// The shortcuts as the recorder library describes them ("⌥P"); nil when unset.
    public var readShortcut: String?
    public var regionShortcut: String?
    /// Shown instead of the usual shortcut hint after a binding was rejected.
    public var shortcutRejection: String?
    public var regionNotice: String?
    /// "The last reading stopped because of a voice error." until the next reading.
    public var voiceError: String?
    public var loginItem: LoginItemRow
    /// Screen Recording was requested once; the row then offers "Quit and reopen".
    public var screenRecordingRequested: Bool

    public init(
        environment: SetupEnvironment, voices: [String], voice: String, speed: Float,
        readShortcut: String? = nil, regionShortcut: String? = nil, shortcutRejection: String? = nil,
        regionNotice: String? = nil, voiceError: String? = nil,
        loginItem: LoginItemRow = .make(status: .notRegistered), screenRecordingRequested: Bool = false
    ) {
        self.environment = environment
        self.voices = voices
        self.voice = voice
        self.speed = speed
        self.readShortcut = readShortcut
        self.regionShortcut = regionShortcut
        self.shortcutRejection = shortcutRejection
        self.regionNotice = regionNotice
        self.voiceError = voiceError
        self.loginItem = loginItem
        self.screenRecordingRequested = screenRecordingRequested
    }
}

/// A shortcut as keycaps; empty when no shortcut is recorded.
public struct ShortcutSlot: Equatable, Sendable {
    public let keycaps: [String]
}

public struct SpeedStep: Equatable, Sendable {
    public let label: String
    public let value: Float
    public let selected: Bool
}

public struct ReadPaneModel: Equatable, Sendable {
    public let selection: ShortcutSlot
    public let region: ShortcutSlot
    /// Always shown: the library does not report a shortcut another app took (notes D34).
    public let shortcutNotice: String
    public let voiceError: String?
    public let regionNotice: String?
    public let speedSteps: [SpeedStep]
    public let voiceName: String
}

public struct VoiceCard: Equatable, Sendable {
    public let id: String
    public let name: String
    public let inUse: Bool
}

public struct VoicePaneModel: Equatable, Sendable {
    /// Offered only when the voice is ready.
    public let voices: [VoiceCard]
    /// The install state's text; nil when the voice is ready.
    public let status: String?
    public let repairLabel: String?
    public let isChecking: Bool
}

public struct PermissionRow: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case allowed
        case action(label: String)
    }

    public let title: String
    public let detail: String
    public let state: State
    public let secondaryAction: String?
    /// A required permission is missing: the row is the panel's call to action.
    public let needsAttention: Bool
}

public struct SetupPaneModel: Equatable, Sendable {
    public let accessibility: PermissionRow
    public let screenRecording: PermissionRow
    public let loginItem: LoginItemRow
}

/// Every state and string of the panel. The views only draw it.
public struct PanelModel: Equatable, Sendable {
    /// The tabs with a dot on their rail item.
    public let attention: Set<PanelTab>
    /// The tab a newly opened panel shows.
    public let initialTab: PanelTab
    public let read: ReadPaneModel
    public let voice: VoicePaneModel
    public let setup: SetupPaneModel
    private let readPill: PanelPill
    private let voicePill: PanelPill
    private let setupPill: PanelPill

    public func pill(for tab: PanelTab) -> PanelPill {
        switch tab {
        case .read: readPill
        case .voice: voicePill
        case .setup: setupPill
        }
    }

    public static func make(_ input: PanelInput) -> PanelModel {
        let env = input.environment
        let setup = SetupState.evaluate(env)
        let missingTabs = setup.requiredMissing.map(tab(for:))
        var attention = Set(missingTabs)
        if input.voiceError != nil || input.regionNotice != nil { attention.insert(.read) }
        return PanelModel(
            attention: attention,
            initialTab: missingTabs.first ?? .read,
            read: readPane(input),
            voice: voicePane(input),
            setup: setupPane(input),
            readPill: setup.isReady ? PanelPill(text: "Ready", kind: .positive) : PanelPill(text: "Needs setup", kind: .neutral),
            voicePill: voicePill(env.voice),
            setupPill: env.accessibilityTrusted
                ? PanelPill(text: "All set", kind: .positive) : PanelPill(text: "1 step left", kind: .neutral)
        )
    }

    /// The tab that holds a setup item's control.
    static func tab(for item: SetupItem) -> PanelTab {
        switch item {
        case .voice: .voice
        case .accessibility, .screenRecording: .setup
        case .readShortcut, .regionShortcut: .read
        }
    }

    private static func voicePill(_ state: VoiceInstallState) -> PanelPill {
        switch state {
        case .ready: PanelPill(text: "Installed", kind: .positive)
        case .checking: PanelPill(text: "Preparing", kind: .pending)
        case .damaged, .bundleInvalid, .installFailed, .failed: PanelPill(text: "Needs attention", kind: .neutral)
        }
    }

    private static func readPane(_ input: PanelInput) -> ReadPaneModel {
        let notice = input.shortcutRejection ?? (input.environment.readShortcutSet
            ? "If this shortcut does nothing, another app may use it; choose another."
            : "Choose a shortcut to read the selected text: click the field, then hold ⌘, ⌥ or ⌃ and press a key.")
        let selected = ReadingPreferences.snap(input.speed)
        return ReadPaneModel(
            selection: ShortcutSlot(keycaps: ShortcutKeycaps.labels(description: input.readShortcut)),
            region: ShortcutSlot(keycaps: ShortcutKeycaps.labels(description: input.regionShortcut)),
            shortcutNotice: notice,
            voiceError: input.voiceError,
            regionNotice: input.regionNotice,
            speedSteps: ReadingPreferences.speedSteps.map {
                SpeedStep(label: ReadingPreferences.label(for: $0), value: $0, selected: $0 == selected)
            },
            voiceName: VoiceDisplay.name(for: input.voice)
        )
    }

    private static func voicePane(_ input: PanelInput) -> VoicePaneModel {
        let state = input.environment.voice
        guard state == .ready else {
            return VoicePaneModel(voices: [], status: state.statusText, repairLabel: state.repairLabel,
                                  isChecking: state == .checking)
        }
        let cards = input.voices.map { VoiceCard(id: $0, name: VoiceDisplay.name(for: $0), inUse: $0 == input.voice) }
        return VoicePaneModel(voices: cards, status: nil, repairLabel: nil, isChecking: false)
    }

    private static func setupPane(_ input: PanelInput) -> SetupPaneModel {
        let env = input.environment
        let accessibility = env.accessibilityTrusted
            ? PermissionRow(title: "Accessibility", detail: "Lets Cáptalo read the text you select",
                            state: .allowed, secondaryAction: nil, needsAttention: false)
            : PermissionRow(title: "Accessibility",
                            detail: "Cáptalo cannot read your selection until you allow this in System Settings.",
                            state: .action(label: "Open Accessibility Settings"), secondaryAction: nil, needsAttention: true)
        let optional = "Optional. Only for Read region"
        let screenRecording: PermissionRow = if env.screenRecordingGranted {
            PermissionRow(title: "Screen Recording", detail: optional, state: .allowed, secondaryAction: nil, needsAttention: false)
        } else if input.screenRecordingRequested {
            PermissionRow(title: "Screen Recording",
                          detail: "If you allowed it and region reading still does nothing, macOS needs Cáptalo to reopen.",
                          state: .action(label: "Allow"), secondaryAction: "Quit and reopen", needsAttention: false)
        } else {
            PermissionRow(title: "Screen Recording", detail: optional, state: .action(label: "Allow"),
                          secondaryAction: nil, needsAttention: false)
        }
        return SetupPaneModel(accessibility: accessibility, screenRecording: screenRecording, loginItem: input.loginItem)
    }
}
