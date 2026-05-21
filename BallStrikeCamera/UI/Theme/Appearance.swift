import SwiftUI
import UIKit

// MARK: - App Appearance (Light / Dark / System)

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// Single source of truth for the chosen appearance. Backed by UserDefaults so
/// every `.tcAppearance()` modifier and the settings picker stay in sync.
/// Defaults to `.light` — the brand's primary "paper" surface.
enum AppearanceStore {
    static let key = "tc_appearance"
    static var current: AppAppearance {
        AppAppearance(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .light
    }
}

// MARK: - Modifier

/// Applies the user's chosen appearance. Sets both SwiftUI's preferredColorScheme
/// and the UIWindow's overrideUserInterfaceStyle — the latter is what UIKit-backed
/// dynamic colors (Color.dyn) actually resolve against.
private struct AppearanceModifier: ViewModifier {
    @AppStorage(AppearanceStore.key) private var raw = AppAppearance.light.rawValue
    private var appearance: AppAppearance { AppAppearance(rawValue: raw) ?? .light }
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(appearance.colorScheme)
            .onAppear { AppearanceStore.applyToWindows(appearance) }
            .onChange(of: raw) { _ in AppearanceStore.applyToWindows(appearance) }
    }
}

extension AppearanceStore {
    /// Force the chosen style onto every window so dynamic colors resolve correctly.
    static func applyToWindows(_ appearance: AppAppearance) {
        let style: UIUserInterfaceStyle
        switch appearance {
        case .light:  style = .light
        case .dark:   style = .dark
        case .system: style = .unspecified
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows { window.overrideUserInterfaceStyle = style }
        }
    }
}

extension View {
    func tcAppearance() -> some View { modifier(AppearanceModifier()) }
}

// MARK: - Dynamic color helper

extension Color {
    /// Resolves to the light or dark value based on the user's chosen appearance.
    /// Theme tokens are computed (`static var`), so they re-read this on each access;
    /// a window-style change (see AppearanceModifier) re-renders views on toggle.
    static func dyn(light: Color, dark: Color) -> Color {
        TCAppearance.isDark ? dark : light
    }
}

enum TCAppearance {
    /// The effective scheme: explicit choice wins; `.system` follows the device.
    static var isDark: Bool {
        switch AppearanceStore.current {
        case .dark:   return true
        case .light:  return false
        case .system: return UITraitCollection.current.userInterfaceStyle == .dark
        }
    }
}
