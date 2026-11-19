import Foundation

public enum MenuCopyState: Equatable, Sendable {
    case enabled
    case disabled
    /// The app has no Copy item (Cmd+C key equivalent).
    case absent
    /// The menu could not be read (timeout or error): no key event is sent.
    case unknown
}

/// The app's own Edit > Copy item, reached through Accessibility.
public protocol MenuCopyAccess: Sendable {
    func copyItemState(pid: Int32) -> MenuCopyState
    /// Presses the enabled Copy item. Returns false when the press failed.
    func pressCopy(pid: Int32) -> Bool
}

/// Synthetic Cmd+C, used only when the app has no Copy menu item.
public protocol KeyEventPosting: Sendable {
    func shortcutModifiersReleased() -> Bool
    func postCopy()
}

/// Frontmost app and focused element, for the pre-Copy recheck.
public protocol FocusEnvironment: Sendable {
    func frontmostPID() -> Int32?
    func focusedElement(pid: Int32) -> ElementRef?
}

extension FocusEnvironment {
    /// The press's app is still frontmost with the same focused element.
    public func matches(_ source: InputSource) -> Bool {
        frontmostPID() == source.pid && focusedElement(pid: source.pid) == source.focusedElement
    }
}

/// The layered reader (assessment §3, plan phase 2).
public final class CaptureCoordinator: Sendable {
    public static let modifierWaitPolls = 50
    public static let modifierPollInterval = Duration.milliseconds(10)

    private let ax: SelectionAccessibility
    private let layer: AXSelectionLayer
    private let menu: MenuCopyAccess
    private let keys: KeyEventPosting
    private let focus: FocusEnvironment
    private let transaction: @MainActor @Sendable () -> ClipboardTransaction
    private let isCurrent: @Sendable (InputToken) async -> Bool
    private let sleep: @Sendable (Duration) async -> Void

    public init(
        ax: SelectionAccessibility,
        menu: MenuCopyAccess,
        keys: KeyEventPosting,
        focus: FocusEnvironment,
        transaction: @escaping @MainActor @Sendable () -> ClipboardTransaction,
        isCurrent: @escaping @Sendable (InputToken) async -> Bool,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.ax = ax
        layer = AXSelectionLayer(ax: ax, focus: focus, sleep: sleep)
        self.menu = menu
        self.keys = keys
        self.focus = focus
        self.transaction = transaction
        self.isCurrent = isCurrent
        self.sleep = sleep
    }

    public func capture(_ token: InputToken) async -> CaptureOutcome {
        guard ax.isProcessTrusted() else { return .permissionMissing }
        let hidesSelection = CopyPolicy.hidesSelection(bundleID: token.source.bundleID)
        switch await layer.read(token.source) {
        case let .selected(text):
            return .text(text, layer: .accessibility)
        case .confirmedEmpty where !hidesSelection:
            return .nothingSelected
        case .confirmedEmpty, .unavailable:
            break
        }
        guard CopyPolicy.allowsCopy(bundleID: token.source.bundleID) else {
            return .unsupported(.copyMayNotReflectSelection)
        }
        if hidesSelection {
            // D31: the menu reports Copy disabled too, so only the key can copy.
            // A sent key that changes nothing means nothing was selected.
            let outcome = await syntheticCopy(token)
            return outcome == .failed(.noCopyResult) ? .nothingSelected : outcome
        }
        let pid = token.source.pid
        switch menu.copyItemState(pid: pid) {
        case .disabled:
            return .nothingSelected
        case .unknown:
            return .failed(.menuUnreadable)
        case .enabled:
            return await copy(token, layer: .menuCopy) { [menu] in menu.pressCopy(pid: pid) }
        case .absent:
            return await syntheticCopy(token)
        }
    }

    /// Cmd+C after the shortcut's modifiers are released.
    private func syntheticCopy(_ token: InputToken) async -> CaptureOutcome {
        guard await waitForModifierRelease() else { return .unsupported(.modifiersHeld) }
        // Modifiers are checked again at the post: a lock wait may have passed.
        return await copy(token, layer: .syntheticCopy) { [keys] in
            guard keys.shortcutModifiersReleased() else { return false }
            keys.postCopy()
            return true
        }
    }

    private func waitForModifierRelease() async -> Bool {
        for _ in 0..<Self.modifierWaitPolls {
            if keys.shortcutModifiersReleased() { return true }
            await sleep(Self.modifierPollInterval)
        }
        return keys.shortcutModifiersReleased()
    }

    private func copy(
        _ token: InputToken,
        layer: CaptureLayerKind,
        action: @escaping @Sendable () -> Bool
    ) async -> CaptureOutcome {
        let isCurrent = self.isCurrent
        let focus = self.focus
        let source = token.source
        let transaction = await transaction()
        let result = await transaction.run(
            isCurrent: { await isCurrent(token) },
            sourceUnchanged: { focus.matches(source) },
            copyAction: action
        )
        switch result {
        case let .copied(text): return text.isEmpty ? .nothingSelected : .text(text, layer: layer)
        case .cancelled: return .cancelled
        case let .failed(failure): return .failed(failure)
        }
    }
}
