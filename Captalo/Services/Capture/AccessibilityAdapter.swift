import AppKit
import ApplicationServices
import CaptaloCore

/// `SelectionAccessibility` and `FocusEnvironment` over `AXUIElement`.
/// Every element gets a short messaging timeout so an unresponsive app
/// cannot hang a press.
nonisolated final class AccessibilityAdapter: SelectionAccessibility, FocusEnvironment, @unchecked Sendable {
    static let messagingTimeout: Float = 0.5
    private static let markerRangeAttribute = "AXSelectedTextMarkerRange"
    private static let stringForMarkerRange = "AXStringForTextMarkerRange"

    func isProcessTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// The source of a press: the system-wide focused element and its app.
    func currentSource() -> InputSource? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, Self.messagingTimeout)
        guard let element = copyElement(system, kAXFocusedUIElementAttribute) else {
            guard let pid = frontmostPID() else { return nil }
            return InputSource(pid: pid, bundleID: bundleID(pid), focusedElement: nil)
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return InputSource(pid: pid, bundleID: bundleID(pid), focusedElement: ElementRef(element))
    }

    func frontmostPID() -> Int32? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, Self.messagingTimeout)
        guard let app = copyElement(system, kAXFocusedApplicationAttribute) else { return nil }
        var pid: pid_t = 0
        return AXUIElementGetPid(app, &pid) == .success ? pid : nil
    }

    func focusedElement(pid: Int32) -> ElementRef? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        guard let element = copyElement(app, kAXFocusedUIElementAttribute) else { return nil }
        return ElementRef(element)
    }

    func selectedText(_ ref: ElementRef) -> AXRead<String> {
        guard let element = element(ref) else { return .error }
        return read(element, kAXSelectedTextAttribute) { $0 as? String }
    }

    func selectedTextRange(_ ref: ElementRef) -> AXRead<AXTextRange> {
        guard let element = element(ref) else { return .error }
        return read(element, kAXSelectedTextRangeAttribute) { value in
            guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
            var range = CFRange()
            guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
            return AXTextRange(location: range.location, length: range.length)
        }
    }

    func string(for range: AXTextRange, in ref: ElementRef) -> AXRead<String> {
        guard let element = element(ref) else { return .error }
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &cfRange) else { return .error }
        return readParameterized(element, kAXStringForRangeParameterizedAttribute, parameter) { $0 as? String }
    }

    func textMarkerSelection(_ ref: ElementRef) -> AXRead<String> {
        guard let element = element(ref) else { return .error }
        var marker: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, Self.markerRangeAttribute as CFString, &marker) {
        case .success:
            guard let marker else { return .error }
            return readParameterized(element, Self.stringForMarkerRange, marker) { $0 as? String }
        case .attributeUnsupported, .noValue:
            return .unsupported
        default:
            return .error
        }
    }

    func setApplicationAttribute(_ name: String, to value: Bool, pid: Int32) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        return AXUIElementSetAttributeValue(app, name as CFString, (value ? kCFBooleanTrue : kCFBooleanFalse)!) == .success
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Helpers

    private func bundleID(_ pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    private func element(_ ref: ElementRef) -> AXUIElement? {
        guard let base = ref.object.base as AnyObject?, CFGetTypeID(base) == AXUIElementGetTypeID() else { return nil }
        let element = base as! AXUIElement
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        return element
    }

    private func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func read<T>(_ element: AXUIElement, _ attribute: String, _ convert: (CFTypeRef) -> T?) -> AXRead<T> {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, attribute as CFString, &value) {
        case .success:
            guard let value, let converted = convert(value) else { return .error }
            return .value(converted)
        case .attributeUnsupported, .noValue:
            return .unsupported
        default:
            return .error
        }
    }

    private func readParameterized<T>(_ element: AXUIElement, _ attribute: String, _ parameter: CFTypeRef, _ convert: (CFTypeRef) -> T?) -> AXRead<T> {
        var value: CFTypeRef?
        switch AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &value) {
        case .success:
            guard let value, let converted = convert(value) else { return .error }
            return .value(converted)
        case .attributeUnsupported, .parameterizedAttributeUnsupported, .noValue:
            return .unsupported
        default:
            return .error
        }
    }
}
