import CoreVideo
import CoreGraphics

/// A tiny CPU-only detector meant as a replaceable first pass.
///
/// Current heuristic: look for a compact, bright, low-saturation blob. This works best for a white ball
/// against darker grass/turf/backgrounds. Replace this with a CoreML/Vision model later if needed.
final class BallDetector {
    struct Configuration {
        var sampleStride: Int = 6
        var minimumBrightPixels: Int = 18
        var brightnessThreshold: Int = 155
        var maxChannelSpread: Int = 72
        var minimumAspectRatio: CGFloat = 0.55
        var maximumAspectRatio: CGFloat = 1.85
        var minimumNormalizedArea: CGFloat = 0.00002
        var maximumNormalizedArea: CGFloat = 0.04
        // Bright pixels must fill at least this fraction of the bounding-box grid cells.
        // A golf ball fills ~40–70%; scattered glare (tee, mat reflections) fills ~4–10%.
        // This prevents multiple distant bright spots from merging into one oversized blob.
        var minimumFillRatio: Double = 0.18
    }

    private let configuration: Configuration

    // ADAPTIVE THRESHOLD state (July 20). The fixed brightnessThreshold assumes a sunlit,
    // saturated (≈255) white ball; indoors the ball's whole disc can sit below it and never
    // cluster ("no cluster" even with the ball plainly in the circle). We lower the working
    // threshold toward the scene's OWN background when a frame is dim — but never above the
    // configured value, so bright/range capture stays byte-for-byte identical. Derived from
    // each frame's brightness histogram and applied on the NEXT frame (lighting changes far
    // slower than 240fps, so a one-frame lag is invisible). Only touched from the video queue.
    private var adaptiveThreshold: Int
    private let adaptiveFloor = 105    // never drop below this (keeps grain/turf out)

    /// The brightness threshold the detector is currently using (adaptive; ≤ the configured
    /// ceiling). Shared with ImpactDetector so its ball-pixel census counts the ball at the SAME
    /// threshold the detector actually located it at — otherwise a dim (flashlight/indoor) ball
    /// locks but the impact baseline stays under its "real ball" floor and the shot never triggers.
    var activeThreshold: Int { adaptiveThreshold }

    // Diagnostic throttling — this runs at up to 240fps, so only a fraction of calls print.
    // `frameCounter` is only ever touched from the serial video-capture queue that calls detect().
    private var frameCounter: Int = 0
    private let diagnosticLogInterval = 60   // ~4x/sec at 240fps, ~2x/sec at 120fps
    private var hasLoggedFormatError = false
    private var rejectedCandidateCount = 0
    // Session-constant scan parameters are only logged when this changes.
    private var lastLoggedROI: CGRect?

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.adaptiveThreshold = configuration.brightnessThreshold
    }

    func detect(in pixelBuffer: CVPixelBuffer, roi: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> BallObservation? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA,
              let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            if !hasLoggedFormatError {
                hasLoggedFormatError = true
                print("BallDetector: pixel buffer is not 32BGRA (or has no base address) — detection can never run. format=\(CVPixelBufferGetPixelFormatType(pixelBuffer))")
            }
            return nil
        }

        frameCounter += 1
        let shouldLogSnapshot = frameCounter % diagnosticLogInterval == 0

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
        let sampleStride = max(1, configuration.sampleStride)

        // Clamp ROI to valid pixel bounds
        let xStart = max(0, Int(roi.minX * CGFloat(width)))
        let xEnd   = min(width,  Int(roi.maxX * CGFloat(width)))
        let yStart = max(0, Int(roi.minY * CGFloat(height)))
        let yEnd   = min(height, Int(roi.maxY * CGFloat(height)))

        guard xStart < xEnd, yStart < yEnd else {
            print("BallDetector: degenerate ROI in pixel space — roi=\(roi) frame=\(width)x\(height) bounds=(\(xStart),\(yStart))-(\(xEnd),\(yEnd))")
            return nil
        }

        // Diagnostics only — doesn't affect detection, just explains *why* count stayed low.
        var maxBrightnessSeen = 0
        var brightIgnoringSpread = 0   // brightness passed, but spread (saturation) did not
        var limePixelCount = 0         // pixels admitted via the lime range-ball signature
        var sampledPixels = 0

        // Collect qualifying sample points instead of folding them into one running bbox —
        // a single stray bright pixel elsewhere in the ROI (glare, a bright blade of grass)
        // used to inflate that one global bbox to the whole ROI and permanently fail the
        // fill-ratio check below, even when the ball itself formed a perfectly tight blob.
        // Clustering by adjacency first (below) fixes that without changing the scan itself.
        var brightX: [Int] = []
        var brightY: [Int] = []

        // This frame collects at the threshold computed from the PREVIOUS frame's histogram;
        // this frame's histogram sets the threshold for the next one. brightnessThreshold is the
        // ceiling, so in bright light scanThreshold == the configured value and nothing changes.
        let scanThreshold = adaptiveThreshold
        var histogram = [Int](repeating: 0, count: 256)

        // Scan only within ROI, downsampled. BGRA byte order.
        // normalizedRect output is always relative to the full frame so overlay mapping is unchanged.
        for y in stride(from: yStart, to: yEnd, by: sampleStride) {
            let row = pointer + y * bytesPerRow
            for x in stride(from: xStart, to: xEnd, by: sampleStride) {
                sampledPixels += 1
                let idx = x * 4
                let b = Int(row[idx])
                let g = Int(row[idx + 1])
                let r = Int(row[idx + 2])
                let maxChannel = max(r, max(g, b))
                let minChannel = min(r, min(g, b))
                let brightness = (r + g + b) / 3
                let spread = maxChannel - minChannel

                histogram[brightness] += 1
                if brightness > maxBrightnessSeen { maxBrightnessSeen = brightness }

                // White balls are bright with modest channel spread. COLORED range balls
                // (yellow OR lime) fail the spread test but their BLUE channel collapses far
                // below BOTH red and green, with red≈green — which neither turf nor white does.
                // Yellow reads r≈g>b (measured 237,219,47), lime reads g≳r>b (207,227,2); both
                // give a large min(r,g)−b. |r−g|≤45 is load-bearing: it rejects golden sunlit
                // grass (240,189,4 → r−g≈50) yet keeps yellow AND lime, and the blue-collapse
                // rejects green turf (g≫r with b≈r). The OLD gate required r<g, which only
                // matched lime — a real yellow ball (r>g) fell through and never locked (Jul 21).
                let isLime = min(r, g) - b >= 90 && abs(r - g) <= 45
                if brightness >= scanThreshold {
                    if spread <= configuration.maxChannelSpread || isLime {
                        if isLime && spread > configuration.maxChannelSpread { limePixelCount += 1 }
                        brightX.append(x)
                        brightY.append(y)
                    } else {
                        brightIgnoringSpread += 1
                    }
                } else if brightness >= 130, isLime {
                    // Lime body in softer light sits under the white threshold but far
                    // above turf brightness (~100-120), and turf never passes the blue gate.
                    limePixelCount += 1
                    brightX.append(x)
                    brightY.append(y)
                }
            }
        }

        // Recompute the adaptive threshold from this frame's brightness distribution, for the
        // NEXT frame. Set it partway up the span between the scene BACKGROUND (45th percentile —
        // most of the ROI is turf/mat) and the BRIGHT peak (99th percentile ≈ the ball, robust to
        // a stray hot pixel). Crucially this keys off the BALL, not the background: when the ball
        // saturates (sun/moon), the span is huge so the threshold pins to the configured ceiling
        // and detection is byte-for-byte unchanged — a dark-grass background can't drag it down.
        // Only when the brightest thing in frame is itself dim (an unsaturated indoor ball) does
        // the threshold lower, floored so it never reaches into grain/turf.
        if sampledPixels > 0 {
            let bgTarget = sampledPixels * 45 / 100
            let hiTarget = sampledPixels * 99 / 100
            var acc = 0
            var bgLevel = 0
            var hiLevel = 255
            var haveBg = false
            for level in 0..<256 {
                acc += histogram[level]
                if !haveBg, acc >= bgTarget { bgLevel = level; haveBg = true }
                if acc >= hiTarget { hiLevel = level; break }
            }
            let dynamic = bgLevel + (hiLevel - bgLevel) * 3 / 5   // 60% up the background→ball span
            adaptiveThreshold = max(adaptiveFloor, min(configuration.brightnessThreshold, dynamic))
        }

        if shouldLogSnapshot {
            // ROI/thresholds are constant for a whole session — print them only on change,
            // then keep the per-snapshot line to the three numbers that actually vary.
            // w = bright+low-spread (white-ish, ball material), c = bright+high-spread (colored glare).
            if roi != lastLoggedROI {
                lastLoggedROI = roi
                print(String(format: "[BD] roi=(%.3f,%.3f %.3fx%.3f) px=(%d,%d)-(%d,%d) sampled=%d thrBright=%d(cap%d) thrSpread=%d needW=%d",
                             roi.minX, roi.minY, roi.width, roi.height,
                             xStart, yStart, xEnd, yEnd, sampledPixels,
                             scanThreshold, configuration.brightnessThreshold, configuration.maxChannelSpread,
                             configuration.minimumBrightPixels))
            }
            print("[BD] max=\(maxBrightnessSeen) thr=\(scanThreshold) w=\(brightX.count) c=\(brightIgnoringSpread) l=\(limePixelCount)")
        }

        guard brightX.count >= configuration.minimumBrightPixels else {
            if shouldLogSnapshot {
                let reason = maxBrightnessSeen < scanThreshold
                    ? "dark max=\(maxBrightnessSeen)"
                    : "w=\(brightX.count)<\(configuration.minimumBrightPixels) c=\(brightIgnoringSpread)"
                print("[BD] NCF \(reason)")
            }
            return nil
        }

        // Group bright samples into spatially-connected clusters (8-neighbor adjacency on the
        // sample grid, same grid the stride already samples on) so each blob is tested for
        // fill/aspect/area independently instead of as one merged region.
        var gridIndex: [Int64: Int] = [:]
        gridIndex.reserveCapacity(brightX.count * 2)
        for i in 0..<brightX.count {
            let key = Int64(brightX[i] / sampleStride) * 1_000_000 + Int64(brightY[i] / sampleStride)
            gridIndex[key] = i
        }

        var visited = [Bool](repeating: false, count: brightX.count)
        var bestObservation: BallObservation?
        var bestCount = 0
        var bestRejectReason: String?

        for start in 0..<brightX.count {
            guard !visited[start] else { continue }
            visited[start] = true
            var stack = [start]
            var clusterIndices: [Int] = []

            while let i = stack.popLast() {
                clusterIndices.append(i)
                let gx = brightX[i] / sampleStride
                let gy = brightY[i] / sampleStride
                for dgx in -1...1 {
                    for dgy in -1...1 {
                        if dgx == 0 && dgy == 0 { continue }
                        let key = Int64(gx + dgx) * 1_000_000 + Int64(gy + dgy)
                        if let ni = gridIndex[key], !visited[ni] {
                            visited[ni] = true
                            stack.append(ni)
                        }
                    }
                }
            }

            guard clusterIndices.count >= configuration.minimumBrightPixels else { continue }

            var minX = width, minY = height, maxX = 0, maxY = 0
            var sumX = 0, sumY = 0
            for i in clusterIndices {
                let x = brightX[i], y = brightY[i]
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
                sumX += x; sumY += y
            }
            let count = clusterIndices.count

            // Reject scattered glare: bright pixels must fill a meaningful fraction of their
            // bounding box. A ball fills ~40–70% of its grid; multiple distant bright spots
            // (tee, mat glare) fill ~4–10%, causing a huge bounding box and center drift.
            let gridW = max(1, (maxX - minX) / sampleStride + 1)
            let gridH = max(1, (maxY - minY) / sampleStride + 1)
            let fillRatio = Double(count) / Double(gridW * gridH)
            guard fillRatio >= configuration.minimumFillRatio else {
                bestRejectReason = "scatter fill=\(String(format: "%.3f", fillRatio))<\(configuration.minimumFillRatio) grid=\(gridW)x\(gridH) n=\(count)"
                continue
            }

            let boxWidth = CGFloat(maxX - minX + sampleStride)
            let boxHeight = CGFloat(maxY - minY + sampleStride)
            guard boxWidth > 0, boxHeight > 0 else { continue }

            let aspect = boxWidth / boxHeight
            let normalizedArea = (boxWidth * boxHeight) / CGFloat(width * height)
            guard aspect >= configuration.minimumAspectRatio,
                  aspect <= configuration.maximumAspectRatio,
                  normalizedArea >= configuration.minimumNormalizedArea,
                  normalizedArea <= configuration.maximumNormalizedArea else {
                bestRejectReason = "asp=\(String(format: "%.2f", aspect)) area=\(String(format: "%.5f", normalizedArea)) box=\(Int(boxWidth))x\(Int(boxHeight))"
                continue
            }

            // Keep the largest passing cluster — the real ball should be the biggest
            // compact, correctly-shaped bright blob in frame.
            if count > bestCount {
                bestCount = count
                let centerX = CGFloat(sumX) / CGFloat(count)
                let centerY = CGFloat(sumY) / CGFloat(count)
                let side = max(boxWidth, boxHeight) * 1.35
                let rect = CGRect(
                    x: max(0, centerX - side / 2) / CGFloat(width),
                    y: max(0, centerY - side / 2) / CGFloat(height),
                    width: min(side, CGFloat(width)) / CGFloat(width),
                    height: min(side, CGFloat(height)) / CGFloat(height)
                ).standardized
                let confidence = min(1.0, Double(count) / 240.0)
                bestObservation = BallObservation(normalizedRect: rect, confidence: confidence,
                                                  fillRatio: fillRatio)
            }
        }

        guard let observation = bestObservation else {
            rejectedCandidateCount += 1
            if shouldLogSnapshot || rejectedCandidateCount % 30 == 1 {
                print("[BD] rej#\(rejectedCandidateCount) \(bestRejectReason ?? "no cluster") [w=\(brightX.count)]")
            }
            return nil
        }

        if shouldLogSnapshot {
            let r = observation.normalizedRect
            print(String(format: "[BD] CAND c=%.2f (%.3f,%.3f %.3fx%.3f)",
                         observation.confidence, r.minX, r.minY, r.width, r.height))
        }
        return observation
    }

    /// One-shot post-lock refinement. The live detect() rect is stride-quantized and padded
    /// 1.35× around the bright-pixel centroid, so it overstates the true ball diameter by
    /// ~35-50%. This rescans a small window around the locked rect at stride 1: a core pass
    /// at the normal brightness threshold finds the ball's bright disc, then a rim pass at a
    /// lower threshold grows that cluster outward so the darker limb of the ball is included
    /// instead of just the specular core. Returns a tight square rect (normalized, full-frame
    /// coords) or nil when no plausible cluster is found — the caller keeps the padded rect.
    func tightRect(in pixelBuffer: CVPixelBuffer, around rect: CGRect) -> CGRect? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA,
              let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)

        // The incoming rect already contains the ball with padding; a touch of extra margin
        // covers the stride-6 quantization of its edges.
        let window = rect.insetBy(dx: -rect.width * 0.15, dy: -rect.height * 0.15)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let xStart = max(0, Int(window.minX * CGFloat(width)))
        let xEnd   = min(width, Int(window.maxX * CGFloat(width)))
        let yStart = max(0, Int(window.minY * CGFloat(height)))
        let yEnd   = min(height, Int(window.maxY * CGFloat(height)))
        let winW = xEnd - xStart
        let winH = yEnd - yStart
        guard winW > 2, winH > 2, winW * winH < 200_000 else { return nil }

        // 0 = background, 1 = rim (dimmer ball limb), 2 = core (ball-bright). Track the same
        // adaptive threshold detection used, so a dim-light lock still finds its (dimmer) core.
        let coreBrightness = adaptiveThreshold
        let rimBrightness  = max(80, coreBrightness - 45)
        let rimSpread      = configuration.maxChannelSpread + 20
        var mask = [UInt8](repeating: 0, count: winW * winH)
        for y in 0..<winH {
            let row = pointer + (y + yStart) * bytesPerRow
            for x in 0..<winW {
                let idx = (x + xStart) * 4
                let b = Int(row[idx]), g = Int(row[idx + 1]), r = Int(row[idx + 2])
                let brightness = (r + g + b) / 3
                let spread = max(r, max(g, b)) - min(r, min(g, b))
                // Same colored-ball signature as the detection scan (yellow OR lime): blue
                // collapsed below both red and green, red≈green. See detect() for the rationale.
                let isLime = min(r, g) - b >= 90 && abs(r - g) <= 45
                if brightness >= coreBrightness && (spread <= configuration.maxChannelSpread || isLime) {
                    mask[y * winW + x] = 2
                } else if brightness >= 130 && isLime {
                    mask[y * winW + x] = 2
                } else if brightness >= rimBrightness && (spread <= rimSpread || isLime) {
                    mask[y * winW + x] = 1
                }
            }
        }

        // Largest 8-connected cluster of core pixels = the ball's bright disc.
        var visited = [Bool](repeating: false, count: winW * winH)
        var bestCluster: [Int] = []
        for start in 0..<mask.count where mask[start] == 2 && !visited[start] {
            visited[start] = true
            var stack = [start]
            var cluster: [Int] = []
            while let i = stack.popLast() {
                cluster.append(i)
                let cx = i % winW, cy = i / winW
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = cx + dx, ny = cy + dy
                        guard nx >= 0, nx < winW, ny >= 0, ny < winH else { continue }
                        let ni = ny * winW + nx
                        if mask[ni] == 2 && !visited[ni] {
                            visited[ni] = true
                            stack.append(ni)
                        }
                    }
                }
            }
            if cluster.count > bestCluster.count { bestCluster = cluster }
        }
        guard bestCluster.count >= configuration.minimumBrightPixels else { return nil }

        var coreMinX = winW, coreMinY = winH, coreMaxX = 0, coreMaxY = 0
        for i in bestCluster {
            let cx = i % winW, cy = i / winW
            coreMinX = min(coreMinX, cx); coreMaxX = max(coreMaxX, cx)
            coreMinY = min(coreMinY, cy); coreMaxY = max(coreMaxY, cy)
        }
        let coreSide = CGFloat(max(coreMaxX - coreMinX, coreMaxY - coreMinY) + 1)

        // Grow the core outward over rim pixels so the tight box spans the whole ball,
        // not just its brightest patch.
        var grown = [Bool](repeating: false, count: winW * winH)
        var stack = bestCluster
        for i in bestCluster { grown[i] = true }
        var minX = winW, minY = winH, maxX = 0, maxY = 0
        while let i = stack.popLast() {
            let cx = i % winW, cy = i / winW
            minX = min(minX, cx); maxX = max(maxX, cx)
            minY = min(minY, cy); maxY = max(maxY, cy)
            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let nx = cx + dx, ny = cy + dy
                    guard nx >= 0, nx < winW, ny >= 0, ny < winH else { continue }
                    let ni = ny * winW + nx
                    if mask[ni] >= 1 && !grown[ni] {
                        grown[ni] = true
                        stack.append(ni)
                    }
                }
            }
        }

        var boxW = CGFloat(maxX - minX + 1)
        var boxH = CGFloat(maxY - minY + 1)
        // The rim can only be the ball's own limb, which adds a thin band around the core.
        // Sunlit grass sits right at the rim threshold and, once one blade touches the core,
        // the flood fill rides it to the window edge (observed: every lock "grew" past the
        // padded rect and got rejected). If growth exceeded what a ball limb can physically
        // add, discard it and take the core plus a fixed limb margin instead.
        if max(boxW, boxH) > coreSide * 1.5 {
            print(String(format: "[BD] TIGHT rim bled (%.0fpx from core %.0fpx) — using core+margin", max(boxW, boxH), coreSide))
            minX = coreMinX; maxX = coreMaxX
            minY = coreMinY; maxY = coreMaxY
            boxW = coreSide * 1.15
            boxH = boxW
        }
        let side = max(boxW, boxH)
        guard side >= 4 else { return nil }

        // Sanity: the tight square must actually be tighter than (or equal to) the padded
        // lock rect, and not so small that we latched onto a glint. Outside that range the
        // scan hit something odd (mat glare bleeding, logo-only cluster) — keep the original.
        let originalSidePx = rect.width * CGFloat(width)
        guard side <= originalSidePx * 1.05, side >= originalSidePx * 0.30 else {
            print(String(format: "[BD] TIGHT rejected: side=%.0fpx vs locked %.0fpx", side, originalSidePx))
            return nil
        }

        let centerX = CGFloat(minX + maxX) / 2 + CGFloat(xStart)
        let centerY = CGFloat(minY + maxY) / 2 + CGFloat(yStart)
        let tight = CGRect(
            x: (centerX - side / 2) / CGFloat(width),
            y: (centerY - side / 2) / CGFloat(height),
            width: side / CGFloat(width),
            height: side / CGFloat(height)
        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        print(String(format: "[BD] TIGHT %.0fpx→%.0fpx core=%d (%.3f,%.3f %.3fx%.3f)",
                     originalSidePx, side, bestCluster.count,
                     tight.minX, tight.minY, tight.width, tight.height))
        return tight
    }
}

