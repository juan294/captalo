import CaptaloCore
import KeyboardShortcuts
import SwiftUI

/// The one settings window (plan phase 4; assessment §7).
struct SettingsView: View {
    @EnvironmentObject private var state: CaptaloAppState

    var body: some View {
        Form {
            Section("Reading") {
                LabeledContent("Read selection") {
                    KeyboardShortcuts.Recorder(for: .readSelection) { state.readShortcutChanged($0) }
                }
                if let notice = state.shortcutNotice {
                    Text(notice).font(.caption).foregroundStyle(.secondary)
                }
                voiceRow
                LabeledContent("Speed") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Slider(value: speedIndex, in: 0...Double(ReadingPreferences.speedSteps.count - 1), step: 1)
                            .frame(width: 180)
                        Text("\(state.speed, specifier: "%.2f")x, from the next reading")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Setup") {
                LabeledContent("Accessibility") {
                    if state.accessibilityPermissionGranted {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Open Accessibility Settings", action: state.openAccessibilitySettings)
                    }
                }
                LabeledContent("Launch at login") {
                    VStack(alignment: .trailing, spacing: 4) {
                        Toggle("", isOn: Binding(get: { state.loginItem.isOn }, set: state.setLaunchAtLogin))
                            .labelsHidden()
                        if let text = state.loginItem.text {
                            Text(text).font(.caption).foregroundStyle(.secondary)
                        }
                        if state.loginItem.action == .openLoginItemsSettings {
                            Button("Open Login Items", action: state.openLoginItemsSettings)
                        }
                    }
                }
            }

            Section("Optional") {
                Text("Reading a screen region arrives with on-device text recognition.")
                    .foregroundStyle(.secondary)
            }

            Section {
                if let error = state.lastReadingError {
                    Text(error).foregroundStyle(.orange)
                }
                HStack {
                    Spacer()
                    Button("Quit Cáptalo", action: state.quit)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onAppear(perform: state.refreshSetup)
    }

    private var voiceRow: some View {
        LabeledContent("Voice") {
            VStack(alignment: .trailing, spacing: 4) {
                switch state.voiceState {
                case .checking:
                    ProgressView().controlSize(.small)
                case .ready:
                    Picker("Voice", selection: Binding(get: { state.voice }, set: state.setVoice)) {
                        ForEach(state.speechService.voices, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                    // A sample button for each bundled voice (plan phase 3).
                    ForEach(state.speechService.voices, id: \.self) { name in
                        Button("Sample \(name)") { state.playSample(name) }
                    }
                case .damaged, .failed:
                    Text(state.voiceState.statusText).foregroundStyle(.secondary)
                    Button("Reinstall voice", action: state.reinstallVoice)
                case .installFailed:
                    Text(state.voiceState.statusText).foregroundStyle(.secondary)
                    Button("Retry", action: state.reinstallVoice)
                case .bundleInvalid:
                    Text(state.voiceState.statusText).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var speedIndex: Binding<Double> {
        Binding(
            get: { Double(ReadingPreferences.speedSteps.firstIndex(of: state.speed) ?? 2) },
            set: { state.setSpeed(ReadingPreferences.speedSteps[Int($0.rounded())]) }
        )
    }
}
