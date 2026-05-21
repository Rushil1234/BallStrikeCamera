import Foundation
import ImageIO
import UIKit

// MARK: - Animated GIF writer from saved frames

struct ShotGIFExporter {

    /// Creates an animated GIF from the stored frames directory.
    /// - Parameters:
    ///   - framesDir: Folder containing frame_000.png … frame_NNN.png
    ///   - frameCount: Number of frames to include.
    ///   - fps: Frame rate of the output GIF (default 15).
    /// - Returns: URL of the written GIF file, or nil on failure.
    static func makeGIF(
        fromFramesDir framesDir: String,
        frameCount: Int,
        fps: Double = 15
    ) -> URL? {
        let frameDelay = 1.0 / fps
        let outputURL = URL(fileURLWithPath: framesDir)
            .deletingLastPathComponent()
            .appendingPathComponent("replay.gif")

        // Load all available frames.
        var images: [CGImage] = []
        for i in 0..<min(frameCount, 41) {
            let name = String(format: "frame_%03d.png", i)
            let path = (framesDir as NSString).appendingPathComponent(name)
            guard let uiImage = UIImage(contentsOfFile: path),
                  let cgImage = uiImage.cgImage else { continue }
            images.append(cgImage)
        }
        guard !images.isEmpty else { return nil }

        // Create destination.
        guard let dest = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            "com.compuserve.gif" as CFString,
            images.count,
            nil
        ) else { return nil }

        let gifProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0  // loop forever
            ] as [CFString: Any]
        ]
        CGImageDestinationSetProperties(dest, gifProperties as CFDictionary)

        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDelay
            ] as [CFString: Any]
        ]

        for cgImage in images {
            CGImageDestinationAddImage(dest, cgImage, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(dest) else { return nil }
        return outputURL
    }
}

// MARK: - UIView-representable animated image player

import SwiftUI

struct AnimatedFramesView: UIViewRepresentable {
    let framesDir: String
    let frameCount: Int

    func makeUIView(context: Context) -> UIImageView {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        return iv
    }

    func updateUIView(_ iv: UIImageView, context: Context) {
        // Load frames on a background thread to avoid blocking UI.
        DispatchQueue.global(qos: .userInitiated).async {
            var uiImages: [UIImage] = []
            for i in 0..<min(frameCount, 41) {
                let name = String(format: "frame_%03d.png", i)
                let path = (framesDir as NSString).appendingPathComponent(name)
                if let img = UIImage(contentsOfFile: path) { uiImages.append(img) }
            }
            guard !uiImages.isEmpty else { return }
            let animated = UIImage.animatedImage(with: uiImages, duration: Double(uiImages.count) / 15.0)
            DispatchQueue.main.async { iv.image = animated }
        }
    }
}
