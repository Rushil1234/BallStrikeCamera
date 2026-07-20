import SwiftUI

/// Palette for the launch-monitor / camera-capture controls, which always sit
/// over a live (dark) camera feed — so these are FIXED brand-dark tones, not
/// `TCTheme`'s light/dark-adaptive colors. Values are pulled from the Brand
/// Guidelines v1 dark ramp (Carry Forest / Fairway Moss / Range Bone / Marker
/// Gold / Atlas Silver) so the capture flow reads as the same product as the
/// rest of the app instead of a generic blue-gray launch monitor.
enum LaunchMonitorTheme {
    // Panels — Carry Forest ramp (was cool blue-gray charcoal).
    static let panelTop           = Color(red: 0.141, green: 0.192, blue: 0.153) // raised forest #243127
    static let panelBottom        = Color(red: 0.086, green: 0.125, blue: 0.102) // forest-deep #16201A
    static let panelRaisedTop     = Color(red: 0.165, green: 0.227, blue: 0.180) // Fairway Moss #2A3A2E
    static let panelRaisedBottom  = Color(red: 0.141, green: 0.192, blue: 0.153) // raised forest #243127

    // Hairlines — Range Bone at low opacity (was pure white).
    static let outline            = Color(red: 0.925, green: 0.894, blue: 0.824).opacity(0.10)
    static let outlineStrong      = Color(red: 0.925, green: 0.894, blue: 0.824).opacity(0.20)

    // Text — Range Bone (was pure white).
    static let textPrimary        = Color(red: 0.925, green: 0.894, blue: 0.824).opacity(0.96) // Bone #ECE4D2
    static let textSecondary      = Color(red: 0.925, green: 0.894, blue: 0.824).opacity(0.64)
    static let textMuted          = Color(red: 0.925, green: 0.894, blue: 0.824).opacity(0.36)

    // Accents — Fairway sage + Marker Gold (sky-blue accent retired).
    static let accentFairway      = Color(red: 0.549, green: 0.647, blue: 0.522) // Fairway sage #8CA585
    static let accentSky          = Color(red: 0.722, green: 0.604, blue: 0.369) // Marker Gold #B89A5E (was sky-blue)

    static let shadow             = Color.black.opacity(0.34)
}
