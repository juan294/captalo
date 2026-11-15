import ApplicationServices
import Testing
@testable import CaptaloCore

/// VAL-02: the per-attribute classification the app's AX reads use, including
/// each entry of a batched `AXUIElementCopyMultipleAttributeValues` read.
@Suite struct AXStatusTests {
    /// Contract probe: the pure constants are the system's `AXError` values.
    @Test func codesMatchTheSystem() {
        #expect(AXStatus.attributeUnsupported == AXError.attributeUnsupported.rawValue)
        #expect(AXStatus.noValue == AXError.noValue.rawValue)
        #expect(AXStatus.parameterizedAttributeUnsupported == AXError.parameterizedAttributeUnsupported.rawValue)
    }

    @Test(arguments: [AXError.attributeUnsupported, .noValue, .parameterizedAttributeUnsupported])
    func absenceCodesAreUnsupported(code: AXError) {
        #expect(isUnsupported(AXStatus.classify(AXRawResult<String>.failed(code.rawValue)) { $0 }))
    }

    @Test(arguments: [AXError.cannotComplete, .failure, .illegalArgument, .invalidUIElement, .apiDisabled,
                      .notImplemented, .actionUnsupported, .notEnoughPrecision])
    func otherCodesAreErrors(code: AXError) {
        #expect(isError(AXStatus.classify(AXRawResult<String>.failed(code.rawValue)) { $0 }))
    }

    /// A success code without a value is not an answer.
    @Test func successWithoutValueIsError() {
        #expect(isError(AXStatus.classify(AXRawResult<String>.failed(AXError.success.rawValue)) { $0 }))
    }

    @Test func nullIsAbsentAndValuesConvert() {
        #expect(isUnsupported(AXStatus.classify(AXRawResult<String>.null) { $0 }))
        guard case .value("c") = AXStatus.classify(AXRawResult<Any>.value("c"), { $0 as? String }) else {
            Issue.record("a string value did not convert"); return
        }
        // A value of the wrong type is unknown, not absent.
        #expect(isError(AXStatus.classify(AXRawResult<Any>.value(3), { $0 as? String })))
    }

    func isUnsupported<T>(_ read: AXRead<T>) -> Bool { if case .unsupported = read { true } else { false } }
    func isError<T>(_ read: AXRead<T>) -> Bool { if case .error = read { true } else { false } }
}
