import SwiftUI

// MARK: - True Carry Design System

enum TCTheme {
    // MARK: Backgrounds
    static let background     = Color(red: 0.035, green: 0.037, blue: 0.041)
    static let backgroundMid  = background
    static let backgroundBot  = background
    static let panel          = Color.white.opacity(0.035)
    static let panelRaised    = Color.white.opacity(0.055)
    static let panelDeep      = Color.black.opacity(0.22)
    static let glassPanel     = panel

    // MARK: Text
    static let textPrimary    = Color.white
    static let textSecondary  = Color.white.opacity(0.76)
    static let textMuted      = Color.white.opacity(0.50)
    static let textUltraMuted = Color.white.opacity(0.32)

    // MARK: Accents
    static let gold           = Color.white.opacity(0.86)
    static let goldLight      = Color.white
    static let goldDim        = Color.white.opacity(0.62)
    static let sage           = Color.white.opacity(0.78)
    static let sageBright     = Color.white
    static let sageDeep       = Color.white.opacity(0.66)
    static let deepGreen      = Color.white.opacity(0.10)
    static let fairway        = Color.white.opacity(0.12)
    static let cyan           = Color.white.opacity(0.82)
    static let danger         = Color(red: 0.93, green: 0.47, blue: 0.47)

    // MARK: Borders
    static let border         = Color.white.opacity(0.10)
    static let borderMedium   = Color.white.opacity(0.14)
    static let borderGold     = Color.white.opacity(0.14)
    static let borderSage     = Color.white.opacity(0.12)

    // MARK: Spacing
    static let hPad: CGFloat        = 20
    static let cardRadius: CGFloat  = 6
    static let sectionGap: CGFloat  = 22
    static let rowRadius: CGFloat   = 4

    // MARK: Gradients
    static let goldGradient = LinearGradient(
        colors: [panelRaised, panelRaised],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let sageGradient = LinearGradient(
        colors: [panelRaised, panelRaised],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let backgroundGradient = LinearGradient(
        colors: [background, backgroundMid, backgroundBot],
        startPoint: .top, endPoint: .bottom
    )
    static let heroGradient = LinearGradient(
        colors: [panel, panel],
        startPoint: .top, endPoint: .bottom
    )
    static let dockBackground = Color.black.opacity(0.94)
    static let courseGradient = LinearGradient(
        colors: [panelRaised, panelRaised],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: Shadows
    static let goldShadow = Color.clear
    static let sageShadow = Color.clear
    static let panelShadow = Color.clear
}

// MARK: - ViewModifier extensions

extension View {
    /// Standard dark panel card
    func tcCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(TCTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                    .strokeBorder(TCTheme.border, lineWidth: 1)
            )
    }

    /// Glass-effect dark card
    func tcGlassCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(TCTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                    .strokeBorder(TCTheme.border, lineWidth: 1)
            )
    }

    func tcGoldGlow(radius: CGFloat = 18) -> some View {
        self.shadow(color: TCTheme.goldShadow, radius: radius, x: 0, y: 0)
    }

    func tcSageGlow(radius: CGFloat = 14) -> some View {
        self.shadow(color: TCTheme.sageShadow, radius: radius, x: 0, y: 0)
    }

    func tcPanelShadow() -> some View {
        self
    }
}
