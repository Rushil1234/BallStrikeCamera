import UIKit
import CoreImage

// Declaration order controls picker order: Original | Darkened | Brightened.
enum FrameNormalizationMode: String, CaseIterable {
    case original
    case darkenedHighContrast
    case brightened

    var displayName: String {
        switch self {
        case .original:            return "Original"
        case .darkenedHighContrast: return "Darkened"
        case .brightened:          return "Brightened"
        }
    }
}

final class FrameNormalizer {

    struct Preset {
        let exposureEV:  Float
        let contrast:    Float
        let gammaPower:  Float

        // Primary analysis mode — makes white ball pop against darkened background.
        static let darkenedHighContrast = Preset(exposureEV: -0.6, contrast: 1.35, gammaPower: 1.10)
        // Visual comparison only — over-brightens mats, not used for tracking.
        static let brightened           = Preset(exposureEV:  1.0, contrast: 1.20, gammaPower: 0.90)

        var description: String {
            String(format: "EV=%.1f contrast=%.2f gamma=%.2f", exposureEV, contrast, gammaPower)
        }
    }

    private static let presetMap: [FrameNormalizationMode: Preset] = [
        .darkenedHighContrast: .darkenedHighContrast,
        .brightened:           .brightened
    ]

    private let context: CIContext

    init() {
        self.context = CIContext(options: [.workingColorSpace: NSNull()])
    }

    func normalizedImage(from image: UIImage, mode: FrameNormalizationMode) -> UIImage {
        if mode == .original { return image }
        guard let preset = FrameNormalizer.presetMap[mode] else { return image }
        return apply(preset, to: image)
    }

    private func apply(_ preset: Preset, to image: UIImage) -> UIImage {
        guard let cgInput = image.cgImage else { return image }
        var ci = CIImage(cgImage: cgInput)

        if let filter = CIFilter(name: "CIExposureAdjust") {
            filter.setValue(ci, forKey: kCIInputImageKey)
            filter.setValue(preset.exposureEV, forKey: kCIInputEVKey)
            if let output = filter.outputImage { ci = output }
        }

        if let filter = CIFilter(name: "CIColorControls") {
            filter.setValue(ci, forKey: kCIInputImageKey)
            filter.setValue(preset.contrast, forKey: kCIInputContrastKey)
            filter.setValue(0.0, forKey: kCIInputBrightnessKey)
            if let output = filter.outputImage { ci = output }
        }

        if let filter = CIFilter(name: "CIGammaAdjust") {
            filter.setValue(ci, forKey: kCIInputImageKey)
            filter.setValue(preset.gammaPower, forKey: "inputPower")
            if let output = filter.outputImage { ci = output }
        }

        guard let cgOutput = context.createCGImage(ci, from: ci.extent) else { return image }
        return UIImage(cgImage: cgOutput, scale: image.scale, orientation: image.imageOrientation)
    }
}
