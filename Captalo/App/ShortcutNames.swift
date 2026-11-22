import CaptaloCore
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// "Read selection". Initial shortcut Control-Option-S (owner decision 13).
    static let readSelection = Self("readSelection", initial: .init(.initialReadSelection))
}

extension KeyboardShortcuts.Name {
    /// "Read region" (optional, phase 5). Initial shortcut Control-Option-A (owner decision 13).
    static let readRegion = Self("readRegion", initial: .init(.initialReadRegion))

    /// Optional. Stop is also available from the panel. Initial shortcut
    /// Control-Option-X (owner decision 13).
    static let stopReading = Self("stopReading", initial: .init(.initialStopReading))
}

private extension KeyboardShortcuts.Shortcut {
    init(_ binding: ShortcutBinding) {
        self.init(carbonKeyCode: binding.keyCode, carbonModifiers: binding.modifiers)
    }
}
