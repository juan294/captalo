import CaptaloCore
import SwiftUI

/// The Setup pane: the two permissions and launch at login.
struct SetupPane: View {
    @Environment(\.panelTheme) private var theme
    let model: SetupPaneModel
    let actions: PanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Permissions")
                if model.accessibility.needsAttention {
                    // The missing required permission is the pane's one call to action.
                    VStack(alignment: .leading, spacing: 12) {
                        RowText(title: model.accessibility.title, detail: model.accessibility.detail)
                        if case let .action(label) = model.accessibility.state {
                            Button(label, action: actions.openAccessibilitySettings).buttonStyle(PrimaryPanelButtonStyle())
                        }
                    }
                    .padding(14)
                    .panelCard(border: theme.attentionBorder, lineWidth: 1.5)
                    PermissionRowView(row: model.screenRecording, primary: actions.requestScreenRecording,
                                      secondary: actions.quitAndReopen)
                        .panelCard()
                } else {
                    VStack(spacing: 0) {
                        PermissionRowView(row: model.accessibility, primary: actions.openAccessibilitySettings)
                        Rectangle().fill(theme.cardBorder).frame(height: 1).padding(.horizontal, 14)
                        PermissionRowView(row: model.screenRecording, primary: actions.requestScreenRecording,
                                          secondary: actions.quitAndReopen)
                    }
                    .panelCard()
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "General")
                loginItem.panelCard()
            }
        }
    }

    private var loginItem: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                RowText(title: "Launch at login", detail: model.loginItem.text ?? "Cáptalo waits in the menu bar")
                Toggle("Launch at login", isOn: Binding(get: { model.loginItem.isOn }, set: { actions.setLaunchAtLogin($0) }))
                    .toggleStyle(PanelSwitchStyle())
            }
            if model.loginItem.action == .openLoginItemsSettings {
                Button("Open Login Items", action: actions.openLoginItemsSettings).buttonStyle(SecondaryPanelButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minHeight: 56)
    }
}

/// A permission: allowed, or the button that asks for it.
struct PermissionRowView: View {
    let row: PermissionRow
    let primary: () -> Void
    var secondary: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                RowText(title: row.title, detail: row.detail)
                switch row.state {
                case .allowed:
                    PositiveMark(text: "Allowed")
                case let .action(label):
                    Button(label, action: primary)
                        .buttonStyle(SecondaryPanelButtonStyle())
                        .accessibilityLabel("\(label) \(row.title)")
                }
            }
            if let label = row.secondaryAction {
                Button(label, action: secondary).buttonStyle(SecondaryPanelButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
