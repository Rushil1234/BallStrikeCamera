import SwiftUI

// MARK: - True Carry Design System

enum TCTheme {
    // MARK: Backgrounds
    static let background     = Color(red: 0.027, green: 0.027, blue: 0.027) // #070707
    static let backgroundMid  = background
    static let backgroundBot  = background
    static let panel          = Color(red: 0.059, green: 0.059, blue: 0.063) // #0f0f10
    static let panelRaised    = Color(red: 0.075, green: 0.075, blue: 0.078) // #131314
    static let panelDeep      = Color.black.opacity(0.42)
    static let glassPanel     = panel

    // MARK: Text
    static let textPrimary    = Color(red: 0.925, green: 0.914, blue: 0.886) // #ece9e2
    static let textSecondary  = Color(red: 0.941, green: 0.929, blue: 0.898).opacity(0.82)
    static let textMuted      = Color(red: 0.553, green: 0.553, blue: 0.529) // #8d8d87
    static let textUltraMuted = Color(red: 0.353, green: 0.353, blue: 0.333) // #5a5a55

    // MARK: Accents
    static let gold           = Color(red: 0.722, green: 0.600, blue: 0.408) // #b89968
    static let goldLight      = Color(red: 0.847, green: 0.741, blue: 0.549) // #d8bd8c
    static let goldDim        = Color(red: 0.530, green: 0.414, blue: 0.263)
    static let cream          = Color(red: 0.941, green: 0.929, blue: 0.898) // #f0ede5
    static let sage           = Color(red: 0.498, green: 0.608, blue: 0.451) // #7f9b73
    static let sageBright     = Color(red: 0.560, green: 0.680, blue: 0.510)
    static let sageDeep       = Color(red: 0.300, green: 0.380, blue: 0.280)
    static let deepGreen      = Color(red: 0.075, green: 0.082, blue: 0.070)
    static let fairway        = Color(red: 0.30, green: 0.62, blue: 0.34).opacity(0.58)
    static let cyan           = cream.opacity(0.82)
    static let danger         = Color(red: 0.93, green: 0.47, blue: 0.47)

    // MARK: Borders
    static let border         = Color.white.opacity(0.07)
    static let borderMedium   = Color.white.opacity(0.14)
    static let borderGold     = gold.opacity(0.35)
    static let borderSage     = sage.opacity(0.22)

    // MARK: Spacing
    static let hPad: CGFloat        = 20
    static let cardRadius: CGFloat  = 10
    static let sectionGap: CGFloat  = 22
    static let rowRadius: CGFloat   = 6

    // MARK: Gradients
    static let goldGradient = LinearGradient(
        colors: [cream, cream],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let sageGradient = LinearGradient(
        colors: [sageBright, sageDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let backgroundGradient = LinearGradient(
        colors: [background, backgroundMid, backgroundBot],
        startPoint: .top, endPoint: .bottom
    )
    static let heroGradient = LinearGradient(
        colors: [panelRaised, panel],
        startPoint: .top, endPoint: .bottom
    )
    static let dockBackground = Color(red: 0.027, green: 0.027, blue: 0.027).opacity(0.96)
    static let courseGradient = LinearGradient(
        colors: [panelRaised, panel],
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
