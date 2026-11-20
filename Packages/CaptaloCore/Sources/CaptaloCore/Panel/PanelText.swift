import Foundation

/// The name the panel shows for a bundled voice ID.
public enum VoiceDisplay {
    /// The part after the first underscore, capitalized: "af_heart" is "Heart".
    public static func name(for id: String) -> String {
        let tail = id.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false).last.map(String.init) ?? id
        guard let first = tail.first else { return id }
        return first.uppercased() + tail.dropFirst()
    }
}

/// A recorded shortcut as keycaps.
public enum ShortcutKeycaps {
    /// The glyphs the recorder library writes for modifiers. Fn is a globe with
    /// a text variation selector (KeyboardShortcuts 3.1.0, `Utilities.swift`).
    static let modifiers: Set<Character> = ["⌃", "⌥", "⇧", "⌘", "🌐", "🌐\u{FE0E}"]

    /// One keycap per leading modifier glyph, then the key: "⌃⌥F5" is ⌃, ⌥, F5.
    public static func labels(description: String?) -> [String] {
        guard let description, !description.isEmpty else { return [] }
        let leading = description.prefix { modifiers.contains($0) }
        let key = description.dropFirst(leading.count)
        return leading.map { String($0) } + (key.isEmpty ? [] : [String(key)])
    }
}

extension ReadingPreferences {
    /// A speed as the panel shows it: "1.00×".
    public static func label(for speed: Float) -> String {
        String(format: "%.2f×", speed)
    }
}

extension VoiceInstallState {
    /// The panel's repair button, if the state has one.
    public var repairLabel: String? {
        switch self {
        case .damaged, .failed: "Reinstall voice"
        case .installFailed: "Retry"
        case .checking, .ready, .bundleInvalid: nil
        }
    }

    public var statusText: String {
        switch self {
        case .checking: "Preparing local voice..."
        case .ready: "Voice ready"
        case .damaged: "Voice files are damaged. Reinstall voice."
        case .bundleInvalid: "The voice in this copy of Cáptalo is damaged. Reinstall Cáptalo."
        case let .installFailed(need): "Cáptalo needs \(Int((Double(need) / 1_000_000).rounded(.up))) MB free to install its voice."
        case .failed: "The voice could not start."
        }
    }
}
