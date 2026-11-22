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

    /// Refreshes the parts of setup the panel shows (permissions, login item).
    func refreshSetup() {
        refreshAccessibilityPermission()
        refreshScreenRecording()
        refreshLoginItem()
    }

    // MARK: Shortcut

    /// Rejects bindings already assigned to another Cáptalo action.
    func shortcutChanged(_ name: KeyboardShortcuts.Name, _ shortcut: KeyboardShortcuts.Shortcut?) {
        var rejection: String?
        let names: [KeyboardShortcuts.Name] = [.readSelection, .readRegion, .stopReading]
        let others = names.filter { $0 != name }
            .compactMap { KeyboardShortcuts.getShortcut(for: $0) }
            .map(Self.binding)
        if let shortcut, ShortcutValidation.validate(Self.binding(shortcut), others: others) == .identicalToOther {
            KeyboardShortcuts.setShortcut(nil, for: name)
            rejection = "Cáptalo already uses that shortcut. Choose another."
        }
        shortcutRejection = rejection
        readShortcutSet = KeyboardShortcuts.getShortcut(for: .readSelection) != nil
        regionShortcutSet = KeyboardShortcuts.getShortcut(for: .readRegion) != nil
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
