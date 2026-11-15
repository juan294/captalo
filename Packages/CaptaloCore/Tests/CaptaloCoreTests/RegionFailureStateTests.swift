import Testing
@testable import CaptaloCore

@Suite struct RegionFailureStateTests {
    /// The Esc tap could not be created while Accessibility still looks
    /// granted: the press must not fail silently (review of VAL-08).
    @Test func overlayFailureIsNoticedAtOnce() {
        var state = RegionFailureState()
        state.record(.failed(.overlayUnavailable))
        #expect(state.notice == .overlayUnavailable)
        // A cancel proves nothing about the tap; the notice stays.
        state.record(.cancelled)
        #expect(state.notice == .overlayUnavailable)
        // An overlay that opened and read clears it.
        state.record(.document([.paragraph("read")]))
        #expect(state.notice == nil)
    }

    @Test func recognitionFailuresStillNeedThree() {
        var state = RegionFailureState()
        state.record(.failed(.ocrFailed))
        state.record(.failed(.ocrFailed))
        #expect(state.notice == nil)
        state.record(.failed(.ocrTimedOut))
        #expect(state.notice == .ocrTimedOut)
    }

    /// The log line names the failure and carries no text.
    @Test func overlayFailureLogLine() {
        let event = PrivacyEvent.ocr(outcome: .failed, failure: .overlayUnavailable, blocks: 0, characters: 0, elapsed: .milliseconds(3))
        #expect(event.rendered == "ocr outcome=failed failure=overlayUnavailable blocks=0 characters=0 elapsedMs=3")
    }
}
