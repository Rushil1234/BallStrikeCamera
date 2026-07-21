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
    /// Flashlight mode (July 20): for a dark room lit by a bright tripad flashlight. The flashlight
    /// throws a bright pool on the ball but the camera meters the dark edges as a dim scene, so the
    /// normal dim-light brightening over-exposes and blows the lit ground to white — the ball then
    /// stops being the lone bright object. This preset locks the fastest shutter (freezes flight)
    /// and forces a fixed, moderate underexposure with NO dim-light easing, so the flashlight-lit
    /// ball's specular stays the brightest thing and the ground drops back. Learned from Noah's
    /// 20:31+ flashlight captures: ~0.65× of the over-brightened output isolates the ball while
    /// still locking it (33/34 shots), whereas going darker starts losing the ball.
    case flashlight

    var id: String { label }

    var label: String {
        switch self {
        case .oneThousand: return "1/1000"
        case .twoThousand: return "1/2000"
        case .fourThousand: return "1/4000"
        case .eightThousand: return "1/8000"
        case .flashlight: return "Flash"
        }
    }

    var symbol: String {
        switch self {
        case .oneThousand:   return "moon.fill"           // night
        case .twoThousand:   return "sun.min.fill"        // sun, small rays
        case .fourThousand:  return "sun.max.fill"        // sun, medium rays
        case .eightThousand: return "sun.max.fill"        // sun, large rays (rendered bigger)
        case .flashlight:    return "flashlight.on.fill"  // tripod flashlight in the dark
        }
    }

    /// Icon point size — ramps across the sun presets so the rays read small → medium → large.
    var iconSize: CGFloat {
        switch self {
        case .oneThousand:   return 16
        case .twoThousand:   return 15
        case .fourThousand:  return 18
        case .eightThousand: return 22
        case .flashlight:    return 18
        }
    }

    var denominator: Int32 {
        switch self {
        case .oneThousand: return 1_000
        case .twoThousand: return 2_000
        case .fourThousand: return 4_000
        case .eightThousand: return 8_000
        case .flashlight:   return 8_000   // fastest shutter — freeze the flight; flashlight supplies the light
        }
    }

    /// Flashlight mode forces its own fixed underexposure instead of the metered dim-light ramp.
    var isFlashlight: Bool { self == .flashlight }
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
