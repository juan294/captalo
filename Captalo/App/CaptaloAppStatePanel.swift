import CaptaloCore
import Foundation
import KeyboardShortcuts

/// This bundle's version and the commit `Scripts/write-build-info` recorded, read once.
private enum InstalledBuild {
    static let label = BuildLabel.make(
        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
        buildInfo: Bundle.main.url(forResource: "build-info", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
    )
}

extension CaptaloAppState {
    /// What the menu-bar panel shows now. `PanelModel.make` decides the rest.
    var panelInput: PanelInput {
        PanelInput(
            environment: setupEnvironment,
            voices: speechService.voices,
            voice: voice,
            speed: speed,
            readShortcut: KeyboardShortcuts.getShortcut(for: .readSelection)?.description,
            regionShortcut: KeyboardShortcuts.getShortcut(for: .readRegion)?.description,
            stopShortcut: KeyboardShortcuts.getShortcut(for: .stopReading)?.description,
            shortcutRejection: shortcutRejection,
            regionNotice: regionFailureNotice,
            voiceError: lastReadingError,
            loginItem: loginItem,
            screenRecordingRequest: screenRecordingRequest,
            build: InstalledBuild.label
        )
    }

    /// The panel's controls, bound to the existing state methods.
    var panelActions: PanelActions {
        PanelActions(
            setSpeed: { [self] in setSpeed($0) },
            setVoice: { [self] in setVoice($0) },
            playSample: { [self] in playSample($0) },
            repairVoice: { [self] in reinstallVoice() },
            openAccessibilitySettings: { [self] in openAccessibilitySettings() },
            requestScreenRecording: { [self] in requestScreenRecording() },
            setLaunchAtLogin: { [self] in setLaunchAtLogin($0) },
            openLoginItemsSettings: { [self] in openLoginItemsSettings() },
            shortcutChanged: { [self] in shortcutChanged($0, $1) },
            stopReading: { [self] in stopReading() },
            quit: { [self] in quit() }
        )
    }
}
