/// A raw Accessibility result before classification: an attribute value,
/// a null value, or a failed call's `AXError` raw code.
public enum AXRawResult<Raw> {
    case value(Raw)
    case null
    case failed(Int32)
}

/// The one AX error policy (VAL-02), without ApplicationServices. Only an
/// attribute the element does not support, or one with no value, is an
/// established absence; every other failure (cannot complete, timeout,
/// invalid element, API disabled) is unknown.
public enum AXStatus {
    /// `AXError` raw values; `AXStatusTests` pins them to the system's.
    public static let attributeUnsupported: Int32 = -25205
    public static let noValue: Int32 = -25212
    public static let parameterizedAttributeUnsupported: Int32 = -25213

    public static func isEstablishedAbsence(_ code: Int32) -> Bool {
        code == attributeUnsupported || code == noValue || code == parameterizedAttributeUnsupported
    }

    public static func classify<Raw, Value>(_ raw: AXRawResult<Raw>, _ convert: (Raw) -> Value?) -> AXRead<Value> {
        switch raw {
        case let .value(value):
            guard let converted = convert(value) else { return .error }
            return .value(converted)
        case .null:
            return .unsupported
        case let .failed(code):
            return isEstablishedAbsence(code) ? .unsupported : .error
        }
    }
}
