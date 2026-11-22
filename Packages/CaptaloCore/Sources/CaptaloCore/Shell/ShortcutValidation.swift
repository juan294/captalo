/// A key binding as the shortcut library stores it.
public struct ShortcutBinding: Hashable, Sendable {
    public let keyCode: Int
    public let modifiers: Int

    public init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Carbon `controlKey | optionKey`.
    private static let controlOption = 0x1000 | 0x0800

    /// Initial shortcuts (owner decision 13, core reader plan). Control-Option
    /// with a letter types no character on any keyboard layout. The library
    /// writes them only when the user has no stored value, so a recorded or
    /// cleared shortcut is kept.
    /// Control-Option-S (`kVK_ANSI_S`).
    public static let initialReadSelection = ShortcutBinding(keyCode: 0x01, modifiers: controlOption)
    /// Control-Option-A (`kVK_ANSI_A`).
    public static let initialReadRegion = ShortcutBinding(keyCode: 0x00, modifiers: controlOption)
}

public enum ShortcutValidation: Equatable, Sendable {
    case accepted
    /// The binding is already used by another Cáptalo shortcut.
    case identicalToOther

    /// The recorder's own checks cover system shortcuts and the app's menu
    /// only; this adds the one rule Cáptalo owns.
    public static func validate(_ candidate: ShortcutBinding, others: [ShortcutBinding]) -> ShortcutValidation {
        others.contains(candidate) ? .identicalToOther : .accepted
    }
}
