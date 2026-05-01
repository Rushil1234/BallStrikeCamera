import UIKit

final class ShotCompositeRenderer {

    struct Configuration {
        var preCount:         Int     = 10
        var postCount:        Int     = 10
        var frameAlpha:       CGFloat = 0.08
        var impactFrameAlpha: CGFloat = 0.18
    }

    func render(
        analysis: ShotAnalysisResult,
        mode: FrameNormalizationMode,
        configuration: Configuration = Configuration()
    ) -> UIImage? {
        let frames = analysis.frames
        guard !frames.isEmpty else { return nil }

        let impact   = analysis.impactFrameIndex
        let firstIdx = max(0, impact - configuration.preCount)
        let lastIdx  = min(frames.count - 1, impact + configuration.postCount)
        let selected = Array(frames[firstIdx...lastIdx])

        print("Rendering 21-frame shot composite")
        print("Composite frame range: \(firstIdx)...\(lastIdx)")
        print("Composite mode: \(mode.displayName)")

        guard let refCG = sourceImage(selected[0], mode: mode).cgImage else { return nil }

        let size = CGSize(width: refCG.width, height: refCG.height)

        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        defer { UIGraphicsEndImageContext() }

        UIColor.black.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))

        var fallbackLogged = false
        for frame in selected {
            let img   = sourceImageWithFallback(frame, mode: mode, fallbackLogged: &fallbackLogged)
            let alpha = frame.frameIndex == impact ? configuration.impactFrameAlpha : configuration.frameAlpha
            img.draw(in: CGRect(origin: .zero, size: size), blendMode: .normal, alpha: alpha)
        }

        let result = UIGraphicsGetImageFromCurrentImageContext()
        print("Shot composite rendered")
        return result
    }

    // MARK: - Private

    private func sourceImage(_ frame: AnalyzedShotFrame, mode: FrameNormalizationMode) -> UIImage {
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
    ) -> UIImage {
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
