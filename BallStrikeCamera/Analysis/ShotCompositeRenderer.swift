import UIKit

enum CompositeStyle: String, CaseIterable {
    case twentyOneFrame  = "21 Frames"
    case elevenFrame     = "11 Frames"
    case postImpactOnly  = "Post-Impact"

    // Short label for the compact top-bar picker.
    var shortName: String {
        switch self {
        case .twentyOneFrame:  return "21F"
        case .elevenFrame:     return "11F"
        case .postImpactOnly:  return "Post"
        }
    }

    // Frame range relative to the impact index.
    func frameRange(impact: Int, totalFrames: Int) -> ClosedRange<Int> {
        switch self {
        case .twentyOneFrame:
            return max(0, impact - 10)...min(totalFrames - 1, impact + 10)
        case .elevenFrame:
            return max(0, impact - 5)...min(totalFrames - 1, impact + 5)
        case .postImpactOnly:
            let start = min(impact + 1, totalFrames - 1)
            let end   = min(totalFrames - 1, impact + 10)
            return start...max(start, end)
        }
    }

    // Per-frame alpha — fewer frames need higher alpha to accumulate enough brightness.
    var frameAlpha: CGFloat {
        switch self {
        case .twentyOneFrame:  return 0.045
        case .elevenFrame:     return 0.080
        case .postImpactOnly:  return 0.100
        }
    }

    // Impact frame rendered brighter for 21F and 11F; postImpactOnly excludes the impact frame.
    var highlightImpactFrame: Bool {
        switch self {
        case .twentyOneFrame, .elevenFrame: return true
        case .postImpactOnly:               return false
        }
    }
}

final class ShotCompositeRenderer {

    struct Configuration {
        var style:               CompositeStyle = .elevenFrame
        // nil = use style default; set explicitly to override.
        var frameAlphaOverride:  CGFloat?       = nil
        var impactFrameAlpha:    CGFloat        = 0.16
    }

    func render(
        analysis: ShotAnalysisResult,
        mode: FrameNormalizationMode,
        configuration: Configuration = Configuration()
    ) -> UIImage? {
        let frames = analysis.frames
        guard !frames.isEmpty else { return nil }

        let impact   = analysis.impactFrameIndex
        let style    = configuration.style
        let range    = style.frameRange(impact: impact, totalFrames: frames.count)
        let selected = Array(frames[range])
        let baseAlpha = configuration.frameAlphaOverride ?? style.frameAlpha

        // Derive pixel dimensions from the first selected frame's source image.
        guard let refImage = sourceImage(selected[0], mode: mode),
              let refCG    = refImage.cgImage else { return nil }

        let size = CGSize(width: refCG.width, height: refCG.height)

        print("Rendering composite at source resolution: \(Int(size.width)) x \(Int(size.height))")
        print("Composite style: \(style.rawValue)")
        print("Composite frame range: \(range.lowerBound)...\(range.upperBound)")
        print("Composite image mode: \(mode.displayName)")
        print(String(format: "Composite alpha: %.3f (impact: %.3f)", baseAlpha,
                     style.highlightImpactFrame ? configuration.impactFrameAlpha : baseAlpha))

        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        defer { UIGraphicsEndImageContext() }

        UIColor.black.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))

        var fallbackLogged = false
        for frame in selected {
            guard let img = sourceImageWithFallback(frame, mode: mode, fallbackLogged: &fallbackLogged) else { continue }
            let alpha: CGFloat = (style.highlightImpactFrame && frame.frameIndex == impact)
                ? configuration.impactFrameAlpha
                : baseAlpha
            img.draw(in: CGRect(origin: .zero, size: size), blendMode: .normal, alpha: alpha)
        }

        let result = UIGraphicsGetImageFromCurrentImageContext()
        print("Shot composite rendered")
        return result
    }

    // MARK: - Private

    private func sourceImage(_ frame: AnalyzedShotFrame, mode: FrameNormalizationMode) -> UIImage? {
        switch mode {
        case .original:            return frame.originalFrame.image
        case .brightened:          return frame.brightenedImage           ?? frame.originalFrame.image
        case .darkenedHighContrast: return frame.darkenedHighContrastImage ?? frame.originalFrame.image
        }
    }

    private func sourceImageWithFallback(
        _ frame: AnalyzedShotFrame,
        mode: FrameNormalizationMode,
        fallbackLogged: inout Bool
    ) -> UIImage? {
        if mode == .darkenedHighContrast, frame.darkenedHighContrastImage == nil {
            if !fallbackLogged {
                print("ShotCompositeRenderer: darkenedHighContrast missing for frame \(frame.frameIndex), using original")
                fallbackLogged = true
            }
            return frame.originalFrame.image
        }
        return sourceImage(frame, mode: mode)
    }
}
