import CaptaloCore
import SwiftUI

/// The Voice pane: the bundled voices, or the voice's state and its repair.
struct VoicePane: View {
    @Environment(\.panelTheme) private var theme
    let model: VoicePaneModel
    let actions: PanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.sectionGap) {
            if model.isChecking {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(model.status ?? "").font(.system(size: 13)).foregroundStyle(theme.textSecondary)
                }
            } else if let status = model.status {
                VStack(alignment: .leading, spacing: 12) {
                    Text(status)
                        .font(.system(size: 14, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let label = model.repairLabel {
                        Button(label, action: actions.repairVoice).buttonStyle(PrimaryPanelButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .panelCard(border: theme.attentionBorder, lineWidth: 1.5)
            } else {
                Text("Play a sample or choose a voice. A sampled voice becomes the voice in use, from the next reading.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    ForEach(model.voices, id: \.id) { VoiceCardView(card: $0, actions: actions) }
                }
            }
        }
    }
}

struct VoiceCardView: View {
    @Environment(\.panelTheme) private var theme
    let card: VoiceCard
    let actions: PanelActions

    var body: some View {
        HStack(spacing: 12) {
            Button { actions.playSample(card.id) } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(card.inUse ? theme.inverseText : theme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(card.inUse ? theme.inverseFill : theme.keycap, in: Circle())
                    .overlay(Circle().strokeBorder(card.inUse ? .clear : theme.controlBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play a sample of \(card.name)")
            Text(card.name).font(.system(size: 14, weight: .semibold))
            Spacer(minLength: 0)
            if card.inUse {
                PositiveMark(text: "In use")
            } else {
                Button("Use") { actions.setVoice(card.id) }
                    .buttonStyle(SecondaryPanelButtonStyle())
                    .accessibilityLabel("Use \(card.name)")
            }
        }
        .padding(12)
        .panelCard(border: card.inUse ? theme.positiveBorder : nil, lineWidth: 1.5)
    }
}
