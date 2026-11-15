import AppKit
import CaptaloCore
import Combine
import KeyboardShortcuts
import ServiceManagement

extension CaptaloAppState {
    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func setSpeed(_ value: Float) {
        // Kokoro's own speed, fixed per reading: applies from the next reading.
        speed = ReadingPreferences.snap(value)
    }

    // MARK: Setup

    var setupEnvironment: SetupEnvironment {
        SetupEnvironment(
            voice: voiceState,
            accessibilityTrusted: accessibilityPermissionGranted,
            readShortcutSet: KeyboardShortcuts.getShortcut(for: .readSelection) != nil,
            lastReadingError: lastReadingError != nil
        )
    }

    var setup: SetupState { SetupState.evaluate(setupEnvironment) }

    /// Refreshes the parts of setup the window shows (permission, login item).
    func refreshSetup() {
        refreshAccessibilityPermission()
        refreshLoginItem()
    }

    // MARK: Shortcut

    /// KeyboardShortcuts 3.1.0 does not report registration failure (phase 4
    /// entry probe), so the row says what to do if the shortcut does nothing.
    var shortcutNotice: String? {
        KeyboardShortcuts.getShortcut(for: .readSelection) == nil
            ? "Choose a shortcut to read the selected text."
            : "If this shortcut does nothing, another app may use it; choose another."
    }

    /// Rejects a binding identical to the other Cáptalo shortcut (none until region reading).
    func readShortcutChanged(_ shortcut: KeyboardShortcuts.Shortcut?) {
        if let shortcut, let other = otherShortcut(than: .readSelection),
           ShortcutValidation.validate(Self.binding(shortcut), other: Self.binding(other)) == .identicalToOther {
            KeyboardShortcuts.setShortcut(nil, for: .readSelection)
        }
        objectWillChange.send()
    }

    func otherShortcut(than name: KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut? {
        nil
    }

    static func binding(_ shortcut: KeyboardShortcuts.Shortcut) -> ShortcutBinding {
        ShortcutBinding(keyCode: shortcut.carbonKeyCode, modifiers: shortcut.carbonModifiers)
    }

    // MARK: Launch at login

    func refreshLoginItem(registerError: String? = nil) {
        loginItem = LoginItemRow.make(status: Self.loginItemStatus(SMAppService.mainApp.status), registerError: registerError)
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

    static func loginItemStatus(_ status: SMAppService.Status) -> LoginItemStatus {
        switch status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        case .notRegistered: .notRegistered
        @unknown default: .notFound
        }
    }
}
