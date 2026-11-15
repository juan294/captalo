import CoreGraphics
import Testing
@testable import CaptaloCore

@Suite struct RegionGeometryTests {
    let primary = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), scale: 2)

    @Test func bottomLeftToTopLeftOnPrimary() throws {
        let selection = try #require(RegionGeometry.selection(from: CGPoint(x: 100, y: 900), to: CGPoint(x: 300, y: 800), displays: [primary]))
        #expect(selection.globalRect == CGRect(x: 100, y: 82, width: 200, height: 100))
        #expect(selection.localRect == selection.globalRect)
        #expect(selection.displayID == 1)
    }

    @Test func secondaryDisplayLeftOfPrimary() throws {
        let left = DisplayInfo(id: 2, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080), scale: 1)
        let selection = try #require(RegionGeometry.selection(from: CGPoint(x: -1820, y: 1000), to: CGPoint(x: -1620, y: 900), displays: [primary, left]))
        #expect(selection.displayID == 2)
        // Global top-left uses the primary height; local is relative to the display's own top-left.
        #expect(selection.globalRect == CGRect(x: -1820, y: -18, width: 200, height: 100))
        #expect(selection.localRect == CGRect(x: 100, y: 80, width: 200, height: 100))
    }

    @Test func secondaryDisplayAbove() throws {
        let above = DisplayInfo(id: 3, frame: CGRect(x: 0, y: 982, width: 2560, height: 1440), scale: 1)
        let selection = try #require(RegionGeometry.selection(from: CGPoint(x: 10, y: 2400), to: CGPoint(x: 110, y: 2300), displays: [primary, above]))
        #expect(selection.displayID == 3)
        #expect(selection.globalRect == CGRect(x: 10, y: -1418, width: 100, height: 100))
        #expect(selection.localRect == CGRect(x: 10, y: 22, width: 100, height: 100))
    }

    @Test func retinaAndNonRetinaMixed() throws {
        let external = DisplayInfo(id: 2, frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), scale: 1)
        let retina = try #require(RegionGeometry.selection(from: CGPoint(x: 10, y: 500), to: CGPoint(x: 110, y: 450), displays: [primary, external]))
        let plain = try #require(RegionGeometry.selection(from: CGPoint(x: 1600, y: 500), to: CGPoint(x: 1700, y: 450), displays: [primary, external]))
        #expect(retina.pixelSize == CGSize(width: 200, height: 100))
        #expect(plain.pixelSize == CGSize(width: 100, height: 50))
    }

    @Test func zeroSizeRectIsCancel() {
        #expect(RegionGeometry.selection(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 50, y: 50), displays: [primary]) == nil)
        #expect(RegionGeometry.selection(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 57, y: 300), displays: [primary]) == nil)
    }

    @Test func crossDisplayDragClampedToStartDisplay() throws {
        let external = DisplayInfo(id: 2, frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), scale: 1)
        let selection = try #require(RegionGeometry.selection(from: CGPoint(x: 1400, y: 500), to: CGPoint(x: 1800, y: 400), displays: [primary, external]))
        #expect(selection.displayID == 1)
        #expect(selection.globalRect.maxX == 1512)
    }
}
