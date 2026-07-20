import SwiftUI

// MARK: - True Carry Design System

enum TCTheme {
    // MARK: Backgrounds — Brand Guidelines v1 (dark = Carry Forest, light = Paper/Bone)
    static var background: Color { Color.dyn(light: Color(red: 0.985, green: 0.976, blue: 0.950), dark: Color(red: 0.118, green: 0.165, blue: 0.133)) } // warm white / Carry Forest #1E2A22
    static var backgroundMid: Color { background }
    static var backgroundBot: Color { background }
    static var panel: Color { Color.dyn(light: Color(red: 1.000, green: 0.996, blue: 0.982), dark: Color(red: 0.141, green: 0.192, blue: 0.153)) } // creamy white / raised forest #243127
    static var panelRaised: Color { Color.dyn(light: Color(red: 0.975, green: 0.958, blue: 0.918), dark: Color(red: 0.165, green: 0.227, blue: 0.180)) } // soft ivory / Fairway Moss #2A3A2E
    static var panelDeep: Color { Color.dyn(light: Color(red: 0.938, green: 0.910, blue: 0.842), dark: Color(red: 0.086, green: 0.125, blue: 0.102)) } // warm divider / forest-deep #16201A
    static var glassPanel: Color { panel }

    // MARK: Text — Range Bone on forest / Night Ink on paper
    static var textPrimary: Color { Color.dyn(light: Color(red: 0.055, green: 0.078, blue: 0.059), dark: Color(red: 0.925, green: 0.894, blue: 0.824)) } // Ink #0E140F / Bone #ECE4D2
    static var textSecondary: Color { Color.dyn(light: Color(red: 0.055, green: 0.078, blue: 0.059).opacity(0.76), dark: Color(red: 0.925, green: 0.894, blue: 0.824).opacity(0.82)) }
    static var textMuted: Color { Color.dyn(light: Color(red: 0.318, green: 0.306, blue: 0.259), dark: Color(red: 0.682, green: 0.690, blue: 0.635)) } // warm ink mute / Ash
    static var textUltraMuted: Color { Color.dyn(light: Color(red: 0.455, green: 0.431, blue: 0.361), dark: Color(red: 0.541, green: 0.533, blue: 0.502)) } // warm pewter / Pewter #8A8880

    // MARK: Accents — Marker Gold, Atlas Silver, Fairway sage
    static var gold: Color { Color.dyn(light: Color(red: 0.514, green: 0.392, blue: 0.188), dark: Color(red: 0.722, green: 0.604, blue: 0.369)) } // deeper Marker Gold / #B89A5E
    static var goldLight: Color { Color.dyn(light: Color(red: 0.722, green: 0.604, blue: 0.369), dark: Color(red: 0.796, green: 0.690, blue: 0.475)) } // #CBB079
    static let goldDim        = Color(red: 0.486, green: 0.396, blue: 0.235)
    static var cream: Color { Color.dyn(light: Color(red: 0.086, green: 0.125, blue: 0.102), dark: Color(red: 0.925, green: 0.894, blue: 0.824)) } // Bone / Ink
    static var sage: Color { Color.dyn(light: Color(red: 0.220, green: 0.337, blue: 0.247), dark: Color(red: 0.549, green: 0.647, blue: 0.522)) } // deeper Fairway / #8CA585
    static let sageBright     = Color(red: 0.612, green: 0.706, blue: 0.580)
    static let sageDeep       = Color(red: 0.208, green: 0.290, blue: 0.227)   // Moss-soft #354A3A
    static let deepGreen      = Color(red: 0.086, green: 0.125, blue: 0.102)   // forest-deep
    static let fairway        = Color(red: 0.30, green: 0.62, blue: 0.34).opacity(0.58)
    static var silver: Color { Color.dyn(light: Color(red: 0.541, green: 0.533, blue: 0.502), dark: Color(red: 0.784, green: 0.773, blue: 0.741)) } // Atlas Silver #C8C5BD
    static var cyan: Color { cream.opacity(0.82) }
    static let danger         = Color(red: 0.85, green: 0.45, blue: 0.42)

    // MARK: Capture flow — FIXED brand-dark tones
    // The camera / shot-result / replay screens always sit over a live feed or a
    // dark flight canvas, so they stay dark in BOTH appearances (not adaptive).
    // Single source of truth for that flow: deep Carry Forest instead of neutral
    // black, Range Bone instead of pure white, Marker Gold / Atlas Silver instead
    // of iOS system blue. Keeps the capture flow reading as the same brand.
    static let captureBg     = Color(red: 0.055, green: 0.086, blue: 0.070) // deep Carry Forest
    static let capturePanel  = Color(red: 0.086, green: 0.125, blue: 0.102) // forest-deep #16201A
    static let captureRaised = Color(red: 0.141, green: 0.192, blue: 0.153) // raised forest #243127
    static let captureGold    = Color(red: 0.722, green: 0.604, blue: 0.369) // Marker Gold #B89A5E
    static let captureBone    = Color(red: 0.925, green: 0.894, blue: 0.824) // Range Bone #ECE4D2
    static let captureSilver  = Color(red: 0.784, green: 0.773, blue: 0.741) // Atlas Silver #C8C5BD
    static let captureSage    = Color(red: 0.549, green: 0.647, blue: 0.522) // Fairway sage #8CA585

    // MARK: Borders — bone hairlines on forest, ink hairlines on paper
    static var border: Color { Color.dyn(light: Color(red: 0.055, green: 0.078, blue: 0.059).opacity(0.15), dark: Color(red: 0.925, green: 0.894, blue: 0.824).opacity(0.12)) }
    static var borderMedium: Color { Color.dyn(light: Color(red: 0.055, green: 0.078, blue: 0.059).opacity(0.24), dark: Color(red: 0.925, green: 0.894, blue: 0.824).opacity(0.22)) }
    static var borderGold: Color { gold.opacity(0.35) }
    static var borderSage: Color { sage.opacity(0.22) }

    // MARK: Spacing
    static let hPad: CGFloat        = 20
    static let cardRadius: CGFloat  = 10
    static let sectionGap: CGFloat  = 22
    static let rowRadius: CGFloat   = 6

    // MARK: Gradients
    /// Primary CTA: an inverted brand button — Carry Forest on paper (light),
    /// Range Bone on forest (dark). High contrast in both modes; keeps gold as
    /// a ≤5% accent per the brand usage ratio.
    static var primaryFill: Color { Color.dyn(light: Color(red: 0.118, green: 0.165, blue: 0.133), dark: Color(red: 0.925, green: 0.894, blue: 0.824)) } // Carry Forest / Range Bone
    static var onPrimary: Color { Color.dyn(light: Color(red: 0.925, green: 0.894, blue: 0.824), dark: Color(red: 0.055, green: 0.078, blue: 0.059)) } // Bone text / Ink text
    static var primaryGradient: LinearGradient {
        LinearGradient(colors: [primaryFill, primaryFill], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// True Marker Gold gradient — for accent badges and icons (white/ink content on top).
    static var goldGradient: LinearGradient {
        LinearGradient(colors: [goldLight, gold], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
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
        Color.dyn(light: Color(red: 0.990, green: 0.980, blue: 0.955), dark: Color(red: 0.086, green: 0.125, blue: 0.102)).opacity(0.97)
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
