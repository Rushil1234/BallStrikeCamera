import SwiftUI

// MARK: - Design System

enum BSTheme {

    // MARK: Colors — Brand Guidelines v1 (dark = Carry Forest, light = Paper/Bone)
    static var backgroundTop: Color { Color.dyn(light: Color(red: 0.957, green: 0.937, blue: 0.886), dark: Color(red: 0.118, green: 0.165, blue: 0.133)) } // Paper / Carry Forest
    static var backgroundBottom: Color { backgroundTop }
    static var panel: Color { Color.dyn(light: Color.white,                                  dark: Color(red: 0.141, green: 0.192, blue: 0.153)) } // raised forest
    static var panelRaised: Color { Color.dyn(light: Color(red: 0.984, green: 0.973, blue: 0.941), dark: Color(red: 0.165, green: 0.227, blue: 0.180)) } // Fairway Moss
    static var border: Color { Color.dyn(light: Color(red: 0.055, green: 0.078, blue: 0.059).opacity(0.12), dark: Color(red: 0.925, green: 0.894, blue: 0.824).opacity(0.12)) }
    static var borderBright: Color { Color.dyn(light: Color(red: 0.055, green: 0.078, blue: 0.059).opacity(0.22), dark: Color(red: 0.925, green: 0.894, blue: 0.824).opacity(0.22)) }
    static var textPrimary: Color { Color.dyn(light: Color(red: 0.055, green: 0.078, blue: 0.059), dark: Color(red: 0.925, green: 0.894, blue: 0.824)) } // Ink / Bone
    static var textSecondary: Color { Color.dyn(light: Color(red: 0.055, green: 0.078, blue: 0.059).opacity(0.76), dark: Color(red: 0.925, green: 0.894, blue: 0.824).opacity(0.80)) }
    static var textMuted: Color { Color.dyn(light: Color(red: 0.361, green: 0.353, blue: 0.310), dark: Color(red: 0.682, green: 0.690, blue: 0.635)) }
    static var fairwayGreen: Color { Color.dyn(light: Color(red: 0.310, green: 0.420, blue: 0.267), dark: Color(red: 0.549, green: 0.647, blue: 0.522)) } // Fairway sage
    static var electricCyan: Color { Color.dyn(light: Color(red: 0.541, green: 0.522, blue: 0.463), dark: Color(red: 0.784, green: 0.773, blue: 0.741)) } // Atlas Silver
    static var gold: Color { Color.dyn(light: Color(red: 0.604, green: 0.482, blue: 0.275), dark: Color(red: 0.722, green: 0.604, blue: 0.369)) } // Marker Gold
    static let dangerRed        = Color(red: 0.85, green: 0.45, blue: 0.42)
    static var successGreen: Color { Color.dyn(light: Color(red: 0.310, green: 0.420, blue: 0.267), dark: Color(red: 0.549, green: 0.647, blue: 0.522)) }
    static var simPurple: Color { Color.dyn(light: Color(red: 0.208, green: 0.290, blue: 0.227), dark: Color(red: 0.612, green: 0.706, blue: 0.580)) } // moss/sage
    static var simBlue: Color { Color.dyn(light: Color(red: 0.541, green: 0.522, blue: 0.463), dark: Color(red: 0.784, green: 0.773, blue: 0.741)) } // silver

    // MARK: Gradients
    static var mainBackground: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom],
                       startPoint: .top, endPoint: .bottom)
    }
    static var rangeGradient: LinearGradient {
        LinearGradient(colors: [panelRaised, panelRaised],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var simGradient: LinearGradient {
        LinearGradient(colors: [panelRaised, panelRaised],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var courseGradient: LinearGradient {
        LinearGradient(colors: [panelRaised, panelRaised],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [panel, panel],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
    static var cardHighlight: LinearGradient {
        LinearGradient(colors: [Color.white.opacity(0.08), Color.clear],
                       startPoint: .top, endPoint: .bottom)
    }

    // MARK: Layout
    static let cardRadius: CGFloat  = 6
    static let chipRadius: CGFloat  = 4
    static let hPad: CGFloat        = 20
    static let sectionGap: CGFloat  = 28
    static let cardGap: CGFloat     = 12
}

// MARK: - ViewModifiers

struct PremiumCardModifier: ViewModifier {
    var padding: CGFloat = BSTheme.hPad
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous)
                        .fill(BSTheme.panel)
                    RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous)
                        .strokeBorder(BSTheme.border, lineWidth: 1)
                }
            )
    }
}

struct GlassCardModifier: ViewModifier {
    var padding: CGFloat = BSTheme.hPad
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous)
                        .fill(BSTheme.panel)
                    RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous)
                        .strokeBorder(BSTheme.border, lineWidth: 1)
                }
            )
    }
}

struct SubtleBorderModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous)
                    .strokeBorder(BSTheme.border, lineWidth: 1)
            )
    }
}

struct MetricTileModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(BSTheme.panel)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(BSTheme.border, lineWidth: 1)
                }
            )
    }
}

extension View {
    func premiumCard(padding: CGFloat = BSTheme.hPad) -> some View {
        modifier(PremiumCardModifier(padding: padding))
    }
    func glassCard(padding: CGFloat = BSTheme.hPad) -> some View {
        modifier(GlassCardModifier(padding: padding))
    }
    func subtleBorder() -> some View {
        modifier(SubtleBorderModifier())
    }
    func metricTile() -> some View {
        modifier(MetricTileModifier())
    }
    func glowingAccent(_ color: Color, radius: CGFloat = 24) -> some View {
        self
    }
}
