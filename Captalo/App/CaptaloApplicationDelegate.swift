import AppKit
import CaptaloCore
import KeyboardShortcuts

@MainActor
final class CaptaloApplicationDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // A panel debug command renders or probes, then exits: no icon, no voice.
        if PanelDebugCommands.runIfRequested() { return }
        #endif
        let state = CaptaloAppState.shared
        statusItem = StatusItemController(state: state)
        state.onSetupRequired = { [weak self] in self?.statusItem?.present() }
        KeyboardShortcuts.onKeyDown(for: .readSelection) {
            CaptaloAppState.shared.speakSelection()
        }
        KeyboardShortcuts.onKeyDown(for: .readRegion) {
            CaptaloAppState.shared.readRegion()
        }
        state.refreshAccessibilityPermission()
        state.prepareVoice()
        // Required setup missing (a voice still checking is pending): open the panel at launch.
        // The next turn of the run loop, so the icon has its place in the menu bar.
        DispatchQueue.main.async { state.requireSetup() }
    }

    /// Opening Cáptalo again (Spotlight, Finder) shows the settings panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem?.present()
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
}
