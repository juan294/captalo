import CaptaloCore
import Foundation

extension CaptaloAppState {
    /// The read-selection shortcut (plan phase 2). The press records its
    /// source at once; trust, capture and the stop gesture run in the coordinators.
    func speakSelection() {
        if !isCaptureProbeActive, !canSpeak {
            onVoiceAttentionRequired?()
            return
        }
        lastReadingError = nil
        let capture = selectionCapture
        let accessibility = self.accessibility
        let requests = self.requests
        // The source is read off the main actor: a hung app cannot block the UI.
        // Without Accessibility trust there is no source; the coordinator then
        // returns .permissionMissing before any layer runs.
        Task.detached {
            let source = accessibility.currentSource() ?? InputSource(pid: 0, bundleID: nil, focusedElement: nil)
            await requests.submit(kind: .selection, source: source) { token in
                let outcome = await capture(token)
                if outcome == .permissionMissing {
                    await MainActor.run { CaptaloAppState.shared.refreshAccessibilityPermission() }
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
