/// A key binding as the shortcut library stores it.
public struct ShortcutBinding: Hashable, Sendable {
    public let keyCode: Int
    public let modifiers: Int

    public init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum ShortcutValidation: Equatable, Sendable {
    case accepted
    /// The binding is identical to the other Cáptalo shortcut.
    case identicalToOther

    /// The recorder's own checks cover system shortcuts and the app's menu
    /// only; this adds the one rule Cáptalo owns.
    public static func validate(_ candidate: ShortcutBinding, other: ShortcutBinding?) -> ShortcutValidation {
        candidate == other ? .identicalToOther : .accepted
    }
}
