import SwiftUI

// MARK: - Design System

enum BSTheme {

    // MARK: Colors  (dark values preserved; light variants added)
    static let backgroundTop    = Color.dyn(light: Color(red: 0.949, green: 0.945, blue: 0.933), dark: Color(red: 0.035, green: 0.037, blue: 0.041))
    static let backgroundBottom = backgroundTop
    static let panel            = Color.dyn(light: Color.white, dark: Color.white.opacity(0.035))
    static let panelRaised      = Color.dyn(light: Color(red: 0.969, green: 0.965, blue: 0.953), dark: Color.white.opacity(0.055))
    static let border           = Color.dyn(light: Color.black.opacity(0.10), dark: Color.white.opacity(0.10))
    static let borderBright     = Color.dyn(light: Color.black.opacity(0.18), dark: Color.white.opacity(0.20))
    static let textPrimary      = Color.dyn(light: Color(red: 0.102, green: 0.098, blue: 0.086), dark: Color.white)
    static let textSecondary    = Color.dyn(light: Color.black.opacity(0.74), dark: Color.white.opacity(0.76))
    static let textMuted        = Color.dyn(light: Color.black.opacity(0.50), dark: Color.white.opacity(0.50))
    static let fairwayGreen     = Color.dyn(light: Color.black.opacity(0.74), dark: Color.white.opacity(0.78))
    static let electricCyan     = Color.dyn(light: Color.black.opacity(0.78), dark: Color.white.opacity(0.82))
    static let gold             = Color.dyn(light: Color.black.opacity(0.82), dark: Color.white.opacity(0.86))
    static let dangerRed        = Color(red: 1.00, green: 0.32, blue: 0.32)
    static let successGreen     = Color.dyn(light: Color.black.opacity(0.74), dark: Color.white.opacity(0.78))
    static let simPurple        = Color.dyn(light: Color.black.opacity(0.66), dark: Color.white.opacity(0.70))
    static let simBlue          = Color.dyn(light: Color.black.opacity(0.72), dark: Color.white.opacity(0.76))

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
