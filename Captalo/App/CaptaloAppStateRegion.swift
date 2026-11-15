import AppKit
import CaptaloCore
import CaptaloOCR
import CoreGraphics

extension CaptaloAppState {
    /// The read-region shortcut (plan phase 5, unit 5C). A region press is a
    /// pending input: it never touches the playing reading; only text that
    /// was recognized successfully replaces it.
    func readRegion() {
        guard pressCanSpeak() else { return }
        refreshScreenRecording()
        if SetupState.regionPressRequirement(setupEnvironment) == .screenRecording {
            // Requested only from a region press or the settings row (owner decision 8).
            if !screenRecordingRequested { requestScreenRecording() }
            onSetupRequired?()
            return
        }
        let reader = regionReader
        let overlay = RegionOverlayController()
        let accessibility = self.accessibility
        let requests = self.requests
        // Ordered at the press, before the source lookup (VAL-01).
        let ticket = requests.reservePress()
        Task.detached {
            let source = accessibility.currentSourceOrNone()
            await requests.submit(ticket, kind: .region, source: source) { token in
                // A newer press cancels this input: the overlay closes as a cancel.
                let result = await withTaskCancellationHandler {
                    await overlay.select()
                } onCancel: {
                    Task { @MainActor in overlay.cancel() }
                }
                let selection: RegionSelection
                switch result {
                case let .selected(selected): selection = selected
                case .cancelled: return .cancelled
                case .escapeUnavailable:
                    let outcome = CaptureOutcome.failed(.overlayUnavailable)
                    PrivacyLog.record(RegionReader.event(for: outcome, elapsed: token.startedAt.duration(to: .now)))
                    // The tap needs Accessibility, so a revoked grant is the likely cause.
                    // Shown in the settings window even while the grant still looks valid.
                    await MainActor.run {
                        let state = CaptaloAppState.shared
                        state.refreshAccessibilityPermission()
                        state.recordRegionOutcome(outcome)
                        state.onSetupRequired?()
                    }
                    return outcome
                }
                let outcome = await reader.read(token, selection)
                await MainActor.run { CaptaloAppState.shared.recordRegionOutcome(outcome) }
                return outcome
            }
        }
    }

    func recordRegionOutcome(_ outcome: CaptureOutcome) {
        ocrFailures.record(outcome)
    }

    /// The failure the optional OCR row shows: recognition failures after
    /// three in a row, an overlay that could not open at once.
    var regionFailureNotice: String? {
        switch ocrFailures.surfacedCategory {
        case .overlayUnavailable?: "The region overlay could not open because Cáptalo could not watch for Esc. Check the Accessibility permission, then try again."
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
        quit()
    }

    nonisolated static func makeRegionReader(requests: RequestCoordinator) -> RegionReader {
        RegionReader(capturer: ScreenRegionCapturer(), recognizer: VisionRecognizer(),
                     isCurrent: { await requests.isCurrent($0) })
    }
}
