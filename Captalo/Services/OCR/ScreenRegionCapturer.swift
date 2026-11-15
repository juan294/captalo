import AppKit
import CaptaloCore
import ScreenCaptureKit

/// `RegionCapturer` over ScreenCaptureKit (gate 0 choice): one screenshot of
/// the selected display with Cáptalo's own windows excluded by the content
/// filter, cropped by `sourceRect` and bounded to the display's native
/// scale. The image is never written anywhere.
nonisolated struct ScreenRegionCapturer: RegionCapturer {
    enum CaptureError: Error {
        case displayNotFound
    }

    func capture(_ selection: RegionSelection) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else {
            throw CaptureError.displayNotFound
        }
        let ownBundle = Bundle.main.bundleIdentifier
        let ownApps = content.applications.filter { $0.bundleIdentifier == ownBundle }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = selection.localRect
        configuration.width = Int(selection.pixelSize.width)
        configuration.height = Int(selection.pixelSize.height)
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
