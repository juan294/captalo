#if DEBUG
import CaptaloCore

/// The panel states `make panel-render` draws (monochrome popover plan, phase 2).
struct PanelFixture {
    let name: String
    let tab: PanelTab
    let input: PanelInput

    private static let ready = PanelInput(
        environment: SetupEnvironment(
            voice: .ready, accessibilityTrusted: true, readShortcutSet: true,
            screenRecordingGranted: true, regionShortcutSet: true
        ),
        voices: ["af_heart", "af_bella"], voice: "af_heart", speed: 1.0,
        readShortcut: "⌃⌥S", regionShortcut: "⌃⌥A", stopShortcut: "⌃⌥X", loginItem: .make(status: .enabled),
        // Fixed, so a render does not change with the commit it was built from.
        build: BuildLabel(text: "v1.0.0 beta 2", spoken: "Version 1.0.0 beta 2", detail: "Version 1.0.0 beta 2, commit 0a1b2c3")
    )

    private static func changed(_ change: (inout PanelInput) -> Void) -> PanelInput {
        var input = ready
        change(&input)
        return input
    }

    static let all: [PanelFixture] = [
        PanelFixture(name: "read-ready", tab: .read, input: ready),
        PanelFixture(name: "voice-ready", tab: .voice, input: ready),
        PanelFixture(name: "setup-all-set", tab: .setup, input: ready),
        PanelFixture(name: "setup-permission-missing", tab: .setup, input: changed {
            $0.environment.accessibilityTrusted = false
            $0.environment.screenRecordingGranted = false
            $0.loginItem = .make(status: .notRegistered)
        }),
        PanelFixture(name: "read-shortcut-unset", tab: .read, input: changed {
            $0.environment.readShortcutSet = false
            $0.environment.regionShortcutSet = false
            $0.readShortcut = nil
            $0.regionShortcut = nil
            $0.stopShortcut = nil
        }),
        // Every notice at once, each with its longest text (stuck states 7 and 10).
        PanelFixture(name: "read-all-notices", tab: .read, input: changed {
            $0.environment.readShortcutSet = false
            $0.environment.lastReadingError = true
            $0.readShortcut = nil
            $0.shortcutRejection = "Cáptalo already uses that shortcut. Choose another."
            $0.voiceError = "The last reading stopped because of a voice error."
            $0.regionNotice = "The screenshot for the last region reading did not arrive. If macOS asks whether Cáptalo may access your screen, answer it first: region presses do nothing until you do. Then press the region shortcut again."
        }),
        PanelFixture(name: "voice-damaged", tab: .voice, input: changed { $0.environment.voice = .damaged }),
        PanelFixture(name: "setup-recording-requested", tab: .setup, input: changed {
            $0.environment.screenRecordingGranted = false
            $0.screenRecordingRequest = .thisLaunch
            $0.loginItem = .make(status: .requiresApproval)
        }),
    ]
}
#endif
