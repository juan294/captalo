import SwiftUI

/// The panel's palette (monochrome popover plan, "Palette"). Views take every
/// colour from here; green marks positive state only.
nonisolated struct PanelTheme: Sendable {
    let ground: Color
    let rail: Color
    let hairline: Color
    let card: Color
    let cardBorder: Color
    let textPrimary: Color
    let textSecondary: Color
    let segmentText: Color
    let control: Color
    let railActive: Color
    let keycap: Color
    let controlBorder: Color
    let switchOff: Color
    let inverseFill: Color
    let inverseText: Color
    let positive: Color
    let positiveText: Color
    let positiveTint: Color
    let positiveBorder: Color
    let attentionBorder: Color

    static let dark = PanelTheme(
        ground: Color(hex: 0x17171A), rail: Color(hex: 0x111113), hairline: Color(hex: 0x26262B),
        card: Color(hex: 0x202024), cardBorder: Color(hex: 0x2C2C31),
        textPrimary: Color(hex: 0xF2F1EE), textSecondary: Color(hex: 0xA6A6AE), segmentText: Color(hex: 0xC9C9CF),
        control: Color(hex: 0x2B2B31), railActive: Color(hex: 0x2B2B31), keycap: Color(hex: 0x2B2B31),
        controlBorder: Color(hex: 0x3C3C43), switchOff: Color(hex: 0x3C3C43),
        inverseFill: Color(hex: 0xF2F1EE), inverseText: Color(hex: 0x17171A),
        positive: Color(hex: 0x4CD08A), positiveText: Color(hex: 0x6BDDA0),
        positiveTint: Color(hex: 0x4CD08A, opacity: 0.12), positiveBorder: Color(hex: 0x6BDDA0, opacity: 0.55),
        attentionBorder: Color(hex: 0x8E8E96)
    )

    static let light = PanelTheme(
        ground: Color(hex: 0xFFFFFF), rail: Color(hex: 0xF4F4F5), hairline: Color(hex: 0xE4E4E7),
        card: Color(hex: 0xF7F7F8), cardBorder: Color(hex: 0xE4E4E7),
        textPrimary: Color(hex: 0x17171A), textSecondary: Color(hex: 0x5C5C66), segmentText: Color(hex: 0x3A3A40),
        control: Color(hex: 0xE9E9EC), railActive: Color(hex: 0xE4E4E7), keycap: Color(hex: 0xFFFFFF),
        controlBorder: Color(hex: 0xD4D4D9), switchOff: Color(hex: 0xC9C9CF),
        inverseFill: Color(hex: 0x17171A), inverseText: Color(hex: 0xFFFFFF),
        positive: Color(hex: 0x1F9D57), positiveText: Color(hex: 0x157A45),
        positiveTint: Color(hex: 0x1F9D57, opacity: 0.12), positiveBorder: Color(hex: 0x1F9D57, opacity: 0.55),
        attentionBorder: Color(hex: 0x6B6B73)
    )

    static func resolve(_ scheme: ColorScheme) -> PanelTheme {
        scheme == .light ? .light : .dark
    }
}

/// The panel's sizes, from the artboards.
nonisolated enum PanelMetrics {
    static let width: CGFloat = 440
    static let height: CGFloat = 520
    static let railWidth: CGFloat = 72
    static let railItemWidth: CGFloat = 56
    static let panePadding: CGFloat = 20
    static let sectionGap: CGFloat = 16
    static let cardRadius: CGFloat = 12
    static let footerHeight: CGFloat = 44
}

extension Color {
    nonisolated init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension EnvironmentValues {
    @Entry var panelTheme = PanelTheme.dark
    /// True only in `--render-panel`: no AppKit recorder and no scroll view,
    /// so the image shows the whole pane or its overflow.
    @Entry var panelIsRender = false
}
