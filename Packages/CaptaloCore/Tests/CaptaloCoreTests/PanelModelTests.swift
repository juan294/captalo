import Testing
@testable import CaptaloCore

@Suite struct PanelModelTests {
    /// Everything set up: voice ready, both permissions, both shortcuts.
    static let ready = PanelInput(
        environment: SetupEnvironment(
            voice: .ready, accessibilityTrusted: true, readShortcutSet: true,
            screenRecordingGranted: true, regionShortcutSet: true
        ),
        voices: ["af_heart", "af_bella"], voice: "af_heart", speed: 1.0,
        readShortcut: "⌥P", regionShortcut: "⌥O"
    )

    func model(_ change: (inout PanelInput) -> Void = { _ in }) -> PanelModel {
        var input = Self.ready
        change(&input)
        return PanelModel.make(input)
    }

    // MARK: Pills

    @Test func readyShowsPositivePills() {
        let model = model()
        #expect(model.pill(for: .read) == PanelPill(text: "Ready", kind: .positive))
        #expect(model.pill(for: .voice) == PanelPill(text: "Installed", kind: .positive))
        #expect(model.pill(for: .setup) == PanelPill(text: "All set", kind: .positive))
        #expect(model.attention.isEmpty)
        #expect(model.initialTab == .read)
    }

    @Test func anyRequiredItemMissingMakesReadNeedSetup() {
        #expect(model { $0.environment.accessibilityTrusted = false }.pill(for: .read)
            == PanelPill(text: "Needs setup", kind: .neutral))
        #expect(model { $0.environment.readShortcutSet = false }.pill(for: .read)
            == PanelPill(text: "Needs setup", kind: .neutral))
        #expect(model { $0.environment.voice = .damaged }.pill(for: .read)
            == PanelPill(text: "Needs setup", kind: .neutral))
    }

    @Test func voicePillFollowsInstallState() {
        #expect(model { $0.environment.voice = .checking }.pill(for: .voice) == PanelPill(text: "Preparing", kind: .pending))
        for state in [VoiceInstallState.damaged, .bundleInvalid, .installFailed(needBytes: 1), .failed] {
            #expect(model { $0.environment.voice = state }.pill(for: .voice)
                == PanelPill(text: "Needs attention", kind: .neutral))
        }
    }

    // MARK: Stuck states

    @Test func accessibilityMissingOpensSetup() {
        let model = model { $0.environment.accessibilityTrusted = false }
        #expect(model.initialTab == .setup)
        #expect(model.attention == [.setup])
        #expect(model.pill(for: .setup) == PanelPill(text: "1 step left", kind: .neutral))
        let row = model.setup.accessibility
        #expect(row.state == .action(label: "Open Accessibility Settings"))
        #expect(row.needsAttention)
        #expect(row.detail == "Cáptalo cannot read your selection until you allow this in System Settings.")
    }

    @Test func grantedAccessibilityIsAllowed() {
        let row = model().setup.accessibility
        #expect(row.state == .allowed)
        #expect(!row.needsAttention)
    }

    @Test func voiceStatesShowRepair() {
        let cases: [(VoiceInstallState, String, String?)] = [
            (.damaged, "Voice files are damaged. Reinstall voice.", "Reinstall voice"),
            (.failed, "The voice could not start.", "Reinstall voice"),
            (.installFailed(needBytes: 95_000_001), "Cáptalo needs 96 MB free to install its voice.", "Retry"),
            (.bundleInvalid, "The voice in this copy of Cáptalo is damaged. Reinstall Cáptalo.", nil),
        ]
        for (state, status, repair) in cases {
            let model = model { $0.environment.voice = state }
            #expect(model.voice.status == status)
            #expect(model.voice.repairLabel == repair)
            #expect(!model.voice.isChecking)
            #expect(model.voice.voices.isEmpty, "voices are offered only when the voice is ready")
            #expect(model.initialTab == .voice)
            #expect(model.attention.contains(.voice))
        }
    }

    @Test func checkingVoiceIsPendingNotMissing() {
        let model = model { $0.environment.voice = .checking }
        #expect(model.voice.isChecking)
        #expect(model.voice.status == "Preparing local voice...")
        #expect(model.voice.repairLabel == nil)
        #expect(model.attention.isEmpty)
        #expect(model.initialTab == .read)
        #expect(model.pill(for: .read) == PanelPill(text: "Ready", kind: .positive))
    }

    @Test func readyVoiceListsVoicesWithTheOneInUse() {
        let voice = model { $0.voice = "af_bella" }.voice
        #expect(voice.status == nil)
        #expect(voice.voices == [
            VoiceCard(id: "af_heart", name: "Heart", inUse: false),
            VoiceCard(id: "af_bella", name: "Bella", inUse: true),
        ])
    }

    @Test func readShortcutNoticeVariants() {
        let set = model()
        #expect(set.read.shortcutNotice == "If this shortcut does nothing, another app may use it; choose another.")
        #expect(set.read.selection.keycaps == ["⌥", "P"])

        let unset = model { $0.environment.readShortcutSet = false; $0.readShortcut = nil }
        #expect(unset.read.shortcutNotice
            == "Choose a shortcut to read the selected text: click Record, then hold ⌘, ⌥ or ⌃ and press a key.")
        #expect(unset.read.selection.keycaps.isEmpty)
        #expect(unset.initialTab == .read)
        #expect(unset.attention == [.read])

        // The app clears a rejected read shortcut, so the rejection arrives with the shortcut unset.
        let rejection = "That shortcut is already used by Cáptalo's other shortcut; choose another."
        let rejected = model {
            $0.environment.readShortcutSet = false
            $0.readShortcut = nil
            $0.shortcutRejection = rejection
        }
        #expect(rejected.read.shortcutNotice == rejection)
        #expect(model { $0.shortcutRejection = rejection }.read.shortcutNotice == rejection)
    }

    @Test func screenRecordingRequestedOffersReopen() {
        let missing = model { $0.environment.screenRecordingGranted = false }.setup.screenRecording
        #expect(missing.state == .action(label: "Allow"))
        #expect(missing.secondaryAction == nil)
        #expect(missing.detail == "Optional. Only for Read region")

        let requested = model {
            $0.environment.screenRecordingGranted = false
            $0.screenRecordingRequested = true
        }.setup.screenRecording
        #expect(requested.state == .action(label: "Allow"))
        #expect(requested.detail == "If you allowed it and region reading still does nothing, macOS needs Cáptalo to reopen.")
        #expect(requested.secondaryAction == "Quit and reopen")

        let granted = model { $0.screenRecordingRequested = true }.setup.screenRecording
        #expect(granted.state == .allowed)
        #expect(granted.secondaryAction == nil)
    }

    @Test func noticesSurfaceOnRead() {
        let model = model {
            $0.voiceError = "The last reading stopped because of a voice error."
            $0.regionNotice = "Recent region readings timed out."
        }
        #expect(model.read.voiceError == "The last reading stopped because of a voice error.")
        #expect(model.read.regionNotice == "Recent region readings timed out.")
        #expect(model.attention == [.read])
        #expect(model.initialTab == .read)
        // A notice never blocks: the reader is still ready.
        #expect(model.pill(for: .read) == PanelPill(text: "Ready", kind: .positive))
    }

    @Test func eachNoticeAloneRaisesTheReadDot() {
        let voiceOnly = model { $0.voiceError = "The last reading stopped because of a voice error." }
        #expect(voiceOnly.attention == [.read])
        #expect(voiceOnly.read.regionNotice == nil)
        let regionOnly = model { $0.regionNotice = "Recent region readings timed out." }
        #expect(regionOnly.attention == [.read])
        #expect(regionOnly.read.voiceError == nil)
    }

    @Test func loginItemRowCarriesTextAndAction() {
        let row = LoginItemRow.make(status: .requiresApproval)
        let setup = model { $0.loginItem = row }.setup
        #expect(setup.loginItem == row)
        #expect(setup.loginItem.text == "Approve Cáptalo in System Settings > Login Items")
        #expect(setup.loginItem.action == .openLoginItemsSettings)
    }

    @Test func optionalItemsNeverRaiseADot() {
        let model = model {
            $0.environment.screenRecordingGranted = false
            $0.environment.regionShortcutSet = false
            $0.regionShortcut = nil
        }
        #expect(model.attention.isEmpty)
        #expect(model.initialTab == .read)
        #expect(model.pill(for: .setup) == PanelPill(text: "All set", kind: .positive))
        #expect(model.pill(for: .read) == PanelPill(text: "Ready", kind: .positive))
        #expect(model.read.region.keycaps.isEmpty)
    }

    @Test func firstRequiredMissingItemDecidesTheTab() {
        // Order: voice, Accessibility, read shortcut (SetupState).
        let all = model {
            $0.environment.voice = .damaged
            $0.environment.accessibilityTrusted = false
            $0.environment.readShortcutSet = false
        }
        #expect(all.initialTab == .voice)
        #expect(all.attention == [.read, .voice, .setup])
        let two = model {
            $0.environment.accessibilityTrusted = false
            $0.environment.readShortcutSet = false
        }
        #expect(two.initialTab == .setup)
    }

    // MARK: Read pane values

    @Test func speedStepsMarkTheSelectedOne() {
        let steps = model { $0.speed = 1.15 }.read.speedSteps
        #expect(steps.map(\.label) == ["0.75×", "0.85×", "1.00×", "1.15×", "1.25×", "1.35×"])
        #expect(steps.map(\.value) == ReadingPreferences.speedSteps)
        #expect(steps.filter(\.selected).map(\.label) == ["1.15×"])
    }

    @Test func offStepSpeedSelectsTheNearestStep() {
        let steps = model { $0.speed = 1.1 }.read.speedSteps
        #expect(steps.filter(\.selected).count == 1)
        #expect(steps.filter(\.selected).map(\.value) == [ReadingPreferences.snap(1.1)])
    }

    @Test func readPaneNamesTheVoiceInUse() {
        #expect(model { $0.voice = "af_bella" }.read.voiceName == "Bella")
    }
}

@Suite struct VoiceDisplayTests {
    @Test func dropsThePrefixAndCapitalizes() {
        #expect(VoiceDisplay.name(for: "af_heart") == "Heart")
        #expect(VoiceDisplay.name(for: "af_bella") == "Bella")
        #expect(VoiceDisplay.name(for: "bm_george_v2") == "George_v2")
    }

    @Test func idWithoutPrefixIsCapitalized() {
        #expect(VoiceDisplay.name(for: "nova") == "Nova")
    }

    @Test func emptyNameFallsBackToTheId() {
        #expect(VoiceDisplay.name(for: "af_") == "af_")
        #expect(VoiceDisplay.name(for: "") == "")
    }
}

@Suite struct ShortcutKeycapsTests {
    @Test func oneKeycapPerModifierThenTheKey() {
        #expect(ShortcutKeycaps.labels(description: "⌥P") == ["⌥", "P"])
        #expect(ShortcutKeycaps.labels(description: "⌃⌥⇧⌘F5") == ["⌃", "⌥", "⇧", "⌘", "F5"])
        #expect(ShortcutKeycaps.labels(description: "⌘Space") == ["⌘", "Space"])
    }

    @Test func keyWithoutModifierIsOneKeycap() {
        #expect(ShortcutKeycaps.labels(description: "F19") == ["F19"])
    }

    @Test func emptyDescriptionHasNoKeycaps() {
        #expect(ShortcutKeycaps.labels(description: "").isEmpty)
        #expect(ShortcutKeycaps.labels(description: nil).isEmpty)
    }

    @Test func functionModifierIsItsOwnKeycap() {
        #expect(ShortcutKeycaps.labels(description: "⌥🌐\u{FE0E}P") == ["⌥", "🌐\u{FE0E}", "P"])
        #expect(ShortcutKeycaps.labels(description: "🌐P") == ["🌐", "P"])
    }

    @Test func modifiersAloneStayModifiers() {
        #expect(ShortcutKeycaps.labels(description: "⌃⌥") == ["⌃", "⌥"])
    }
}

@Suite struct SpeedLabelTests {
    @Test func labelHasTwoDecimalsAndAMultiplicationSign() {
        #expect(ReadingPreferences.label(for: 1.0) == "1.00×")
        #expect(ReadingPreferences.label(for: 0.75) == "0.75×")
        #expect(ReadingPreferences.label(for: 1.35) == "1.35×")
    }
}

@Suite struct VoiceInstallStateTextTests {
    @Test func everyStateHasItsText() {
        #expect(VoiceInstallState.checking.statusText == "Preparing local voice...")
        #expect(VoiceInstallState.ready.statusText == "Voice ready")
        #expect(VoiceInstallState.damaged.statusText == "Voice files are damaged. Reinstall voice.")
        #expect(VoiceInstallState.bundleInvalid.statusText == "The voice in this copy of Cáptalo is damaged. Reinstall Cáptalo.")
        #expect(VoiceInstallState.installFailed(needBytes: 1).statusText == "Cáptalo needs 1 MB free to install its voice.")
        #expect(VoiceInstallState.failed.statusText == "The voice could not start.")
    }

    @Test func onlyRepairableStatesHaveARepairLabel() {
        #expect(VoiceInstallState.damaged.repairLabel == "Reinstall voice")
        #expect(VoiceInstallState.failed.repairLabel == "Reinstall voice")
        #expect(VoiceInstallState.installFailed(needBytes: 1).repairLabel == "Retry")
        #expect(VoiceInstallState.checking.repairLabel == nil)
        #expect(VoiceInstallState.ready.repairLabel == nil)
        #expect(VoiceInstallState.bundleInvalid.repairLabel == nil)
    }
}
