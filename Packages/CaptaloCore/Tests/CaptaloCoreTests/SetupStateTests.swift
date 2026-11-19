import Testing
@testable import CaptaloCore

@Suite struct SetupStateTests {
    let ready = SetupEnvironment(voice: .ready, accessibilityTrusted: true, readShortcutSet: true)

    @Test func missingReadShortcutRequiresSetup() {
        var env = ready
        env.readShortcutSet = false
        let state = SetupState.evaluate(env)
        #expect(!state.isReady)
        #expect(state.requiredMissing == [.readShortcut])
    }

    @Test func untrustedRequiresAccessibility() {
        var env = ready
        env.accessibilityTrusted = false
        #expect(SetupState.evaluate(env).requiredMissing == [.accessibility])
    }

    @Test func damagedVoiceListedFirst() {
        let env = SetupEnvironment(voice: .damaged, accessibilityTrusted: false, readShortcutSet: false)
        #expect(SetupState.evaluate(env).requiredMissing == [.voice, .accessibility, .readShortcut])
    }

    @Test func checkingVoiceIsPendingNotMissing() {
        var env = ready
        env.voice = .checking
        #expect(SetupState.evaluate(env).isReady)
    }

    @Test func allRequiredPresentIsReady() {
        let state = SetupState.evaluate(ready)
        #expect(state.isReady)
        #expect(state.requiredMissing.isEmpty)
    }

    @Test func missingScreenRecordingDoesNotRequireSetup() {
        let state = SetupState.evaluate(ready)
        #expect(state.isReady)
        #expect(state.optionalMissing == [.screenRecording, .regionShortcut])
    }

    @Test func screenRecordingIsOptionalButRequestedOnRegionPress() {
        #expect(SetupState.evaluate(ready).isReady)
        #expect(SetupState.regionPressRequirement(ready) == .screenRecording)
        var granted = ready
        granted.screenRecordingGranted = true
        #expect(SetupState.regionPressRequirement(granted) == nil)
    }

    @Test func lastVoiceErrorShownButDoesNotBlockReady() {
        var env = ready
        env.lastReadingError = true
        let state = SetupState.evaluate(env)
        #expect(state.isReady)
        #expect(state.showsVoiceError)
    }
}

@Suite struct ShortcutValidationTests {
    @Test func identicalBindingsRejected() {
        let a = ShortcutBinding(keyCode: 15, modifiers: 256)
        #expect(ShortcutValidation.validate(a, other: a) == .identicalToOther)
        #expect(ShortcutValidation.validate(a, other: ShortcutBinding(keyCode: 15, modifiers: 768)) == .accepted)
        #expect(ShortcutValidation.validate(a, other: nil) == .accepted)
    }
}

@Suite struct LoginItemStateTests {
    @Test func enabledShowsOnWithoutText() {
        #expect(LoginItemRow.make(status: .enabled) == LoginItemRow(isOn: true, text: nil, action: .none))
    }

    @Test func notRegisteredShowsOff() {
        #expect(LoginItemRow.make(status: .notRegistered) == LoginItemRow(isOn: false, text: nil, action: .none))
    }

    @Test func requiresApprovalOffersLoginItemsPane() {
        let row = LoginItemRow.make(status: .requiresApproval)
        #expect(row.text == "Approve Cáptalo in System Settings > Login Items")
        #expect(row.action == .openLoginItemsSettings)
        #expect(row.isOn)
    }

    @Test func notFoundOutsideApplicationsExplainsTheFix() {
        let row = LoginItemRow.make(status: .notFound, inApplicationsFolder: false)
        #expect(row.text?.contains("Applications") == true)
        #expect(row.action == .none)
    }

    /// An app in /Applications that never registered also reads `.notFound`
    /// (owner check, 2026-11-19): it must not be told to move.
    @Test func notFoundInsideApplicationsGivesNoMoveAdvice() {
        let row = LoginItemRow.make(status: .notFound, inApplicationsFolder: true)
        #expect(row.text == nil)
        #expect(!row.isOn)
        #expect(row.action == .none)
    }

    @Test func applicationsFolderIsRecognized() {
        let home = "/Users/someone"
        #expect(LoginItemRow.isInApplicationsFolder(bundlePath: "/Applications/Captalo.app", home: home))
        #expect(LoginItemRow.isInApplicationsFolder(bundlePath: "/Users/someone/Applications/Captalo.app", home: home))
        #expect(!LoginItemRow.isInApplicationsFolder(bundlePath: "/Users/someone/Downloads/Captalo.app", home: home))
        #expect(!LoginItemRow.isInApplicationsFolder(bundlePath: "/Applications Old/Captalo.app", home: home))
        #expect(!LoginItemRow.isInApplicationsFolder(bundlePath: "/Applications/Tools/Captalo.app", home: home))
    }

    @Test func registerErrorIsVisible() {
        let row = LoginItemRow.make(status: .notRegistered, registerError: "Operation not permitted")
        #expect(row.text == "Launch at login could not be changed: Operation not permitted")
    }

    @Test func registerErrorKeepsTheApprovalButton() {
        let row = LoginItemRow.make(status: .requiresApproval, registerError: "Operation not permitted")
        #expect(row.action == .openLoginItemsSettings)
        #expect(row.text?.contains("Approve Cáptalo") == true)
        #expect(row.text?.contains("Operation not permitted") == true)
    }

    @Test func everyServiceManagementStatusMaps() {
        #expect(LoginItemStatus(.enabled) == .enabled)
        #expect(LoginItemStatus(.notRegistered) == .notRegistered)
        #expect(LoginItemStatus(.requiresApproval) == .requiresApproval)
        #expect(LoginItemStatus(.notFound) == .notFound)
    }
}
