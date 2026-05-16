import SwiftUI

// MARK: - Design System

enum BSTheme {

    // MARK: Colors
    static let backgroundTop    = Color(red: 0.02, green: 0.04, blue: 0.08)
    static let backgroundBottom = Color(red: 0.00, green: 0.08, blue: 0.06)
    static let panel            = Color.white.opacity(0.07)
    static let panelRaised      = Color.white.opacity(0.11)
    static let border           = Color.white.opacity(0.10)
    static let borderBright     = Color.white.opacity(0.20)
    static let textPrimary      = Color.white
    static let textSecondary    = Color.white.opacity(0.68)
    static let textMuted        = Color.white.opacity(0.42)
    static let fairwayGreen     = Color(red: 0.10, green: 0.88, blue: 0.44)
    static let electricCyan     = Color(red: 0.00, green: 0.86, blue: 1.00)
    static let gold             = Color(red: 1.00, green: 0.78, blue: 0.20)
    static let dangerRed        = Color(red: 1.00, green: 0.32, blue: 0.32)
    static let successGreen     = Color(red: 0.20, green: 0.95, blue: 0.52)
    static let simPurple        = Color(red: 0.58, green: 0.22, blue: 0.96)
    static let simBlue          = Color(red: 0.18, green: 0.42, blue: 1.00)

    // MARK: Gradients
    static var mainBackground: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom],
                       startPoint: .top, endPoint: .bottom)
    }
    static var rangeGradient: LinearGradient {
        LinearGradient(colors: [fairwayGreen, electricCyan],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var simGradient: LinearGradient {
        LinearGradient(colors: [simBlue, simPurple],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var courseGradient: LinearGradient {
        LinearGradient(colors: [gold, fairwayGreen],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [electricCyan.opacity(0.30), fairwayGreen.opacity(0.15), Color.clear],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
    static var cardHighlight: LinearGradient {
        LinearGradient(colors: [Color.white.opacity(0.08), Color.clear],
                       startPoint: .top, endPoint: .bottom)
    }

    // MARK: Layout
    static let cardRadius: CGFloat  = 22
    static let chipRadius: CGFloat  = 10
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
                        .fill(BSTheme.cardHighlight)
                    RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous)
                        .strokeBorder(BSTheme.border, lineWidth: 1)
                }
            )
            .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
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
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                    RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous)
                        .fill(BSTheme.panel)
                    RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous)
                        .strokeBorder(BSTheme.borderBright, lineWidth: 1)
                }
            )
            .shadow(color: Color.black.opacity(0.40), radius: 16, x: 0, y: 8)
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
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(BSTheme.panel)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
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
        self.shadow(color: color.opacity(0.45), radius: radius, x: 0, y: 0)
    }
}
