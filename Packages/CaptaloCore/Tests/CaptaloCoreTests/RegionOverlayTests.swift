import CoreGraphics
import Testing
@testable import CaptaloCore

@Suite struct RegionOverlayTests {
    let display = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), scale: 2)

    func tracker() -> (RegionSelectionTracker, () -> [RegionSelection?]) {
        var results: [RegionSelection?] = []
        let tracker = RegionSelectionTracker(displays: [display]) { results.append($0) }
        return (tracker, { results })
    }

    @Test func screenChangeCancels() {
        let (tracker, results) = tracker()
        tracker.handle(.mouseDown(CGPoint(x: 10, y: 10)))
        tracker.handle(.mouseDragged(CGPoint(x: 300, y: 200)))
        tracker.handle(.screensChanged)
        #expect(results().count == 1)
        #expect(results().first! == nil)
        #expect(tracker.dragRect == nil)
        tracker.handle(.mouseUp(CGPoint(x: 300, y: 200)))
        #expect(results().count == 1) // finished exactly once
    }

    @Test func dragReturnsSelection() {
        let (tracker, results) = tracker()
        tracker.handle(.mouseDown(CGPoint(x: 100, y: 900)))
        tracker.handle(.mouseDragged(CGPoint(x: 300, y: 800)))
        #expect(tracker.dragRect == CGRect(x: 100, y: 800, width: 200, height: 100))
        tracker.handle(.mouseUp(CGPoint(x: 300, y: 800)))
        #expect(results().first??.globalRect == CGRect(x: 100, y: 82, width: 200, height: 100))
    }

    /// The drawn rectangle matches the capture: clamped to the start display.
    @Test func dragRectIsClampedToStartDisplay() {
        let external = DisplayInfo(id: 2, frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), scale: 1)
        let tracker = RegionSelectionTracker(displays: [display, external]) { _ in }
        tracker.handle(.mouseDown(CGPoint(x: 1400, y: 500)))
        tracker.handle(.mouseDragged(CGPoint(x: 1800, y: 400)))
        #expect(tracker.dragRect == CGRect(x: 1400, y: 400, width: 112, height: 100))
    }

    @Test func escapeClickAndSupersededCancel() {
        for events: [RegionSelectionTracker.Event] in [
            [.mouseDown(CGPoint(x: 10, y: 10)), .escape],
            [.mouseDown(CGPoint(x: 10, y: 10)), .mouseUp(CGPoint(x: 10, y: 10))],
            [.escape],
            [.superseded],
            [.mouseUp(CGPoint(x: 5, y: 5))],
        ] {
            let (tracker, results) = tracker()
            events.forEach(tracker.handle)
            #expect(results().count == 1)
            #expect(results().first! == nil)
            #expect(tracker.isFinished)
        }
    }
}
