import CaptaloCore
import KeyboardShortcuts

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
            shortcutRejection: shortcutRejection,
            regionNotice: regionFailureNotice,
            voiceError: lastReadingError,
            loginItem: loginItem,
            screenRecordingRequested: screenRecordingRequested
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
            quitAndReopen: { [self] in quitAndReopen() },
            setLaunchAtLogin: { [self] in setLaunchAtLogin($0) },
            openLoginItemsSettings: { [self] in openLoginItemsSettings() },
            shortcutChanged: { [self] in shortcutChanged($0, $1) },
            quit: { [self] in quit() }
        )
    }
}
