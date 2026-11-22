import CaptaloCore
import KeyboardShortcuts
import SwiftUI

/// What the panel's controls do. The live panel binds these to
/// `CaptaloAppState`; a render leaves them empty.
struct PanelActions {
    var setSpeed: (Float) -> Void = { _ in }
    var setVoice: (String) -> Void = { _ in }
    var playSample: (String) -> Void = { _ in }
    var repairVoice: () -> Void = {}
    var openAccessibilitySettings: () -> Void = {}
    var requestScreenRecording: () -> Void = {}
    var quitAndReopen: () -> Void = {}
    var setLaunchAtLogin: (Bool) -> Void = { _ in }
    var openLoginItemsSettings: () -> Void = {}
    var shortcutChanged: (KeyboardShortcuts.Name, KeyboardShortcuts.Shortcut?) -> Void = { _, _ in }
    var stopReading: () -> Void = {}
    var quit: () -> Void = {}
}

/// The menu-bar panel: a rail of sections, one pane, a footer. It draws
/// `PanelModel` and decides nothing itself.
struct PanelRootView: View {
    let model: PanelModel
    let actions: PanelActions
    @Binding var tab: PanelTab
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = PanelTheme.resolve(scheme)
        HStack(spacing: 0) {
            RailView(attention: model.attention, tab: $tab, stopReading: actions.stopReading, quit: actions.quit)
            Rectangle().fill(theme.hairline).frame(width: 1)
            VStack(spacing: 0) {
                PaneHeader(title: title, pill: model.pill(for: tab))
                PaneBody { pane }
                PanelFooter()
            }
            // Top-aligned and clipped: content that does not fit a render is cut at the bottom, where it shows.
            .frame(maxWidth: .infinity)
            .frame(height: PanelMetrics.height, alignment: .top)
            .clipped()
        }
        .frame(width: PanelMetrics.width, height: PanelMetrics.height)
        .foregroundStyle(theme.textPrimary)
        .background(theme.ground)
        .environment(\.panelTheme, theme)
    }

    private var title: String {
        switch tab {
        case .read: "Read"
        case .voice: "Voice"
        case .setup: "Setup"
        }
    }

    @ViewBuilder private var pane: some View {
        switch tab {
        case .read: ReadPane(model: model.read, actions: actions, tab: $tab)
        case .voice: VoicePane(model: model.voice, actions: actions)
        case .setup: SetupPane(model: model.setup, actions: actions)
        }
    }
}

struct RailView: View {
    @Environment(\.panelTheme) private var theme
    let attention: Set<PanelTab>
    @Binding var tab: PanelTab
    let stopReading: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image("MenuBarGlyph")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
                .frame(width: 32, height: 32)
                .padding(.bottom, 12)
                .accessibilityHidden(true)
            item(.read, "Read", "speaker.wave.2")
            item(.voice, "Voice", "waveform")
            item(.setup, "Setup", "slider.horizontal.3")
            Spacer(minLength: 0)
            Button(action: stopReading) { RailLabel(title: "Stop", symbol: "stop.fill", active: false) }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop reading")
                .help("Stop reading")
            Button(action: quit) { RailLabel(title: "Quit", symbol: "power", active: false) }
                .buttonStyle(.plain)
                .accessibilityLabel("Quit Cáptalo")
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(width: PanelMetrics.railWidth - 1)
        .frame(maxHeight: .infinity)
        .background(theme.rail)
    }

    private func item(_ target: PanelTab, _ title: String, _ symbol: String) -> some View {
        let needsAttention = attention.contains(target)
        return Button { tab = target } label: {
            RailLabel(title: title, symbol: symbol, active: tab == target)
                .overlay(alignment: .topTrailing) {
                    if needsAttention {
                        Circle().fill(theme.textPrimary).frame(width: 8, height: 8)
                            .overlay(Circle().strokeBorder(theme.rail, lineWidth: 2).frame(width: 12, height: 12))
                            .offset(x: -11, y: 5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(needsAttention ? "Needs attention" : "")
        .accessibilityAddTraits(tab == target ? .isSelected : [])
    }
}

struct RailLabel: View {
    @Environment(\.panelTheme) private var theme
    let title: String
    let symbol: String
    let active: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .frame(height: 20)
            Text(title).font(.system(size: 11, weight: active ? .semibold : .regular))
        }
        .foregroundStyle(active ? theme.textPrimary : theme.textSecondary)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(width: PanelMetrics.railItemWidth)
        .background(active ? theme.railActive : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }
}

struct PaneHeader: View {
    let title: String
    let pill: PanelPill

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            StatusPill(pill: pill)
        }
        .frame(height: 28)
        .padding(.horizontal, PanelMetrics.panePadding)
        .padding(.top, PanelMetrics.panePadding)
        .padding(.bottom, PanelMetrics.sectionGap)
    }
}

/// The pane's content. It scrolls in the live panel, so a long notice is never
/// cut off; a render draws it unscrolled, so an overflow shows in the image.
struct PaneBody<Content: View>: View {
    @Environment(\.panelIsRender) private var isRender
    @ViewBuilder let content: Content

    var body: some View {
        let padded = content
            .padding(.horizontal, PanelMetrics.panePadding)
            .padding(.bottom, PanelMetrics.sectionGap)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        if isRender {
            padded.frame(maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView { padded }.frame(maxHeight: .infinity)
        }
    }
}

struct PanelFooter: View {
    @Environment(\.panelTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock").font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
            Text("Speech and OCR run on this Mac").font(.system(size: 12))
        }
        .foregroundStyle(theme.textSecondary)
        .padding(.horizontal, PanelMetrics.panePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: PanelMetrics.footerHeight)
        .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }
}
