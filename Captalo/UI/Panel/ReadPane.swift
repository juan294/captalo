import CaptaloCore
import KeyboardShortcuts
import SwiftUI

/// The Read pane: both shortcuts, the speed, and the voice in use.
struct ReadPane: View {
    @Environment(\.panelTheme) private var theme
    let model: ReadPaneModel
    let actions: PanelActions
    @Binding var tab: PanelTab

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.sectionGap) {
            if let error = model.voiceError { NoticeRow(text: error) }
            VStack(alignment: .leading, spacing: 8) {
                ShortcutCard(
                    symbol: "text.cursor", title: "Read selection", caption: "Select text, then press",
                    name: .readSelection, slot: model.selection, changed: actions.shortcutChanged
                )
                ShortcutCard(
                    symbol: "viewfinder", title: "Read region", caption: "Press, then drag on screen",
                    name: .readRegion, slot: model.region, changed: actions.shortcutChanged
                )
                if let notice = model.regionNotice { NoticeRow(text: notice) }
                Text(model.shortcutNotice)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel(text: "Speed")
                    Spacer()
                    Text("From the next reading").font(.system(size: 12)).foregroundStyle(theme.textSecondary)
                }
                SpeedControl(steps: model.speedSteps, select: actions.setSpeed)
            }
            Button { tab = .voice } label: {
                HStack(spacing: 12) {
                    Text("Voice").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(model.voiceName).font(.system(size: 13)).foregroundStyle(theme.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                        .accessibilityHidden(true)
                }
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .frame(height: 48)
                .panelCard()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Voice, \(model.voiceName)")
            .accessibilityHint("Shows the voices")
        }
    }
}

/// One shortcut: what it does, and its keycaps, which record a new one.
struct ShortcutCard: View {
    @Environment(\.panelTheme) private var theme
    @Environment(\.panelIsRender) private var isRender
    let symbol: String
    let title: String
    let caption: String
    let name: KeyboardShortcuts.Name
    let slot: ShortcutSlot
    let changed: (KeyboardShortcuts.Name, KeyboardShortcuts.Shortcut?) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 36, height: 36)
                .background(theme.control, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            RowText(title: title, detail: caption)
            if isRender {
                KeycapsLabel(keycaps: slot.keycaps)
            } else {
                KeycapRecorder(name: name, keycaps: slot.keycaps, title: title) { changed(name, $0) }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .panelCard()
    }
}

/// The six reading speeds as one segmented control.
struct SpeedControl: View {
    @Environment(\.panelTheme) private var theme
    let steps: [SpeedStep]
    let select: (Float) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(steps, id: \.label) { step in
                Button { select(step.value) } label: {
                    Text(step.label)
                        .font(.system(size: 12.5, weight: step.selected ? .bold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(step.selected ? theme.inverseText : theme.segmentText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(step.selected ? theme.inverseFill : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Speed \(step.label)")
                .accessibilityAddTraits(step.selected ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(height: 44)
        .panelCard()
    }
}
