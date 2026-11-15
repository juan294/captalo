import AppKit
import CaptaloCore
import CaptaloOCR
import CoreGraphics

extension CaptaloAppState {
    /// The read-region shortcut (plan phase 5, unit 5C). A region press is a
    /// pending input: it never touches the playing reading; only text that
    /// was recognized successfully replaces it.
    func readRegion() {
        if voiceState == .checking { return }
        if !voiceState.canSpeak || !accessibilityPermissionGranted {
            refreshAccessibilityPermission()
            requireSetup()
            return
        }
        refreshScreenRecording()
        if SetupState.regionPressRequirement(setupEnvironment) == .screenRecording {
            // Requested only from a region press or the settings row (owner decision 8).
            if !screenRecordingRequested {
                screenRecordingRequested = true
                CGRequestScreenCaptureAccess()
            }
            onSetupRequired?()
            return
        }
        let reader = regionReader
        let overlay = RegionOverlayController()
        let accessibility = self.accessibility
        let requests = self.requests
        Task.detached {
            let source = accessibility.currentSource() ?? InputSource(pid: 0, bundleID: nil, focusedElement: nil)
            await requests.submit(kind: .region, source: source) { token in
                // A newer press cancels this input: the overlay closes as a cancel.
                let selection = await withTaskCancellationHandler {
                    await overlay.select()
                } onCancel: {
                    Task { @MainActor in overlay.cancel() }
                }
                guard let selection else { return .cancelled }
                let outcome = await reader.read(token, selection)
                await MainActor.run { CaptaloAppState.shared.recordRegionOutcome(outcome) }
                return outcome
            }
        }
    }

    func recordRegionOutcome(_ outcome: CaptureOutcome) {
        ocrFailures.record(outcome)
    }

    /// The failure category the optional OCR row shows after three consecutive failures.
    var regionFailureNotice: String? {
        switch ocrFailures.surfacedCategory {
        case .ocrTimedOut?: "Recent region readings timed out."
        case .ocrFailed?: "Recent region readings could not be recognized."
        default: nil
        }
    }

    func refreshScreenRecording() {
        let granted = CGPreflightScreenCaptureAccess()
        if granted != screenRecordingGranted { screenRecordingGranted = granted }
    }

    /// The settings row's button.
    func requestScreenRecording() {
        screenRecordingRequested = true
        CGRequestScreenCaptureAccess()
        refreshScreenRecording()
    }

    /// macOS may apply a new Screen Recording grant only after a relaunch.
    func quitAndReopen() {
        let path = Bundle.main.bundlePath
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? relaunch.run()
        NSApplication.shared.terminate(nil)
    }

    nonisolated static func makeRegionReader(requests: RequestCoordinator) -> RegionReader {
        RegionReader(capturer: ScreenRegionCapturer(), recognizer: VisionRecognizer(),
                     isCurrent: { await requests.isCurrent($0) })
    }
}
