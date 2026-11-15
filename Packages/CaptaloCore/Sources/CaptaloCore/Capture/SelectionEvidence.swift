import Foundation

/// The result of reading one accessibility attribute.
public enum AXRead<Value: Sendable>: Sendable {
    case value(Value)
    /// The element does not support the attribute.
    case unsupported
    /// The call failed (timeout, invalid element, cannot complete).
    case error
}

public struct AXTextRange: Equatable, Sendable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

/// The Accessibility calls the selection layer needs. The app implements it
/// with `AXUIElement`; tests use a fake because Accessibility is not owned code.
public protocol SelectionAccessibility: Sendable {
    func isProcessTrusted() -> Bool
    func selectedText(_ element: ElementRef) -> AXRead<String>
    func selectedTextRange(_ element: ElementRef) -> AXRead<AXTextRange>
    func string(for range: AXTextRange, in element: ElementRef) -> AXRead<String>
    /// WebKit: `AXSelectedTextMarkerRange`, then `AXStringForTextMarkerRange`.
    func textMarkerSelection(_ element: ElementRef) -> AXRead<String>
    /// Writes a Boolean attribute on the application element of `pid`.
    func setApplicationAttribute(_ name: String, to value: Bool, pid: Int32) -> Bool
}

public enum SelectionEvidence: Equatable, Sendable {
    case selected(String)
    case confirmedEmpty
    case unavailable
}

/// Layer 1 of the approved reader (assessment §3): Accessibility variants,
/// with `AXManualAccessibility` for Chromium and Electron apps.
public final class AXSelectionLayer: @unchecked Sendable {
    /// Bundle IDs of Chromium and Electron apps that build their tree only
    /// after `AXManualAccessibility` is set. Never set `AXEnhancedUserInterface`.
    public static let manualAccessibilityBundles: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "org.chromium.Chromium", "com.microsoft.edgemac", "com.brave.Browser",
        "com.vivaldi.Vivaldi", "com.microsoft.VSCode", "com.tinyspeck.slackmacgap",
        "com.hnc.Discord", "notion.id", "md.obsidian",
    ]
    public static let manualAccessibilityAttribute = "AXManualAccessibility"

    private let ax: SelectionAccessibility
    private let lock = NSLock()
    private var manualAccessibilityPIDs: Set<Int32> = []

    public init(ax: SelectionAccessibility) {
        self.ax = ax
    }

    public func read(_ source: InputSource) -> SelectionEvidence {
        guard let element = source.focusedElement else { return .unavailable }
        let first = probe(element)
        if case .selected = first { return first }
        guard let bundle = source.bundleID, Self.manualAccessibilityBundles.contains(bundle),
              markManualAccessibility(source.pid) else { return first }
        guard ax.setApplicationAttribute(Self.manualAccessibilityAttribute, to: true, pid: source.pid) else {
            return first
        }
        return probe(element)
    }

    /// True the first time it is called for a PID (once per app launch).
    private func markManualAccessibility(_ pid: Int32) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return manualAccessibilityPIDs.insert(pid).inserted
    }

    private func probe(_ element: ElementRef) -> SelectionEvidence {
        var confirmedEmpty = false
        switch ax.selectedText(element) {
        case let .value(text) where !text.isEmpty: return .selected(text)
        case .value: confirmedEmpty = true
        default: break
        }
        switch ax.selectedTextRange(element) {
        case let .value(range) where range.length > 0:
            if case let .value(text) = ax.string(for: range, in: element), !text.isEmpty {
                return .selected(text)
            }
        case .value:
            confirmedEmpty = true
        default: break
        }
        if case let .value(text) = ax.textMarkerSelection(element), !text.isEmpty {
            return .selected(text)
        }
        return confirmedEmpty ? .confirmedEmpty : .unavailable
    }
}
