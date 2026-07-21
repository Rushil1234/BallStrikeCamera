import Foundation

enum CameraPhase: String, CaseIterable {
    case searching = "Searching"
    case tracking = "Tracking"
    case ready = "Ready"
    case captured = "Captured"
    case reviewingShot = "ReviewingShot"
}

/// Live lighting fit for a shutter preset, derived from the sensor's own metering.
/// The shutter is sacred (motion blur kills tracking), so the only lever is ISO — and ISO
/// tells you everything: too high = grain/murk, floor-limited = the lock falls back to a
/// slower, streak-prone shutter.
enum ShutterFitness {
    case good        // holds the -2EV operating point at clean ISO
    case grainy      // needs high ISO — noisy frames likely
    case tooDark     // even max ISO can't reach the underexposed target — murky frames
    case tooBright   // ISO floor overexposes — lock falls back to a slower shutter (streak risk)
}

enum ShutterPreset: CaseIterable, Identifiable {
    case oneThousand
    case twoThousand
    case fourThousand
    case eightThousand
    /// Dark-room escape hatch (July 20): hand the whole exposure back to the camera's native
    /// continuous auto-exposure and DON'T lock a deliberately-underexposed custom value. In a very
    /// dim room the shutter-first −2EV lock leaves the ball too dark to detect at any preset; this
    /// lets iOS brighten the scene however it wants. Frames may be blurry (AE will pick a slow
    /// shutter), so tracking accuracy is not guaranteed — it's a "does it even capture?" fallback.
    case auto

    var id: String { label }

    var label: String {
        switch self {
        case .oneThousand: return "1/1000"
        case .twoThousand: return "1/2000"
        case .fourThousand: return "1/4000"
        case .eightThousand: return "1/8000"
        case .auto: return "Auto"
        }
    }

    var symbol: String {
        switch self {
        case .oneThousand:   return "moon.fill"        // night
        case .twoThousand:   return "sun.min.fill"     // sun, small rays
        case .fourThousand:  return "sun.max.fill"     // sun, medium rays
        case .eightThousand: return "sun.max.fill"     // sun, large rays (rendered bigger)
        case .auto:          return "a.circle.fill"    // camera decides (dark-room fallback)
        }
    }

    /// Icon point size — ramps across the sun presets so the rays read small → medium → large.
    var iconSize: CGFloat {
        switch self {
        case .oneThousand:   return 16
        case .twoThousand:   return 15
        case .fourThousand:  return 18
        case .eightThousand: return 22
        case .auto:          return 18
        }
    }

    /// Shutter denominator for the custom lock. `.auto` never locks a custom shutter (it hands
    /// exposure to the camera), so this is an unused placeholder for it.
    var denominator: Int32 {
        switch self {
        case .oneThousand: return 1_000
        case .twoThousand: return 2_000
        case .fourThousand: return 4_000
        case .eightThousand: return 8_000
        case .auto:        return 1_000
        }
    }

    /// True for the fixed shutter-first presets that lock a custom exposure; false for `.auto`.
    var isCustomLock: Bool { self != .auto }
}

struct CapturedFrame: Identifiable {
    let id = UUID()
    /// 360px-wide analysis frame — EVERY detector threshold and trained model is
    /// calibrated in this space; it never changes resolution.
    let image: PlatformImage
    let timestamp: TimeInterval
    /// 720px-wide copy of the same frame (July 17). Detection stays at 360; the V2
    /// measurement stage (subpixel centroid + diameter → speed/VLA) refines its picks
    /// here at 2× precision. nil on legacy 360-only archives and when the render
    /// pipeline is backlogged — everything degrades to exactly the old behavior.
    let hiRes: PlatformImage?

    init(image: PlatformImage, timestamp: TimeInterval, hiRes: PlatformImage? = nil) {
        self.image = image
        self.timestamp = timestamp
        self.hiRes = hiRes
    }
}
