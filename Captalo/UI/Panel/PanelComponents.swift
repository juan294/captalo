import CaptaloCore
import SwiftUI

/// The rounded card behind rows and controls.
struct PanelCardModifier: ViewModifier {
    @Environment(\.panelTheme) private var theme
    var border: Color?
    var lineWidth: CGFloat = 1

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: PanelMetrics.cardRadius)
        content
            .background(theme.card, in: shape)
            .overlay(shape.strokeBorder(border ?? theme.cardBorder, lineWidth: lineWidth))
    }
}

extension View {
    func panelCard(border: Color? = nil, lineWidth: CGFloat = 1) -> some View {
        modifier(PanelCardModifier(border: border, lineWidth: lineWidth))
    }
}

/// The status pill in a pane's header.
struct StatusPill: View {
    @Environment(\.panelTheme) private var theme
    let pill: PanelPill

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(pill.text).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(text)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(pill.kind == .positive ? theme.positiveTint : theme.control, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var dot: Color {
        switch pill.kind {
        case .positive: theme.positive
        case .neutral: theme.textPrimary
        case .pending: theme.textSecondary
        }
    }

    private var text: Color {
        switch pill.kind {
        case .positive: theme.positiveText
        case .neutral: theme.textPrimary
        case .pending: theme.textSecondary
        }
    }
}

struct Keycap: View {
    @Environment(\.panelTheme) private var theme
    let label: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7)
        Text(label)
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 6)
            .frame(minWidth: 28, minHeight: 28)
            .background(theme.keycap, in: shape)
            .overlay(shape.strokeBorder(theme.controlBorder, lineWidth: 1))
            .shadow(color: theme.controlBorder, radius: 0, y: 1)
    }
}

/// A recorded shortcut as keycaps, or "Record" when there is none.
struct KeycapsLabel: View {
    let keycaps: [String]

    var body: some View {
        if keycaps.isEmpty {
            Text("Record").modifier(SecondaryButtonLook())
        } else {
            HStack(spacing: 4) {
                ForEach(Array(keycaps.enumerated()), id: \.offset) { Keycap(label: $0.element) }
            }
        }
    }
}

/// The look of a small bordered button.
struct SecondaryButtonLook: ViewModifier {
    @Environment(\.panelTheme) private var theme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        content
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(theme.keycap, in: shape)
            .overlay(shape.strokeBorder(theme.controlBorder, lineWidth: 1))
    }
}

struct SecondaryPanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(SecondaryButtonLook())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The one filled button of a pane: the action the user must take.
struct PrimaryPanelButtonStyle: ButtonStyle {
    @Environment(\.panelTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .bold))
            .foregroundStyle(theme.inverseText)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(theme.inverseFill, in: RoundedRectangle(cornerRadius: 10))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// A switch drawn from the palette: green when on.
struct PanelSwitchStyle: ToggleStyle {
    @Environment(\.panelTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? theme.positive : theme.switchOff)
                .frame(width: 40, height: 24)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 20, height: 20).padding(2)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// A section's small uppercase heading.
struct SectionLabel: View {
    @Environment(\.panelTheme) private var theme
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.3)
            .foregroundStyle(theme.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A notice the user must be able to read in full.
struct NoticeRow: View {
    @Environment(\.panelTheme) private var theme
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A row's title with its one-line explanation.
struct RowText: View {
    @Environment(\.panelTheme) private var theme
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Allowed", "In use": a green check with its word.
struct PositiveMark: View {
    @Environment(\.panelTheme) private var theme
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).accessibilityHidden(true)
            Text(text).font(.system(size: 12.5, weight: .semibold))
        }
        .foregroundStyle(theme.positiveText)
    }
}
