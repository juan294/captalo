import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

/// Owns the library's recorder field for one shortcut and knows whether it is
/// recording. Recording is the field being the window's first responder
/// (itself or its field editor); the library ends it on a recorded shortcut,
/// Esc, a click elsewhere, or a window that stops being key.
final class KeycapRecorderController: ObservableObject {
    @Published private(set) var isRecording = false
    var onChange: (KeyboardShortcuts.Shortcut?) -> Void = { _ in }
    private let name: KeyboardShortcuts.Name
    private var observation: NSKeyValueObservation?
    private weak var observedWindow: NSWindow?

    /// Idle, the field refuses the first responder: it is invisible then, and
    /// a Tab or a stray click must not start a recording nobody can see.
    private(set) lazy var field: KeyboardShortcuts.RecorderCocoa = {
        let field = KeyboardShortcuts.RecorderCocoa(for: name) { [weak self] shortcut in
            self?.onChange(shortcut)
        }
        field.refusesFirstResponder = true
        return field
    }()

    init(name: KeyboardShortcuts.Name) {
        self.name = name
    }

    /// Starts recording: the field takes the keys until the library ends it.
    func begin() {
        guard let window = field.window else { return }
        observe(window)
        field.refusesFirstResponder = false
        window.makeFirstResponder(field)
        refresh()
    }

    /// Follows the window's first responder, the one fact that says whether the field records.
    func observe(_ window: NSWindow) {
        guard observedWindow !== window else { return }
        observedWindow = window
        observation = window.observe(\.firstResponder) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let responder = field.window?.firstResponder
        let editor = field.currentEditor()
        let recording = responder === field || (editor != nil && responder === editor)
        if !recording { field.refusesFirstResponder = true }
        if recording != isRecording { isRecording = recording }
    }
}

/// The shortcut as keycaps. A click swaps in the library's recorder field in
/// the same place until recording ends (owner decision P3): the library's
/// conflict checks stay the only path that stores a shortcut.
struct KeycapRecorder: View {
    /// Keeps the name it was created with; each shortcut card has a fixed name.
    @StateObject private var controller: KeycapRecorderController
    let keycaps: [String]
    let title: String
    let onChange: (KeyboardShortcuts.Shortcut?) -> Void

    init(name: KeyboardShortcuts.Name, keycaps: [String], title: String,
         onChange: @escaping (KeyboardShortcuts.Shortcut?) -> Void) {
        _controller = StateObject(wrappedValue: KeycapRecorderController(name: name))
        self.keycaps = keycaps
        self.title = title
        self.onChange = onChange
    }

    var body: some View {
        KeycapRecorderSlot(controller: controller, keycaps: keycaps, title: title, onChange: onChange)
    }
}

/// The slot itself, with an injected controller (the recorder probe drives one directly).
struct KeycapRecorderSlot: View {
    @Environment(\.panelTheme) private var theme
    @ObservedObject var controller: KeycapRecorderController
    let keycaps: [String]
    let title: String
    let onChange: (KeyboardShortcuts.Shortcut?) -> Void

    var body: some View {
        Button(action: controller.begin) {
            KeycapsLabel(keycaps: keycaps)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(controller.isRecording ? 0 : 1)
        .accessibilityLabel("Change the \(title) shortcut")
        .accessibilityValue(keycaps.isEmpty ? "Not set" : keycaps.joined(separator: " "))
        // The field is always in the view tree so it can take focus; it is
        // visible, and covers the caption beside it, only while it records.
        .overlay(alignment: .trailing) {
            RecorderFieldHost(controller: controller, onChange: onChange)
                .frame(width: 136, height: 24)
                .padding(.vertical, 10)
                .padding(.leading, 8)
                .background(theme.card)
                .opacity(controller.isRecording ? 1 : 0)
                .allowsHitTesting(controller.isRecording)
                .accessibilityHidden(!controller.isRecording)
        }
    }
}

struct RecorderFieldHost: NSViewRepresentable {
    let controller: KeycapRecorderController
    let onChange: (KeyboardShortcuts.Shortcut?) -> Void

    func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
        controller.onChange = onChange
        return controller.field
    }

    func updateNSView(_ field: KeyboardShortcuts.RecorderCocoa, context: Context) {
        controller.onChange = onChange
        // Follow the window from the start, not only from the first click.
        if let window = field.window { controller.observe(window) }
    }
}
