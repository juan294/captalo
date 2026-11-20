#if DEBUG
import AppKit
import CaptaloCore
import KeyboardShortcuts
import SwiftUI

/// Debug-only launch arguments for the panel (monochrome popover plan, phase 2).
/// Both run before the voice is prepared and end the process themselves.
///
/// - `--render-panel <directory>`: writes every fixture as a PNG, dark and light.
/// - `--panel-recorder-probe`: checks the keycap recorder's swap with the library field.
enum PanelDebugCommands {
    /// True when a debug command took over this launch.
    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--render-panel") {
            guard arguments.indices.contains(flag + 1) else {
                say("render-panel: missing output directory")
                exit(2)
            }
            exit(render(to: URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)))
        }
        if arguments.contains("--panel-recorder-probe") {
            PanelRecorderProbe.shared.start()
            return true
        }
        return false
    }

    /// Command output for the terminal that started the app; this is not app logging.
    static func say(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    /// Draws each fixture at 2x in both appearances. Exit 1 names the fixture that failed.
    static func render(to directory: URL) -> Int32 {
        var failed = false
        for fixture in PanelFixture.all {
            for (suffix, scheme) in [("dark", ColorScheme.dark), ("light", ColorScheme.light)] {
                let name = "\(fixture.name)-\(suffix).png"
                let view = PanelRootView(model: .make(fixture.input), actions: PanelActions(), tab: .constant(fixture.tab))
                    .environment(\.colorScheme, scheme)
                    .environment(\.panelIsRender, true)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.cgImage,
                      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                    say("render-panel: could not render \(name)")
                    failed = true
                    continue
                }
                do {
                    try data.write(to: directory.appending(path: name))
                    say("render-panel: \(name) \(image.width)x\(image.height)")
                } catch {
                    say("render-panel: could not write \(name): \(error.localizedDescription)")
                    failed = true
                }
            }
        }
        return failed ? 1 : 0
    }
}

/// The phase 2 entry probe (owner decision P3): five steps on a probe-only
/// shortcut name, then its defaults key is removed again.
final class PanelRecorderProbe {
    static let shared = PanelRecorderProbe()
    static let name = KeyboardShortcuts.Name("captaloPanelProbe")
    static let defaultsKey = "KeyboardShortcuts_captaloPanelProbe"

    private let controller = KeycapRecorderController(name: PanelRecorderProbe.name)
    private var window: NSWindow?
    private var changes = 0
    private var failures = 0

    func start() {
        Task {
            let code = await run()
            exit(code)
        }
    }

    private func run() async -> Int32 {
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        let slot = KeycapRecorderSlot(controller: controller, keycaps: [], title: "Probe") { [weak self] _ in
            self?.changes += 1
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: slot.padding(40).environment(\.panelTheme, .dark))
        window.center()
        self.window = window
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
        await pause()

        controller.begin()
        await pause()
        check("1 a click on the keycaps makes the recorder the first responder", controller.isRecording)

        post(keyCode: 0x50, flags: [.control, .option, .shift, .function]) // ⌃⌥⇧F19
        await pause()
        let stored = KeyboardShortcuts.getShortcut(for: Self.name)
        check("2 a key-down stores the shortcut, calls onChange once and shows keycaps again",
              stored != nil && changes == 1 && !controller.isRecording)

        controller.begin()
        await pause()
        let recordingBeforeEscape = controller.isRecording
        post(keyCode: 0x35, flags: []) // Esc
        await pause()
        check("3 Esc shows keycaps again and keeps the stored shortcut",
              recordingBeforeEscape && !controller.isRecording
                  && KeyboardShortcuts.getShortcut(for: Self.name) == stored && changes == 1)

        controller.begin()
        await pause()
        let recordingBeforeResign = controller.isRecording
        window.makeFirstResponder(nil)
        await pause()
        check("4 losing the first responder shows keycaps again",
              recordingBeforeResign && !controller.isRecording
                  && KeyboardShortcuts.getShortcut(for: Self.name) == stored)

        post(keyCode: 0x30, flags: []) // Tab
        await pause()
        let responder = window.firstResponder
        check("5 Tab while idle does not give the hidden recorder the keys",
              !controller.isRecording && responder !== controller.field && responder !== controller.field.currentEditor())

        KeyboardShortcuts.reset(Self.name)
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        check("cleanup: the probe's defaults key is gone", UserDefaults.standard.object(forKey: Self.defaultsKey) == nil)
        PanelDebugCommands.say(failures == 0 ? "panel-recorder-probe: passed" : "panel-recorder-probe: \(failures) step(s) failed")
        return failures == 0 ? 0 : 1
    }

    private func check(_ step: String, _ passed: Bool) {
        if !passed { failures += 1 }
        PanelDebugCommands.say("panel-recorder-probe: \(passed ? "ok  " : "FAIL") \(step)")
    }

    private func pause() async {
        try? await Task.sleep(for: .milliseconds(400))
    }

    private func post(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        guard let window, let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode
        ) else { return }
        NSApplication.shared.postEvent(event, atStart: false)
    }
}
#endif
