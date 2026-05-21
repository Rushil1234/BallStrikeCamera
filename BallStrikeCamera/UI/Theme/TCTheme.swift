import SwiftUI

// MARK: - True Carry Design System

enum TCTheme {
    // MARK: Backgrounds — Brand Guidelines v1 (dark = Carry Forest, light = Paper/Bone)
    static var background: Color { Color.dyn(light: Color(red: 0.957, green: 0.937, blue: 0.886), dark: Color(red: 0.118, green: 0.165, blue: 0.133)) } // Paper / Carry Forest #1E2A22
    static var backgroundMid: Color { background }
    static var backgroundBot: Color { background }
    static var panel: Color { Color.dyn(light: Color.white,                                  dark: Color(red: 0.141, green: 0.192, blue: 0.153)) } // raised forest #243127
    static var panelRaised: Color { Color.dyn(light: Color(red: 0.984, green: 0.973, blue: 0.941), dark: Color(red: 0.165, green: 0.227, blue: 0.180)) } // Fairway Moss #2A3A2E
    static var panelDeep: Color { Color.dyn(light: Color.black.opacity(0.05),                    dark: Color(red: 0.086, green: 0.125, blue: 0.102)) } // forest-deep #16201A
    static var glassPanel: Color { panel }

    // MARK: Text — Range Bone on forest / Night Ink on paper
    static var textPrimary: Color { Color.dyn(light: Color(red: 0.055, green: 0.078, blue: 0.059), dark: Color(red: 0.925, green: 0.894, blue: 0.824)) } // Ink #0E140F / Bone #ECE4D2
    static var textSecondary: Color { Color.dyn(light: Color(red: 0.055, green: 0.078, blue: 0.059).opacity(0.76), dark: Color(red: 0.925, green: 0.894, blue: 0.824).opacity(0.82)) }
    static var textMuted: Color { Color.dyn(light: Color(red: 0.361, green: 0.353, blue: 0.310), dark: Color(red: 0.682, green: 0.690, blue: 0.635)) } // #5C5A4F / Ash
    static var textUltraMuted: Color { Color.dyn(light: Color(red: 0.541, green: 0.522, blue: 0.463), dark: Color(red: 0.541, green: 0.533, blue: 0.502)) } // Pewter #8A8880

    // MARK: Accents — Marker Gold, Atlas Silver, Fairway sage
    static var gold: Color { Color.dyn(light: Color(red: 0.604, green: 0.482, blue: 0.275), dark: Color(red: 0.722, green: 0.604, blue: 0.369)) } // Marker Gold #B89A5E
    static var goldLight: Color { Color.dyn(light: Color(red: 0.722, green: 0.604, blue: 0.369), dark: Color(red: 0.796, green: 0.690, blue: 0.475)) } // #CBB079
    static let goldDim        = Color(red: 0.486, green: 0.396, blue: 0.235)
    static var cream: Color { Color.dyn(light: Color(red: 0.086, green: 0.125, blue: 0.102), dark: Color(red: 0.925, green: 0.894, blue: 0.824)) } // Bone / Ink
    static var sage: Color { Color.dyn(light: Color(red: 0.310, green: 0.420, blue: 0.267), dark: Color(red: 0.549, green: 0.647, blue: 0.522)) } // Fairway #8CA585
    static let sageBright     = Color(red: 0.612, green: 0.706, blue: 0.580)
    static let sageDeep       = Color(red: 0.208, green: 0.290, blue: 0.227)   // Moss-soft #354A3A
    static let deepGreen      = Color(red: 0.086, green: 0.125, blue: 0.102)   // forest-deep
    static let fairway        = Color(red: 0.30, green: 0.62, blue: 0.34).opacity(0.58)
    static var silver: Color { Color.dyn(light: Color(red: 0.541, green: 0.533, blue: 0.502), dark: Color(red: 0.784, green: 0.773, blue: 0.741)) } // Atlas Silver #C8C5BD
    static var cyan: Color { cream.opacity(0.82) }
    static let danger         = Color(red: 0.85, green: 0.45, blue: 0.42)

    // MARK: Borders — bone hairlines on forest, ink hairlines on paper
    static var border: Color { Color.dyn(light: Color(red: 0.055, green: 0.078, blue: 0.059).opacity(0.12), dark: Color(red: 0.925, green: 0.894, blue: 0.824).opacity(0.12)) }
    static var borderMedium: Color { Color.dyn(light: Color(red: 0.055, green: 0.078, blue: 0.059).opacity(0.20), dark: Color(red: 0.925, green: 0.894, blue: 0.824).opacity(0.22)) }
    static var borderGold: Color { gold.opacity(0.35) }
    static var borderSage: Color { sage.opacity(0.22) }

    // MARK: Spacing
    static let hPad: CGFloat        = 20
    static let cardRadius: CGFloat  = 10
    static let sectionGap: CGFloat  = 22
    static let rowRadius: CGFloat   = 6

    // MARK: Gradients
    /// Fixed light fill for primary buttons (which use hardcoded dark text), so
    /// it stays readable in both light and dark mode.
    static let primaryButtonFill = Color(red: 0.941, green: 0.929, blue: 0.898)
    static let goldGradient = LinearGradient(
        colors: [primaryButtonFill, primaryButtonFill],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let sageGradient = LinearGradient(
        colors: [sageBright, sageDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static var backgroundGradient: LinearGradient {
        LinearGradient(colors: [background, backgroundMid, backgroundBot],
                       startPoint: .top, endPoint: .bottom)
    }
    static var heroGradient: LinearGradient {
        LinearGradient(colors: [panelRaised, panel], startPoint: .top, endPoint: .bottom)
    }
    static var dockBackground: Color {
        Color.dyn(light: Color(red: 0.957, green: 0.937, blue: 0.886), dark: Color(red: 0.086, green: 0.125, blue: 0.102)).opacity(0.97)
    }
    static var courseGradient: LinearGradient {
        LinearGradient(colors: [panelRaised, panel], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

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
