import CoreGraphics

/// The overlay's selection logic (plan phase 5, unit 5A), independent of
/// AppKit. Every exit (drag end, Esc, click without drag, a rectangle under
/// 8 × 8 points, a display change, a superseded input) calls `finish`
/// exactly once; the overlay tears down in that callback.
public final class RegionSelectionTracker {
    public enum Event: Equatable, Sendable {
        case mouseDown(CGPoint)
        case mouseDragged(CGPoint)
        case mouseUp(CGPoint)
        case escape
        case screensChanged
        case superseded
    }

    private let displays: [DisplayInfo]
    private var finish: ((RegionSelection?) -> Void)?
    private var start: CGPoint?
    /// The rectangle to draw (AppKit global points), while dragging.
    public private(set) var dragRect: CGRect?

    public init(displays: [DisplayInfo], finish: @escaping (RegionSelection?) -> Void) {
        self.displays = displays
        self.finish = finish
    }

    public var isFinished: Bool { finish == nil }

    public func handle(_ event: Event) {
        guard !isFinished else { return }
        switch event {
        case let .mouseDown(point):
            start = point
            dragRect = CGRect(origin: point, size: .zero)
        case let .mouseDragged(point):
            guard let start else { return }
            dragRect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                              width: abs(point.x - start.x), height: abs(point.y - start.y))
        case let .mouseUp(point):
            guard let start else { return complete(nil) }
            complete(RegionGeometry.selection(from: start, to: point, displays: displays))
        case .escape, .screensChanged, .superseded:
            complete(nil)
        }
    }

    private func complete(_ selection: RegionSelection?) {
        let finish = self.finish
        self.finish = nil
        dragRect = nil
        finish?(selection)
    }
}
