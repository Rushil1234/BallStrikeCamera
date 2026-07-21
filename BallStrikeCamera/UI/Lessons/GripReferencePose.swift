import Foundation
import simd

/// Real 21-point hand landmarks captured from Noah's grip clip via MediaPipe Hand
/// Landmarker (image coords x,y in [0,1], z = relative depth). Drives the 3D grip hologram
/// so the hands take a true human grip shape, not a placeholder silhouette.
/// Hand order matches MediaPipe HAND_CONNECTIONS indexing.
enum GripReferencePose {
    /// [hand][landmark] — two hands forming the grip.
    static let grip: [[SIMD3<Float>]] = [
    // Right hand — 21 MediaPipe landmarks (image x,y,z)
    [
        SIMD3<Float>(0.5248, 0.5946, 0.0000),
        SIMD3<Float>(0.5339, 0.6181, -0.0261),
        SIMD3<Float>(0.5502, 0.6461, -0.0269),
        SIMD3<Float>(0.5677, 0.6686, -0.0234),
        SIMD3<Float>(0.5845, 0.6884, -0.0182),
        SIMD3<Float>(0.5401, 0.6553, 0.0134),
        SIMD3<Float>(0.5544, 0.6802, 0.0206),
        SIMD3<Float>(0.5666, 0.6970, 0.0192),
        SIMD3<Float>(0.5796, 0.7088, 0.0170),
        SIMD3<Float>(0.5551, 0.6488, 0.0277),
        SIMD3<Float>(0.5650, 0.6726, 0.0399),
        SIMD3<Float>(0.5780, 0.6888, 0.0367),
        SIMD3<Float>(0.5886, 0.7015, 0.0324),
        SIMD3<Float>(0.5684, 0.6422, 0.0377),
        SIMD3<Float>(0.5772, 0.6640, 0.0483),
        SIMD3<Float>(0.5855, 0.6784, 0.0464),
        SIMD3<Float>(0.5943, 0.6914, 0.0428),
        SIMD3<Float>(0.5811, 0.6358, 0.0444),
        SIMD3<Float>(0.5895, 0.6554, 0.0517),
        SIMD3<Float>(0.5931, 0.6663, 0.0539),
        SIMD3<Float>(0.5964, 0.6761, 0.0544)
    ],
    // Left hand — 21 MediaPipe landmarks (image x,y,z)
    [
        SIMD3<Float>(0.6560, 0.7277, 0.0000),
        SIMD3<Float>(0.5882, 0.7542, -0.0163),
        SIMD3<Float>(0.5658, 0.7952, -0.0107),
        SIMD3<Float>(0.5842, 0.8237, 0.0004),
        SIMD3<Float>(0.6001, 0.8416, 0.0137),
        SIMD3<Float>(0.6280, 0.8247, -0.0176),
        SIMD3<Float>(0.6335, 0.8707, -0.0169),
        SIMD3<Float>(0.6397, 0.8969, -0.0154),
        SIMD3<Float>(0.6457, 0.9174, -0.0140),
        SIMD3<Float>(0.6698, 0.8223, -0.0047),
        SIMD3<Float>(0.6676, 0.8648, 0.0050),
        SIMD3<Float>(0.6588, 0.8833, 0.0117),
        SIMD3<Float>(0.6532, 0.8938, 0.0148),
        SIMD3<Float>(0.6932, 0.8138, 0.0081),
        SIMD3<Float>(0.6779, 0.8459, 0.0152),
        SIMD3<Float>(0.6542, 0.8450, 0.0199),
        SIMD3<Float>(0.6400, 0.8383, 0.0230),
        SIMD3<Float>(0.7053, 0.8046, 0.0194),
        SIMD3<Float>(0.6870, 0.8329, 0.0268),
        SIMD3<Float>(0.6688, 0.8323, 0.0342),
        SIMD3<Float>(0.6580, 0.8247, 0.0399)
    ]
    ]
    /// MediaPipe hand skeleton connections (21-landmark topology).
    static let connections: [(Int, Int)] = [
        (0,1),(1,2),(2,3),(3,4), (0,5),(5,6),(6,7),(7,8), (5,9),(9,10),(10,11),(11,12),
        (9,13),(13,14),(14,15),(15,16), (13,17),(17,18),(18,19),(19,20), (0,17)
    ]
    /// Fingertip + key joint radii scale (wrist thick → fingertips thin) by landmark.
    static func radius(_ i: Int) -> Float {
        switch i {
        case 0: return 0.9                     // wrist
        case 1,5,9,13,17: return 0.62          // MCP / base
        case 2,6,10,14,18: return 0.5
        case 3,7,11,15,19: return 0.42
        case 4,8,12,16,20: return 0.34         // tips
        default: return 0.5
        }
    }
}
