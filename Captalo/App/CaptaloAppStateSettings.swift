import AppKit
import CaptaloCore
import KeyboardShortcuts
import ServiceManagement

extension CaptaloAppState {
    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func setSpeed(_ value: Float) {
        // Kokoro's own speed, fixed per reading: applies from the next reading.
        let snapped = ReadingPreferences.snap(value)
        if snapped != speed { speed = snapped }
    }

    // MARK: Setup

    var setupEnvironment: SetupEnvironment {
        SetupEnvironment(
            voice: voiceState,
            accessibilityTrusted: accessibilityPermissionGranted,
            readShortcutSet: readShortcutSet,
            screenRecordingGranted: screenRecordingGranted,
            regionShortcutSet: regionShortcutSet,
            lastReadingError: lastReadingError != nil
        )
    }

    var setup: SetupState { SetupState.evaluate(setupEnvironment) }

    /// Refreshes the parts of setup the window shows (permissions, login item).
    func refreshSetup() {
        refreshAccessibilityPermission()
        refreshScreenRecording()
        refreshLoginItem()
    }

    // MARK: Shortcut

    /// KeyboardShortcuts 3.1.0 does not report registration failure (phase 4
    /// entry probe), so the row says what to do if the shortcut does nothing.
    var shortcutNotice: String? {
        if let shortcutRejection { return shortcutRejection }
        return !readShortcutSet
            ? "Choose a shortcut to read the selected text: click the field, then hold ⌘, ⌥ or ⌃ and press a key."
            : "If this shortcut does nothing, another app may use it; choose another."
    }

    /// Rejects a binding identical to the other Cáptalo shortcut, for either recorder.
    func shortcutChanged(_ name: KeyboardShortcuts.Name, _ shortcut: KeyboardShortcuts.Shortcut?) {
        var rejection: String?
        if let shortcut, let other = KeyboardShortcuts.getShortcut(for: otherName(than: name)),
           ShortcutValidation.validate(Self.binding(shortcut), other: Self.binding(other)) == .identicalToOther {
            KeyboardShortcuts.setShortcut(nil, for: name)
            rejection = "That shortcut is already used by Cáptalo's other shortcut; choose another."
        }
        shortcutRejection = rejection
        readShortcutSet = KeyboardShortcuts.getShortcut(for: .readSelection) != nil
        regionShortcutSet = KeyboardShortcuts.getShortcut(for: .readRegion) != nil
    }

    func otherName(than name: KeyboardShortcuts.Name) -> KeyboardShortcuts.Name {
        name == .readSelection ? .readRegion : .readSelection
    }

    static func binding(_ shortcut: KeyboardShortcuts.Shortcut) -> ShortcutBinding {
        ShortcutBinding(keyCode: shortcut.carbonKeyCode, modifiers: shortcut.carbonModifiers)
    }

    // MARK: Launch at login

    func refreshLoginItem(registerError: String? = nil) {
        let inApplications = LoginItemRow.isInApplicationsFolder(
            bundlePath: Bundle.main.bundlePath, home: FileManager.default.homeDirectoryForCurrentUser.path
        )
        let row = LoginItemRow.make(status: LoginItemStatus(SMAppService.mainApp.status), registerError: registerError,
                                    inApplicationsFolder: inApplications)
        if row != loginItem { loginItem = row }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            refreshLoginItem()
        } catch {
            refreshLoginItem(registerError: error.localizedDescription)
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

}
