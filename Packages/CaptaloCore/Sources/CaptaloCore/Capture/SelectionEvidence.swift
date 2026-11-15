import Foundation
import Synchronization

/// The result of reading one accessibility attribute. `.unsupported` is an
/// established absence; `.error` means the answer is unknown.
public enum AXRead<Value> {
    case value(Value)
    /// The element does not support the attribute.
    case unsupported
    /// The call failed (timeout, invalid element, cannot complete).
    case error
}

extension AXRead: Sendable where Value: Sendable {}

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
public final class AXSelectionLayer: Sendable {
    /// Bundle IDs of Chromium and Electron apps that build their tree only
    /// after `AXManualAccessibility` is set. Never set `AXEnhancedUserInterface`.
    public static let manualAccessibilityBundles: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "org.chromium.Chromium", "com.microsoft.edgemac", "com.brave.Browser",
        "com.vivaldi.Vivaldi", "com.microsoft.VSCode", "com.tinyspeck.slackmacgap",
        "com.hnc.Discord", "notion.id", "md.obsidian",
    ]
    public static let manualAccessibilityAttribute = "AXManualAccessibility"

    /// After `AXManualAccessibility` is set, Chromium builds its tree
    /// asynchronously: the focused element is re-queried up to this many
    /// times, `retryInterval` apart (bounded at 200 ms).
    public static let retryAttempts = 5
    public static let retryInterval = Duration.milliseconds(40)

    private let ax: SelectionAccessibility
    private let focus: FocusEnvironment
    private let sleep: @Sendable (Duration) async -> Void
    private let manualAccessibilityPIDs = Mutex<Set<Int32>>([])

    public init(ax: SelectionAccessibility, focus: FocusEnvironment, sleep: @escaping @Sendable (Duration) async -> Void) {
        self.ax = ax
        self.focus = focus
        self.sleep = sleep
    }

    public func read(_ source: InputSource) async -> SelectionEvidence {
        let first = source.focusedElement.map(probe) ?? .unavailable
        if case .selected = first { return first }
        guard let bundle = source.bundleID, Self.manualAccessibilityBundles.contains(bundle),
              markManualAccessibility(source.pid) else { return first }
        guard ax.setApplicationAttribute(Self.manualAccessibilityAttribute, to: true, pid: source.pid) else {
            return first
        }
        var latest = first
        for _ in 0..<Self.retryAttempts {
            await sleep(Self.retryInterval)
            guard let element = focus.focusedElement(pid: source.pid) ?? source.focusedElement else { continue }
            latest = probe(element)
            if case .selected = latest { return latest }
        }
        return latest
    }

    /// True the first time it is called for a PID (once per app launch).
    private func markManualAccessibility(_ pid: Int32) -> Bool {
        manualAccessibilityPIDs.withLock { $0.insert(pid).inserted }
    }

    private func probe(_ element: ElementRef) -> SelectionEvidence {
        var confirmedEmpty = false
        // A nonzero range whose text cannot be read is evidence of a selection:
        // it must never count as an empty one.
        var selectionUnreadable = false
        // An error (timeout, invalid element) stops the probe: further calls
        // to a hung app would each wait for the messaging timeout.
        switch ax.selectedText(element) {
        case let .value(text) where !text.isEmpty: return .selected(text)
        case .value: confirmedEmpty = true
        case .unsupported: break
        case .error: return .unavailable
        }
        switch ax.selectedTextRange(element) {
        case let .value(range) where range.length > 0:
            if case let .value(text) = ax.string(for: range, in: element), !text.isEmpty {
                return .selected(text)
            }
            selectionUnreadable = true
        case .value:
            confirmedEmpty = true
        case .unsupported: break
        case .error: return .unavailable
        }
        if case let .value(text) = ax.textMarkerSelection(element), !text.isEmpty {
            return .selected(text)
        }
        return confirmedEmpty && !selectionUnreadable ? .confirmedEmpty : .unavailable
    }
}
