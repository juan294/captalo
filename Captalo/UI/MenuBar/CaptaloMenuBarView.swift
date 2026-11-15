import SwiftUI

struct CaptaloMenuBarView: View {
    @EnvironmentObject private var state: CaptaloAppState
    @State private var isStudioHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cáptalo")
                .font(.title3.weight(.semibold))

            HStack(spacing: 12) {
                Text("Speed")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
                Slider(value: speedIndex, in: 0...Double(CaptaloAppState.speedSteps.count - 1), step: 1)
                Text("\(state.speed, specifier: "%.2f")x")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }

            Divider()

            if state.showMenuBarStatus {
                Text(state.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: primaryAction) {
                Label("Speak Selection", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!state.canSpeak)

            HStack(spacing: 10) {
                transportButton("stop.fill", help: "Stop speaking") {
                    state.stopSpeaking()
                }
                transportButton("power", help: "Quit Cáptalo") {
                    state.quit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .disabled(!state.canSpeak)

            Divider()

            Button {
                state.openStudio()
            } label: {
                Label("Open Cáptalo Studio", systemImage: "slider.horizontal.3")
                    .foregroundStyle(isStudioHovered ? .white : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isStudioHovered ? Color.accentColor : .clear)
                    }
                    .contentShape(.rect)
                    .onHover { isStudioHovered = $0 }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 300)
    }

    private var speedIndex: Binding<Double> {
        Binding(
            get: { Double(state.speedIndex) },
            set: { state.setSpeedIndex(Int($0.rounded())) }
        )
    }

    private func primaryAction() {
        state.speakSelection()
    }

    private func transportButton(
        _ symbol: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .help(help)
    }
}
