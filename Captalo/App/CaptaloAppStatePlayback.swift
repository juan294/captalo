import CaptaloCore
import Foundation

extension CaptaloAppState {
    /// The gate both shortcuts share. A press while the voice is still being
    /// prepared at launch is ignored (not a failure). The shortcut fired, so it
    /// is set: a failed press means the voice or the Accessibility permission.
    func pressCanSpeak() -> Bool {
        if voiceState == .checking { return false }
        if !voiceState.canSpeak || !accessibilityPermissionGranted {
            refreshAccessibilityPermission()
            requireSetup()
            return false
        }
        return true
    }

    /// The read-selection shortcut (plan phase 2). The press records its
    /// source at once; trust, capture and the stop gesture run in the coordinators.
    func speakSelection() {
        if !isCaptureProbeActive, !pressCanSpeak() { return }
        if lastReadingError != nil { lastReadingError = nil }
        let capture = selectionCapture
        let accessibility = self.accessibility
        let requests = self.requests
        // The source is read off the main actor: a hung app cannot block the UI.
        // Without Accessibility trust there is no source; the coordinator then
        // returns .permissionMissing before any layer runs.
        Task.detached {
            let source = accessibility.currentSourceOrNone()
            await requests.submit(kind: .selection, source: source) { token in
                let outcome = await capture(token)
                if outcome == .permissionMissing {
                    await MainActor.run {
                        CaptaloAppState.shared.refreshAccessibilityPermission()
                        CaptaloAppState.shared.requireSetup()
                    }
                }
                return outcome
            }
        }
    }

    var isCaptureProbeActive: Bool {
        #if DEBUG
        captureProbe != nil
        #else
        false
        #endif
    }
}
