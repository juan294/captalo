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
                    KeyboardShortcuts.Recorder(for: .readSelection) { state.shortcutChanged(.readSelection, $0) }
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

            Section("Optional: read a screen region") {
                LabeledContent("Read region") {
                    KeyboardShortcuts.Recorder(for: .readRegion) { state.shortcutChanged(.readRegion, $0) }
                }
                LabeledContent("Screen Recording") {
                    VStack(alignment: .trailing, spacing: 4) {
                        if state.screenRecordingGranted {
                            Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button("Allow Screen Recording", action: state.requestScreenRecording)
                            if state.screenRecordingRequested {
                                Text("If you allowed it and region reading still does nothing, macOS needs Cáptalo to reopen.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Button("Quit and reopen", action: state.quitAndReopen)
                            }
                        }
                    }
                }
                if let notice = state.regionFailureNotice {
                    Text(notice).font(.caption).foregroundStyle(.orange)
                }
            }

            Section {
                if state.setup.showsVoiceError, let error = state.lastReadingError {
                    Text(error).foregroundStyle(.orange)
                }
                HStack {
                    Spacer()
                    Button("Quit Cáptalo", action: state.quit)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsWindowController.width)
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
                default:
                    Text(state.voiceState.statusText).foregroundStyle(.secondary)
                    if let label = state.voiceState.repairLabel {
                        Button(label, action: state.reinstallVoice)
                    }
                }
            }
        }
    }

    private var speedIndex: Binding<Double> {
        Binding(
            get: { Double(ReadingPreferences.speedIndex(of: state.speed)) },
            set: { state.setSpeed(ReadingPreferences.speedSteps[Int($0.rounded())]) }
        )
    }
}
