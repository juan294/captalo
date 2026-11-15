import Testing
@testable import CaptaloCore

@Suite struct PressGateTests {
    /// VAL-10: Accessibility was granted while Cáptalo stayed inactive, so the
    /// cache is still false. The first press must read, not only refresh.
    @Test func firstPressAfterGrantReads() {
        var refreshes = 0
        let decision = PressGate.decide(voice: .ready, cachedTrust: false) { refreshes += 1; return true }
        #expect(decision == .proceed)
        #expect(refreshes == 1)
    }

    @Test func trustedPressDoesNotRefresh() {
        var refreshes = 0
        #expect(PressGate.decide(voice: .ready, cachedTrust: true) { refreshes += 1; return true } == .proceed)
        #expect(refreshes == 0)
    }

    @Test func missingTrustOrVoiceRequiresSetup() {
        #expect(PressGate.decide(voice: .ready, cachedTrust: false) { false } == .requireSetup)
        var refreshes = 0
        // A voice that cannot speak still refreshes the permission row.
        #expect(PressGate.decide(voice: .damaged, cachedTrust: true) { refreshes += 1; return true } == .requireSetup)
        #expect(refreshes == 1)
    }

    @Test func checkingVoiceIgnoresThePress() {
        var refreshes = 0
        #expect(PressGate.decide(voice: .checking, cachedTrust: false) { refreshes += 1; return true } == .ignore)
        #expect(refreshes == 0)
    }
}
