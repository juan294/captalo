import AppKit
import CaptaloCore
import SwiftUI

/// The menu-bar icon and the settings panel under it (owner decision 12).
/// The panel is the app's only interface. It opens on a click on the icon,
/// when the app is opened again, when required setup is missing, or when the
/// voice or a region reading needs attention. Its content is `PanelRootView`
/// (monochrome popover plan); it follows the system's light or dark appearance.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    /// A click on the icon first closes a transient panel, then sends the
    /// button's action; a close this recent means that click was a close.
    private static let closeClickWindow: TimeInterval = 0.3

    private let state: CaptaloAppState
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let selection = PanelSelection()
    private var lastClose = Date.distantPast

    init(state: CaptaloAppState) {
        self.state = state
        super.init()
        let content = NSHostingController(rootView: LivePanelView(selection: selection).environmentObject(state))
        content.sizingOptions = .preferredContentSize
        popover.contentViewController = content
        popover.behavior = .transient
        popover.delegate = self
        if let button = statusItem.button {
            // The accented C (concept A), a template image in Assets.xcassets.
            let glyph = NSImage(named: "MenuBarGlyph")
            glyph?.isTemplate = true
            glyph?.accessibilityDescription = "Cáptalo"
            button.image = glyph
            button.target = self
            button.action = #selector(togglePanel)
        }
    }

    @objc private func togglePanel() {
        if popover.isShown {
            popover.performClose(nil)
        } else if Date().timeIntervalSince(lastClose) > Self.closeClickWindow {
            present()
        }
    }

    /// A shortcut recorder that was still recording ends with the panel. The
    /// library also ends it when the window stops being key; this is the
    /// explicit path while the panel still has its window.
    func popoverWillClose(_ notification: Notification) {
        popover.contentViewController?.view.window?.makeFirstResponder(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        lastClose = Date()
    }

    /// Opens the panel under the icon. A popover cannot open from an icon that
    /// macOS hid (a full menu bar), so the app then stays behind the frontmost
    /// app instead of taking focus with nothing to show (D36). Activation is
    /// requested so the shortcut recorders can take keys; macOS may refuse it,
    /// and a click into the panel then gives them focus.
    func present() {
        guard !popover.isShown, let button = statusItem.button,
              button.window?.occlusionState.contains(.visible) == true else { return }
        state.refreshSetup()
        // Each open starts on the tab that needs the user, else on Read.
        selection.tab = PanelModel.make(state.panelInput).initialTab
        NSApplication.shared.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
