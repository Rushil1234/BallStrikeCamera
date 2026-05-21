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
/// Defaults to `.dark` to preserve the app's original look.
enum AppearanceStore {
    static let key = "tc_appearance"
    static var current: AppAppearance {
        AppAppearance(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .dark
    }
}

// MARK: - Modifier

/// Applies the user's chosen appearance. Use in place of the old
/// `.tcAppearance()` so sheets/fullScreenCovers also follow it.
private struct AppearanceModifier: ViewModifier {
    @AppStorage(AppearanceStore.key) private var raw = AppAppearance.dark.rawValue
    func body(content: Content) -> some View {
        content.preferredColorScheme((AppAppearance(rawValue: raw) ?? .dark).colorScheme)
    }
}

extension View {
    func tcAppearance() -> some View { modifier(AppearanceModifier()) }
}

// MARK: - Dynamic color helper

extension Color {
    /// A color that resolves differently in light vs. dark mode. Lets the theme
    /// constants adapt without touching the hundreds of call sites that use them.
    static func dyn(light: Color, dark: Color) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
