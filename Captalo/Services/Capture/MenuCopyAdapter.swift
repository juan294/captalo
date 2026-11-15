import ApplicationServices
import CaptaloCore

/// Finds the app's own Copy menu item (Cmd+C, no other modifiers) through
/// Accessibility. Language-independent: it matches the key equivalent, not the title.
nonisolated final class MenuCopyAdapter: MenuCopyAccess, @unchecked Sendable {
    fileprivate enum Lookup {
        case found(AXUIElement)
        case absent
        case unreadable
    }

    func copyItemState(pid: Int32) -> MenuCopyState {
        let lookup = copyItem(pid: pid)
        guard case let .found(item) = lookup else { return lookup.isAbsent ? .absent : .unknown }
        var enabled: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, kAXEnabledAttribute as CFString, &enabled) == .success,
              let isEnabled = enabled as? Bool else { return .unknown }
        return isEnabled ? .enabled : .disabled
    }

    func pressCopy(pid: Int32) -> Bool {
        guard case let .found(item) = copyItem(pid: pid) else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    /// `.absent` only when the menu bar was read and holds no Copy item;
    /// any read error is `.unreadable`, so no synthetic key is sent.
    private func copyItem(pid: Int32) -> Lookup {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, AccessibilityAdapter.messagingTimeout)
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &value) {
        case .success: break
        case .attributeUnsupported, .noValue: return .absent
        default: return .unreadable
        }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return .unreadable }
        let menuBar = value as! AXUIElement
        for topLevel in children(menuBar) {
            for menu in children(topLevel) {
                for item in children(menu) where isCopy(item) {
                    return .found(item)
                }
            }
        }
        return .absent
    }

    private func isCopy(_ item: AXUIElement) -> Bool {
        var char: CFTypeRef?
        var modifiers: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, kAXMenuItemCmdCharAttribute as CFString, &char) == .success,
              let key = char as? String, key.caseInsensitiveCompare("c") == .orderedSame else { return false }
        // 0 means Command only (kAXMenuItemModifierNone).
        guard AXUIElementCopyAttributeValue(item, kAXMenuItemCmdModifiersAttribute as CFString, &modifiers) == .success,
              let mask = modifiers as? Int else { return false }
        return mask == 0
    }

    private func children(_ parent: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return (value as? [AXUIElement]) ?? []
    }
}

private extension MenuCopyAdapter.Lookup {
    var isAbsent: Bool {
        if case .absent = self { return true }
        return false
    }
}
