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

    enum Status { case success, unsupported, error }

    /// The one AX error policy: unsupported attributes and missing values
    /// are `.unsupported`; every other failure is `.error`.
    static func status(_ error: AXError) -> Status {
        switch error {
        case .success: .success
        case .attributeUnsupported, .parameterizedAttributeUnsupported, .noValue: .unsupported
        default: .error
        }
    }

    static func classify<T>(_ error: AXError, _ value: CFTypeRef?, _ convert: (CFTypeRef) -> T?) -> AXRead<T> {
        switch status(error) {
        case .success:
            guard let value, let converted = convert(value) else { return .error }
            return .value(converted)
        case .unsupported: return .unsupported
        case .error: return .error
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

    /// One value from `AXUIElementCopyMultipleAttributeValues`, classified
    /// like a single read: a failed attribute arrives as an AXValue holding
    /// its AXError, and a null value is an absent attribute.
    static func entry<T>(_ value: AnyObject, _ convert: (CFTypeRef) -> T?) -> AXRead<T> {
        if CFGetTypeID(value) == CFNullGetTypeID() { return .unsupported }
        if CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .axError {
            var error = AXError.failure
            guard AXValueGetValue(value as! AXValue, .axError, &error) else { return .error }
            return classify(error, nil, convert)
        }
        return classify(.success, value, convert)
    }
}
