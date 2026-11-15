/// What the settings window's optional OCR row reports about region presses:
/// recognition failures after `OcrFailureCounter.threshold`, and at once an
/// overlay that could not open because its Esc tap could not be created.
public struct RegionFailureState: Equatable, Sendable {
    public private(set) var ocr = OcrFailureCounter()
    public private(set) var overlayUnavailable = false

    public init() {}

    public mutating func record(_ outcome: CaptureOutcome) {
        ocr.record(outcome)
        switch outcome {
        case .failed(.overlayUnavailable): overlayUnavailable = true
        // A cancel can come before the overlay opened: it proves nothing.
        case .cancelled: break
        default: overlayUnavailable = false
        }
    }

    /// The failure category to show, or nil.
    public var notice: CaptureFailure? {
        overlayUnavailable ? .overlayUnavailable : ocr.surfacedCategory
    }
}
