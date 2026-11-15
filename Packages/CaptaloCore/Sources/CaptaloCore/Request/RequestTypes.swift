import CryptoKit
import Foundation

/// An opaque reference to the focused accessibility element at press time.
/// The app wraps an `AXUIElement`; tests use any hashable value.
public struct ElementRef: Hashable, @unchecked Sendable {
    public let object: AnyHashable

    public init(_ object: AnyHashable) {
        self.object = object
    }
}

public enum InputKind: String, Sendable {
    case selection
    case region
}

/// Where a press came from, recorded when the shortcut fires.
public struct InputSource: Hashable, Sendable {
    public let pid: Int32
    public let bundleID: String?
    public let focusedElement: ElementRef?

    public init(pid: Int32, bundleID: String?, focusedElement: ElementRef?) {
        self.pid = pid
        self.bundleID = bundleID
        self.focusedElement = focusedElement
    }
}

public struct InputToken: Hashable, Sendable {
    public let inputGeneration: UInt64
    public let kind: InputKind
    public let source: InputSource
    public let startedAt: ContinuousClock.Instant
}

public struct SessionToken: Hashable, Sendable {
    public let sessionGeneration: UInt64
}

public enum CaptureLayerKind: String, Sendable {
    case accessibility
    case menuCopy
    case syntheticCopy
    case ocr
}

public enum UnsupportedReason: String, Sendable {
    /// Copy can produce content without a selection in this app (CopyPolicy).
    case copyMayNotReflectSelection
    /// The shortcut's modifiers were still held after 500 ms.
    case modifiersHeld
}

public enum CaptureFailure: String, Sendable {
    case notPreservable
    case ownershipUncertain
    case noCopyResult
    case restoreFailed
    case sourceChanged
    case noText
    case ocrTimedOut
    case ocrFailed
}

public enum CaptureOutcome: Equatable, Sendable {
    case text(String, layer: CaptureLayerKind)
    case nothingSelected
    case unsupported(UnsupportedReason)
    case permissionMissing
    case cancelled
    case failed(CaptureFailure)
}

/// The identity of a reading: a hash of the captured text, so the stop
/// gesture compares what was captured, never what was spoken.
public struct ReadingIdentity: Hashable, Sendable {
    public let digest: Data

    public init(capturedText: String) {
        digest = Data(SHA256.hash(data: Data(capturedText.utf8)))
    }
}
