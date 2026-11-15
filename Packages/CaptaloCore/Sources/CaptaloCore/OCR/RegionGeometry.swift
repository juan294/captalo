import CoreGraphics

/// One display in AppKit global coordinates (origin at the primary
/// display's bottom-left, y up, points).
public struct DisplayInfo: Equatable, Sendable {
    public let id: UInt32
    public let frame: CGRect
    public let scale: CGFloat

    public init(id: UInt32, frame: CGRect, scale: CGFloat) {
        self.id = id
        self.frame = frame
        self.scale = scale
    }
}

/// A selected region ready for capture.
public struct RegionSelection: Equatable, Sendable {
    public let displayID: UInt32
    /// Global, top-left origin, y down, points (CoreGraphics display space).
    public let globalRect: CGRect
    /// Relative to the display's top-left corner, points (ScreenCaptureKit `sourceRect`).
    public let localRect: CGRect
    /// Capture size at the display's native scale (the bound on image size).
    public let pixelSize: CGSize

    public init(displayID: UInt32, globalRect: CGRect, localRect: CGRect, pixelSize: CGSize) {
        self.displayID = displayID
        self.globalRect = globalRect
        self.localRect = localRect
        self.pixelSize = pixelSize
    }
}

/// Coordinate conversion for the region overlay (plan phase 5, unit 5A).
public enum RegionGeometry {
    /// A rectangle smaller than this on either side is a click, not a drag: a cancel.
    public static let minimumSide: CGFloat = 8

    /// The region between `start` and `end` (AppKit global points), clamped to
    /// the display that contains `start`. Nil for a cancel.
    public static func selection(from start: CGPoint, to end: CGPoint, displays: [DisplayInfo]) -> RegionSelection? {
        guard let display = display(containing: start, in: displays),
              let primary = displays.first(where: { $0.frame.origin == .zero }) ?? displays.first else { return nil }
        let clamped = rect(from: start, to: end, clampedTo: display.frame)
        guard !clamped.isNull, clamped.width >= minimumSide, clamped.height >= minimumSide else { return nil }
        let global = topLeft(clamped, primaryHeight: primary.frame.height)
        let displayTopLeft = topLeft(display.frame, primaryHeight: primary.frame.height)
        let local = global.offsetBy(dx: -displayTopLeft.minX, dy: -displayTopLeft.minY)
        return RegionSelection(
            displayID: display.id, globalRect: global, localRect: local,
            pixelSize: CGSize(width: (clamped.width * display.scale).rounded(), height: (clamped.height * display.scale).rounded())
        )
    }

    /// The rectangle between two points, clamped to `frame` (null when outside).
    /// The overlay draws and the capture uses this same rectangle.
    public static func rect(from start: CGPoint, to end: CGPoint, clampedTo frame: CGRect) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
            .intersection(frame)
    }

    /// The display under `point`, edges included: AppKit reports the top row
    /// and right column as `y == maxY` and `x == maxX`.
    public static func display(containing point: CGPoint, in displays: [DisplayInfo]) -> DisplayInfo? {
        displays.first { (point.x >= $0.frame.minX && point.x <= $0.frame.maxX) && (point.y >= $0.frame.minY && point.y <= $0.frame.maxY) }
    }

    /// AppKit (bottom-left, y up) to CoreGraphics global (top-left, y down).
    public static func topLeft(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
