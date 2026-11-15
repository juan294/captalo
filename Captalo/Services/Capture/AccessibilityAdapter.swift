import AppKit
import ApplicationServices
import CaptaloCore

/// `SelectionAccessibility` and `FocusEnvironment` over `AXUIElement`.
nonisolated final class AccessibilityAdapter: SelectionAccessibility, FocusEnvironment, Sendable {
    private static let markerRangeAttribute = "AXSelectedTextMarkerRange"
    private static let stringForMarkerRange = "AXStringForTextMarkerRange"

    func isProcessTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// The source of a press: the system-wide focused element and its app.
    func currentSource() -> InputSource? {
        guard case let .value(element) = AX.element(AX.systemWide(), kAXFocusedUIElementAttribute) else {
            guard let pid = frontmostPID() else { return nil }
            return InputSource(pid: pid, bundleID: bundleID(pid), focusedElement: nil)
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return InputSource(pid: pid, bundleID: bundleID(pid), focusedElement: ElementRef(element))
    }

    func frontmostPID() -> Int32? {
        guard case let .value(app) = AX.element(AX.systemWide(), kAXFocusedApplicationAttribute) else { return nil }
        var pid: pid_t = 0
        return AXUIElementGetPid(app, &pid) == .success ? pid : nil
    }

    func focusedElement(pid: Int32) -> ElementRef? {
        guard case let .value(element) = AX.element(AX.application(pid), kAXFocusedUIElementAttribute) else { return nil }
        return ElementRef(element)
    }

    func selectedText(_ ref: ElementRef) -> AXRead<String> {
        guard let element = element(ref) else { return .error }
        return AX.read(element, kAXSelectedTextAttribute) { $0 as? String }
    }

    func selectedTextRange(_ ref: ElementRef) -> AXRead<AXTextRange> {
        guard let element = element(ref) else { return .error }
        return AX.read(element, kAXSelectedTextRangeAttribute) { value in
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
        return AX.read(element, kAXStringForRangeParameterizedAttribute, parameter: parameter) { $0 as? String }
    }

    func textMarkerSelection(_ ref: ElementRef) -> AXRead<String> {
        guard let element = element(ref) else { return .error }
        var marker: CFTypeRef?
        switch AX.status(AXUIElementCopyAttributeValue(element, Self.markerRangeAttribute as CFString, &marker)) {
        case .success:
            guard let marker else { return .error }
            return AX.read(element, Self.stringForMarkerRange, parameter: marker) { $0 as? String }
        case .unsupported: return .unsupported
        case .error: return .error
        }
    }

    func setApplicationAttribute(_ name: String, to value: Bool, pid: Int32) -> Bool {
        AXUIElementSetAttributeValue(AX.application(pid), name as CFString, (value ? kCFBooleanTrue : kCFBooleanFalse)!) == .success
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func bundleID(_ pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    private func element(_ ref: ElementRef) -> AXUIElement? {
        guard let base = ref.object.base as AnyObject? else { return nil }
        return AX.asElement(base).map(AX.prepared)
    }
}
