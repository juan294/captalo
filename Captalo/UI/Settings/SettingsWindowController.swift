import AppKit
import SwiftUI

/// The one small settings window. It appears only when the app is opened
/// again, when required setup is missing, or when the voice needs attention.
@MainActor
final class SettingsWindowController: NSWindowController {
    static let width: CGFloat = 480
    /// A grouped Form is a scroll view with no minimum height, so without this
    /// the hosting controller shrinks the window to its title bar.
    static let minHeight: CGFloat = 600

    init(state: CaptaloAppState) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.minHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Cáptalo"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView().environmentObject(state))
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func present() {
        NSApplication.shared.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
