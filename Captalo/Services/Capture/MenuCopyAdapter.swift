import ApplicationServices
import CaptaloCore
import Synchronization

/// Finds the app's own Copy menu item (Cmd+C, no other modifiers) through
/// Accessibility. Language-independent: it matches the key equivalent, not the title.
nonisolated final class MenuCopyAdapter: MenuCopyAccess, Sendable {
    /// The item found by the last state query, pressed without a second menu walk.
    private let lastItem = Mutex<(pid: Int32, item: AXUIElement)?>(nil)

    func copyItemState(pid: Int32) -> MenuCopyState {
        let state: MenuCopyState
        var found: AXUIElement?
        switch copyItem(pid: pid) {
        case .absent: state = .absent
        case .unreadable: state = .unknown
        case let .found(item):
            found = item
            switch AX.read(item, kAXEnabledAttribute, { $0 as? Bool }) {
            case let .value(enabled): state = enabled ? .enabled : .disabled
            case .unsupported, .error: state = .unknown
            }
        }
        lastItem.withLock { $0 = found.map { (pid, $0) } }
        return state
    }

    func pressCopy(pid: Int32) -> Bool {
        let item = lastItem.withLock { last -> AXUIElement? in
            defer { last = nil }
            return last?.pid == pid ? last?.item : nil
        }
        guard let item else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    private enum Lookup {
        case found(AXUIElement)
        case absent
        case unreadable
    }

    /// `.absent` only when the menu bar was read and holds no Copy item;
    /// any read error is `.unreadable`, so no synthetic key is sent.
    private func copyItem(pid: Int32) -> Lookup {
        let menuBar: AXUIElement
        switch AX.element(AX.application(pid), kAXMenuBarAttribute) {
        case let .value(element): menuBar = element
        case .unsupported: return .absent
        case .error: return .unreadable
        }
        for topLevel in AX.children(menuBar) {
            for menu in AX.children(topLevel) {
                for item in AX.children(menu) where isCopy(item) {
                    return .found(item)
                }
            }
        }
        return .absent
    }

    /// One batched read of the key equivalent and its modifiers (0 means Command only).
    private func isCopy(_ item: AXUIElement) -> Bool {
        let names = [kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute] as CFArray
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(item, names, AXCopyMultipleAttributeOptions(), &values) == .success,
              let pair = values as? [Any], pair.count == 2,
              let key = pair[0] as? String, let mask = pair[1] as? Int else { return false }
        return key.caseInsensitiveCompare("c") == .orderedSame && mask == 0
    }
}
