import ApplicationServices
import CaptaloCore

/// Finds the app's own Copy menu item (Cmd+C, no other modifiers) through
/// Accessibility. Language-independent: it matches the key equivalent, not the title.
nonisolated final class MenuCopyAdapter: MenuCopyAccess, @unchecked Sendable {
    func copyItemState(pid: Int32) -> MenuCopyState {
        guard let item = copyItem(pid: pid) else { return .absent }
        var enabled: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, kAXEnabledAttribute as CFString, &enabled) == .success,
              let isEnabled = enabled as? Bool else { return .absent }
        return isEnabled ? .enabled : .disabled
    }

    func pressCopy(pid: Int32) -> Bool {
        guard let item = copyItem(pid: pid) else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    private func copyItem(pid: Int32) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, AccessibilityAdapter.messagingTimeout)
        guard let menuBar: AXUIElement = element(app, kAXMenuBarAttribute) else { return nil }
        for topLevel in children(menuBar) {
            for menu in children(topLevel) {
                for item in children(menu) where isCopy(item) {
                    return item
                }
            }
        }
        return nil
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

    private func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func children(_ parent: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return (value as? [AXUIElement]) ?? []
    }
}
