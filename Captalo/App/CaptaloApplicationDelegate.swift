import AppKit
import CaptaloCore
import KeyboardShortcuts

@MainActor
final class CaptaloApplicationDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = CaptaloAppState.shared
        state.onVoiceAttentionRequired = { [weak self] in self?.showSettings() }
        state.onAccessibilityPermissionRequired = { [weak self] in self?.showSettings() }
        KeyboardShortcuts.onKeyDown(for: .readSelection) {
            CaptaloAppState.shared.speakSelection()
        }
        state.refreshSetup()
        state.prepareVoice()
        // Required setup missing (voice is still checking here): open the window at launch.
        if state.setup.requiredMissing.contains(where: { $0 != .voice }) {
            showSettings()
        }
    }

    /// Opening Cáptalo again (Spotlight, Finder) shows the settings window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    /// Quit lets an open clipboard transaction finish its cleanup first (plan phase 2).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let requests = CaptaloAppState.shared.requests
        Task {
            await requests.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        CaptaloAppState.shared.refreshSetup()
    }

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(state: CaptaloAppState.shared)
        }
        settingsWindow?.present()
    }
}
