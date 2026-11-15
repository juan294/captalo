import ApplicationServices
import CaptaloCore

/// The Accessibility reads behind `MenuCopyFinder`, which owns the Copy-item
/// search and its classification (VAL-02). Every read keeps the AX error
/// policy: unsupported or no value is an established absence, any other
/// failure is unknown.
nonisolated struct AXMenuTree: MenuTreeReading {
    func menuBar(pid: Int32) -> AXRead<AXUIElement> {
        AX.element(AX.application(pid), kAXMenuBarAttribute)
    }

    func children(_ element: AXUIElement) -> AXRead<[AXUIElement]> {
        AX.read(element, kAXChildrenAttribute) { ($0 as? [AXUIElement])?.map(AX.prepared) }
    }

    /// One batched read of the key equivalent and its modifiers.
    func keyEquivalent(_ item: AXUIElement) -> AXRead<MenuKeyEquivalent> {
        let names = [kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute] as CFArray
        var values: CFArray?
        let status = AX.status(AXUIElementCopyMultipleAttributeValues(item, names, AXCopyMultipleAttributeOptions(), &values))
        switch status {
        case .success: break
        case .unsupported: return .unsupported
        case .error: return .error
        }
        guard let pair = values as? [AnyObject], pair.count == 2 else { return .error }
        let character = AXStatus.classify(AX.entry(pair[0])) { $0 as? String }
        let modifiers = AXStatus.classify(AX.entry(pair[1])) { $0 as? Int }
        switch (character, modifiers) {
        case (.error, _), (_, .error): return .error
        default: return .value(MenuKeyEquivalent(character: character.value, modifiers: modifiers.value))
        }
    }

    func isEnabled(_ item: AXUIElement) -> AXRead<Bool> {
        AX.read(item, kAXEnabledAttribute) { $0 as? Bool }
    }

    func press(_ item: AXUIElement) -> Bool {
        AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }
}

private extension AXRead {
    nonisolated var value: Value? {
        if case let .value(value) = self { return value }
        return nil
    }
}
