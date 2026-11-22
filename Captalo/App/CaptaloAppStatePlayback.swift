import CaptaloCore
import Foundation

extension CaptaloAppState {
    func stopReading() {
        let requests = self.requests
        let ticket = requests.reserveStop()
        Task { await requests.stopReading(ticket) }
    }

    /// The gate both shortcuts share. A press while the voice is still being
    /// prepared at launch is ignored (not a failure). The shortcut fired, so it
    /// is set: a failed press means the voice or the Accessibility permission.
    func pressCanSpeak() -> Bool {
        let decision = PressGate.decide(voice: voiceState, cachedTrust: accessibilityPermissionGranted) {
            refreshAccessibilityPermission()
            return accessibilityPermissionGranted
        }
        switch decision {
        case .ignore: return false
        case .requireSetup:
            requireSetup()
            return false
        case .proceed: return true
        }
    }

    /// The read-selection shortcut (plan phase 2). The press records its
    /// source at once; trust, capture and the stop gesture run in the coordinators.
    func speakSelection() {
        if !isCaptureProbeActive, !pressCanSpeak() { return }
        if lastReadingError != nil { lastReadingError = nil }
        let capture = selectionCapture
        let accessibility = self.accessibility
        let requests = self.requests
        // The press takes its place in order now; a slower lookup of an older
        // press then has no effect (VAL-01).
        let ticket = requests.reservePress()
        // The source is read off the main actor: a hung app cannot block the UI.
        // Without Accessibility trust there is no source; the coordinator then
        // returns .permissionMissing before any layer runs.
        Task.detached {
            let source = accessibility.currentSourceOrNone()
            await requests.submit(ticket, kind: .selection, source: source) { token in
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
