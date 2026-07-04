import Foundation

enum CameraPhase: String, CaseIterable {
    case searching = "Searching"
    case tracking = "Tracking"
    case ready = "Ready"
    case captured = "Captured"
    case reviewingShot = "ReviewingShot"
}

enum ShutterPreset: CaseIterable, Identifiable {
    case oneThousand
    case twoThousand
    case fourThousand
    case eightThousand

    var id: String { label }

    var label: String {
        switch self {
        case .oneThousand: return "1/1000"
        case .twoThousand: return "1/2000"
        case .fourThousand: return "1/4000"
        case .eightThousand: return "1/8000"
        }
    }

    var symbol: String {
        switch self {
        case .oneThousand:   return "moon.fill"        // night
        case .twoThousand:   return "sun.min.fill"     // sun, small rays
        case .fourThousand:  return "sun.max.fill"     // sun, medium rays
        case .eightThousand: return "sun.max.fill"     // sun, large rays (rendered bigger)
        }
    }

    /// Icon point size — ramps across the sun presets so the rays read small → medium → large.
    var iconSize: CGFloat {
        switch self {
        case .oneThousand:   return 16
        case .twoThousand:   return 15
        case .fourThousand:  return 18
        case .eightThousand: return 22
        }
    }

    var denominator: Int32 {
        switch self {
        case .oneThousand: return 1_000
        case .twoThousand: return 2_000
        case .fourThousand: return 4_000
        case .eightThousand: return 8_000
        }
    }
}

struct CapturedFrame: Identifiable {
    let id = UUID()
    let image: PlatformImage
    let timestamp: TimeInterval
}
