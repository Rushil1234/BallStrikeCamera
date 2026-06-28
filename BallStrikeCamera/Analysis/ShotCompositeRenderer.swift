import UIKit

/// Renders the single per-shot composite ("best combo"): one still image that captures the whole
/// shot. There are no longer any style (21F/11F/post) or dark/bright variants — this is THE composite.
///
/// Per pixel, across every captured frame (on the original images):
///   • background (turf) — pixels that barely change → per-pixel average (clean, denoised)
///   • ball                — brightest excursion above the average wins
///   • club                — darkest excursion below the average wins
/// The brighter/darker of the two excursions decides which moving object owns the pixel.
final class ShotCompositeRenderer {

    /// Luminance excursion (0–255) a pixel must exceed before it's treated as a moving object
    /// rather than background. Matches the tuned value from the composite experiment.
    private let excursionThreshold = 16

    func render(analysis: ShotAnalysisResult) -> UIImage? {
        render(images: analysis.frames.map { $0.originalFrame.image })
    }

    /// Core renderer over a raw image sequence (used by live capture and by the one-time
    /// migration that rebuilds composites for older shots from their stored frames).
    func render(images: [UIImage]) -> UIImage? {
        guard let first = images.first, let firstCG = first.cgImage else { return nil }

        let width  = firstCG.width
        let height = firstCG.height
        let bytesPerRow = 4 * width
        let totalBytes  = bytesPerRow * height
        let pixelCount  = width * height
        let colorSpace  = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo  = CGImageAlphaInfo.premultipliedLast.rawValue
        let size = CGSize(width: width, height: height)

        // Decode every frame into an RGBA byte buffer at source resolution.
        var buffers: [[UInt8]] = []
        buffers.reserveCapacity(images.count)
        for img in images {
            guard let cg = img.cgImage else { continue }
            var bytes = [UInt8](repeating: 0, count: totalBytes)
            guard let ctx = CGContext(data: &bytes, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: colorSpace, bitmapInfo: bitmapInfo) else { continue }
            ctx.draw(cg, in: CGRect(origin: .zero, size: size))
            buffers.append(bytes)
        }
        guard !buffers.isEmpty else { return nil }
        let n = buffers.count

        var out = [UInt8](repeating: 0, count: totalBytes)
        for p in 0..<pixelCount {
            let o = p * 4
            var sumR = 0, sumG = 0, sumB = 0
            var minLum = 999, maxLum = -1, darkFrame = 0, brightFrame = 0
            for f in 0..<n {
                let buf = buffers[f]
                let r = Int(buf[o]), g = Int(buf[o+1]), b = Int(buf[o+2])
                let lum = (r + g + b) / 3
                sumR += r; sumG += g; sumB += b
                if lum < minLum { minLum = lum; darkFrame = f }
                if lum > maxLum { maxLum = lum; brightFrame = f }
            }
            let avg = (sumR + sumG + sumB) / (3 * n)
            let darkExcursion   = avg - minLum
            let brightExcursion = maxLum - avg

            if max(darkExcursion, brightExcursion) <= excursionThreshold {
                // Static background → per-pixel average.
                out[o]   = UInt8(sumR / n)
                out[o+1] = UInt8(sumG / n)
                out[o+2] = UInt8(sumB / n)
                out[o+3] = 255
            } else {
                // Moving object → brightest (ball) or darkest (club) frame wins.
                let src = brightExcursion >= darkExcursion ? buffers[brightFrame] : buffers[darkFrame]
                out[o]   = src[o]
                out[o+1] = src[o+1]
                out[o+2] = src[o+2]
                out[o+3] = 255
            }
        }

        guard let outCtx = CGContext(data: &out, width: width, height: height,
                                     bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                     space: colorSpace, bitmapInfo: bitmapInfo),
              let outCG = outCtx.makeImage() else { return nil }
        return UIImage(cgImage: outCG, scale: first.scale, orientation: first.imageOrientation)
    }
}
