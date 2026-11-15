import Carbon.HIToolbox
import CaptaloCore
import CoreGraphics

/// Synthetic Cmd+C. Used only when the app has no Copy menu item.
nonisolated final class KeyEventAdapter: KeyEventPosting, Sendable {
    /// All four modifiers must be up: any held one would turn Cmd+C into another shortcut.
    func shortcutModifiersReleased() -> Bool {
        let held = CGEventSource.flagsState(.combinedSessionState)
        return held.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]).isEmpty
    }

    func postCopy() {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
