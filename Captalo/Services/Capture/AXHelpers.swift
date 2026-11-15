import ApplicationServices
import CaptaloCore

/// Shared Accessibility reads with one timeout policy: every element gets
/// the 0.5 s messaging timeout before it is queried.
nonisolated enum AX {
    static let messagingTimeout: Float = 0.5

    static func prepared(_ element: AXUIElement) -> AXUIElement {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    static func application(_ pid: pid_t) -> AXUIElement {
        prepared(AXUIElementCreateApplication(pid))
    }

    static func systemWide() -> AXUIElement {
        prepared(AXUIElementCreateSystemWide())
    }

    /// Maps an AX result to `AXRead`: unsupported attributes and missing
    /// values are `.unsupported`; every other error is `.error`.
    static func classify<T>(_ status: AXError, _ value: CFTypeRef?, _ convert: (CFTypeRef) -> T?) -> AXRead<T> {
        switch status {
        case .success:
            guard let value, let converted = convert(value) else { return .error }
            return .value(converted)
        case .attributeUnsupported, .parameterizedAttributeUnsupported, .noValue:
            return .unsupported
        default:
            return .error
        }
    }

    static func read<T>(_ element: AXUIElement, _ attribute: String, _ convert: (CFTypeRef) -> T?) -> AXRead<T> {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return classify(status, value, convert)
    }

    static func read<T>(_ element: AXUIElement, _ attribute: String, parameter: CFTypeRef, _ convert: (CFTypeRef) -> T?) -> AXRead<T> {
        var value: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &value)
        return classify(status, value, convert)
    }

    static func asElement(_ value: CFTypeRef) -> AXUIElement? {
        CFGetTypeID(value) == AXUIElementGetTypeID() ? (value as! AXUIElement) : nil
    }

    static func element(_ parent: AXUIElement, _ attribute: String) -> AXRead<AXUIElement> {
        read(parent, attribute) { asElement($0).map(prepared) }
    }

    static func children(_ parent: AXUIElement) -> [AXUIElement] {
        guard case let .value(children) = read(parent, kAXChildrenAttribute, { $0 as? [AXUIElement] }) else { return [] }
        return children.map(prepared)
    }
}
