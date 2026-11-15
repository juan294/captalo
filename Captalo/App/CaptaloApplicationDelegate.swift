import AppKit
import CaptaloCore

@MainActor
final class CaptaloApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        CaptaloAppState.shared.refreshAccessibilityPermission()
        CaptaloAppState.shared.prepareVoice()
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
        CaptaloAppState.shared.refreshAccessibilityPermission()
    }
}
