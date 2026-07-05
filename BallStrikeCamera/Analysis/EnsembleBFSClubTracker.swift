// Analysis/EnsembleBFSClubTracker.swift
// EnsembleBFS club head detector for the live iOS pipeline.
// Algorithm mirrors ensemble_bfs.swift / club_lab.py ensembleBFS exactly.

import UIKit
import CoreGraphics

// Gated debug logging — off in normal runs (per-frame trace flooded the console + analysis thread).
private let kEBFSDebugLog = false
@inline(__always) private func dbg(_ message: @autoclosure () -> String) {
    if kEBFSDebugLog { Swift.print(message()) }
}

struct EnsembleBFSClubTracker {

    // MARK: - Internal types

    private struct EBFSFrame {
        let data: [UInt8]   // flat RGB, row-major, H*W*3
        let W: Int, H: Int
        func r(_ row: Int, _ col: Int) -> Float { Float(data[(row*W+col)*3])   }
        func g(_ row: Int, _ col: Int) -> Float { Float(data[(row*W+col)*3+1]) }
        func b(_ row: Int, _ col: Int) -> Float { Float(data[(row*W+col)*3+2]) }
    }

    private struct EBFSBallObs {
        let cx: Double, cy: Double, dia: Double
    }

    private struct EBFSContext {
        let frames: [Int: EBFSFrame]
        let sortedFrameIndices: [Int]
        let frameTimes: [Int: Double]   // frameIndex → relativeTime
        let W: Int, H: Int
        let impact: Int
        let fps: Double
        let ballObs: [Int: EBFSBallObs]
        let ballSpeedMph: Double
        let baselineGray: [Double]?     // H*W mean of first pre-swing frames
        let windowBg: [Double]?         // H*W mean of detection window frames
        let ballDepthM: Double?         // 3D ball depth from stereo/sfm pipeline
    }

    private struct EBFSMaskResult {
        let diffMap: [Double]
        let rows: Int, cols: Int
        let x0: Int, y0: Int
        let ball: EBFSBallObs
    }

    private struct EBFSDetection {
        var cx: Double, cy: Double
        var count: Int
        var leadX: Double = 0
        var leadY: Double = 0
        var predicted: Bool = false
        var synthetic: Bool = false
    }

    // Hardcoded params matching club_lab_state.json
    private struct EBFSParams {
        let exclusion:      Double = 1.003
        let roiX:           Double = 22.0
        let roiY:           Double = 7.066
        let skipNearImpact: Double = 1.98
        let fovX:           Double = 70.0
        let fovY:           Double = 45.0
        let ballDiamM:      Double = 0.04276
    }

    // MARK: - Public entry point

    func track(analysis: ShotAnalysisResult, ballSpeedMph knownBallSpeedMph: Double? = nil, ballDepthM knownBallDepthM: Double? = nil) -> [ClubObservation] {
        let p = EBFSParams()

        // Extract pixel data from UIImages
        var frameMap = [Int: EBFSFrame]()
        for f in analysis.frames {
            if let ef = extractFrame(f.originalFrame.image) {
                frameMap[f.frameIndex] = ef
            }
        }
        guard !frameMap.isEmpty,
              let firstIdx = frameMap.keys.min(),
              let firstFrame = frameMap[firstIdx] else { return [] }

        let W = firstFrame.W, H = firstFrame.H
        let sortedIndices = frameMap.keys.sorted()

        // Map ball observations
        var ballObs = [Int: EBFSBallObs]()
        for f in analysis.frames {
            guard let obs = f.ballObservation,
                  let cx = obs.centerX, let cy = obs.centerY,
                  let dia = obs.diameter,
                  obs.confidence > 0, dia > 0 else { continue }
            ballObs[f.frameIndex] = EBFSBallObs(cx: Double(cx), cy: Double(cy), dia: Double(dia))
        }

        // Frame relative times for speed computation
        let frameTimes: [Int: Double] = Dictionary(uniqueKeysWithValues: analysis.frames.map { ($0.frameIndex, $0.relativeTime) })

        let fps = computeFPS(analysis.frames)
        let impact = analysis.detectedImpactFrameIndex

        // Determine detection window
        var start = max((sortedIndices.first ?? 0) + 1, impact - 3)
        let end   = min(sortedIndices.last ?? 0, impact + 1)
        // Shift start forward until frame at start-1 exists for frame diff
        while start <= end && frameMap[start - 1] == nil { start += 1 }
        guard start <= end else { return [] }

        // Pre-compute backgrounds
        let baselineGray = buildBaselineGray(frameMap: frameMap, sortedIndices: sortedIndices,
                                             impact: impact, W: W, H: H)
        let windowBg = buildWindowBg(frameMap: frameMap, sortedIndices: sortedIndices,
                                     start: start, end: end, W: W, H: H)

        // Use caller-supplied ball speed when available (matches Python tester which reads
        // the pre-computed value from python_experimental_metrics.json). Fall back to
        // on-the-fly estimate only when no value is passed in.
        let ballSpeedMph = knownBallSpeedMph ?? estimateBallSpeed(frames: analysis.frames,
                                                                   ballObs: ballObs,
                                                                   W: W, H: H,
                                                                   impact: impact, p: p)

        let ctx = EBFSContext(
            frames: frameMap,
            sortedFrameIndices: sortedIndices,
            frameTimes: frameTimes,
            W: W, H: H,
            impact: impact,
            fps: fps,
            ballObs: ballObs,
            ballSpeedMph: ballSpeedMph,
            baselineGray: baselineGray,
            windowBg: windowBg,
            ballDepthM: knownBallDepthM
        )

        let ballImp = ballForFrame(ctx, impact)

        // ── DEBUG: input summary ───────────────────────────────────────────────
        dbg("[EBFS-DEBUG] ═══════════════════════════════════════════════════")
        dbg("[EBFS-DEBUG] impact=\(impact)  window=\(start)…\(end)  W=\(W) H=\(H)  fps=\(String(format:"%.2f",fps))")
        dbg("[EBFS-DEBUG] ballSpeedMph=\(String(format:"%.4f",ballSpeedMph)) (passed=\(knownBallSpeedMph.map{String(format:"%.4f",$0)} ?? "nil"))")
        dbg("[EBFS-DEBUG] ballDepthM=\(knownBallDepthM.map{String(format:"%.4f",$0)} ?? "nil")")
        if let bi = ballImp {
            dbg("[EBFS-DEBUG] ball@impact: cx=\(String(format:"%.5f",bi.cx)) cy=\(String(format:"%.5f",bi.cy)) dia=\(String(format:"%.5f",bi.dia))")
        } else {
            dbg("[EBFS-DEBUG] ball@impact: NONE")
        }
        dbg("[EBFS-DEBUG] ballObs frames: \(ballObs.keys.sorted())")
        for fi in ballObs.keys.sorted() {
            let b = ballObs[fi]!
            dbg("[EBFS-DEBUG]   fi=\(fi): cx=\(String(format:"%.5f",b.cx)) cy=\(String(format:"%.5f",b.cy)) dia=\(String(format:"%.5f",b.dia))")
        }
        // ──────────────────────────────────────────────────────────────────────

        let rawNd = runBFSSweep(ctx, method: "newDiff",   maskMethod: "bgDiff",
                                impact: impact, start: start, end: end, ballImp: ballImp, p: p)
        let rawBf = runBFSSweep(ctx, method: "brightBFS", maskMethod: "baseline",
                                impact: impact, start: start, end: end, ballImp: ballImp, p: p)

        // ── DEBUG: raw sweep results ───────────────────────────────────────────
        dbg("[EBFS-DEBUG] rawNd (\(rawNd.count)): \(rawNd.keys.sorted().map { fi -> String in let d=rawNd[fi]!; return "fi\(fi):(\(String(format:"%.4f",d.cx)),\(String(format:"%.4f",d.cy))) cnt=\(d.count)" }.joined(separator: "  "))")
        dbg("[EBFS-DEBUG] rawBf (\(rawBf.count)): \(rawBf.keys.sorted().map { fi -> String in let d=rawBf[fi]!; return "fi\(fi):(\(String(format:"%.4f",d.cx)),\(String(format:"%.4f",d.cy))) cnt=\(d.count)" }.joined(separator: "  "))")
        // ──────────────────────────────────────────────────────────────────────

        let ensemble = ensemblePoolAndFit(rawNd, rawBf, ctx: ctx,
                                          impact: impact, start: start, end: end, p: p)

        dbg("[EnsembleBFSClubTracker] nd=\(rawNd.count) bf=\(rawBf.count) kept=\(ensemble.count)")

        let frameByIndex = Dictionary(uniqueKeysWithValues: analysis.frames.map { ($0.frameIndex, $0) })
        return ensemble.keys.sorted().compactMap { fi -> ClubObservation? in
            guard let det = ensemble[fi] else { return nil }
            let af = frameByIndex[fi]
            return ClubObservation(
                frameIndex: fi,
                timestamp: af?.timestamp ?? 0,
                relativeTime: af?.relativeTime ?? 0,
                centerX: CGFloat(det.cx),
                centerY: CGFloat(det.cy),
                leadingEdgeX: det.leadX > 0 ? CGFloat(det.leadX) : nil,
                leadingEdgeY: det.leadY > 0 ? CGFloat(det.leadY) : nil,
                clubBoundingBox: nil,
                confidence: 0.80,
                searchROI: nil,
                ballExclusionCenterX: nil,
                ballExclusionCenterY: nil,
                ballExclusionDiameter: nil,
                debugReason: "ensembleBFS",
                detectionMode: "ensembleBFS",
                ballExclusionWasApplied: true,
                frameDifferenceWasUsed: true
            )
        }
    }

    // MARK: - Frame extraction

    private func extractFrame(_ image: UIImage) -> EBFSFrame? {
        guard let cg = image.cgImage else { return nil }
        let W = cg.width, H = cg.height
        guard W > 0, H > 0 else { return nil }
        var rgba = [UInt8](repeating: 0, count: W * H * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &rgba, width: W, height: H,
                                  bitsPerComponent: 8, bytesPerRow: W * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
        var rgb = [UInt8](repeating: 0, count: W * H * 3)
        for i in 0..<(W * H) {
            rgb[i*3] = rgba[i*4]; rgb[i*3+1] = rgba[i*4+1]; rgb[i*3+2] = rgba[i*4+2]
        }
        return EBFSFrame(data: rgb, W: W, H: H)
    }

    private func computeFPS(_ frames: [AnalyzedShotFrame]) -> Double {
        let sorted = frames.sorted { $0.frameIndex < $1.frameIndex }
        guard sorted.count >= 2 else { return 240.0 }
        var dts = [Double]()
        for i in 1..<sorted.count {
            let dt = sorted[i].relativeTime - sorted[i-1].relativeTime
            if dt > 1e-9 { dts.append(dt) }
        }
        guard !dts.isEmpty else { return 240.0 }
        let medDt = dts.sorted()[dts.count / 2]
        return medDt > 1e-9 ? 1.0 / medDt : 240.0
    }

    private func estimateBallSpeed(frames: [AnalyzedShotFrame], ballObs: [Int: EBFSBallObs],
                                   W: Int, H: Int, impact: Int, p: EBFSParams) -> Double {
        let fx = Double(W) / (2.0 * tan(p.fovX * .pi / 360.0))
        let fy = Double(H) / (2.0 * tan(p.fovY * .pi / 360.0))

        // Estimate depth from ball at impact
        let impBall = ballObs[impact] ?? ballObs.min(by: { abs($0.key - impact) < abs($1.key - impact) })?.value
        guard let impDia = impBall?.dia, impDia > 0 else { return 0 }
        let depthM = p.ballDiamM * fx / (impDia * Double(W))

        // Post-impact ball observations
        let postObs = frames
            .filter { $0.frameIndex > impact }
            .compactMap { f -> (t: Double, x: Double, y: Double)? in
                guard let obs = f.ballObservation,
                      let cx = obs.centerX, let cy = obs.centerY,
                      obs.confidence > 0 else { return nil }
                return (f.relativeTime, Double(cx), Double(cy))
            }
            .sorted { $0.t < $1.t }

        guard postObs.count >= 2 else { return 0 }
        let sel = Array(postObs.prefix(4))

        // 3D positions with constant z = depthM
        let pts = sel.map { obs -> (t: Double, X: Double, Y: Double) in
            let X = (obs.x - 0.5) * Double(W) / fx * depthM
            let Y = (obs.y - 0.5) * Double(H) / fy * depthM
            return (obs.t, X, Y)
        }

        if pts.count >= 3 {
            let meanT = pts.map(\.t).reduce(0, +) / Double(pts.count)
            let denom = pts.map { ($0.t - meanT) * ($0.t - meanT) }.reduce(0, +)
            guard denom > 0 else { return 0 }
            let vx = pts.map { ($0.t - meanT) * $0.X }.reduce(0, +) / denom
            let vy = pts.map { ($0.t - meanT) * $0.Y }.reduce(0, +) / denom
            return sqrt(vx*vx + vy*vy) * 2.23694
        } else {
            let dt = pts[1].t - pts[0].t
            guard dt > 1e-9 else { return 0 }
            let vx = (pts[1].X - pts[0].X) / dt
            let vy = (pts[1].Y - pts[0].Y) / dt
            return sqrt(vx*vx + vy*vy) * 2.23694
        }
    }

    // MARK: - Background computation

    private func buildBaselineGray(frameMap: [Int: EBFSFrame], sortedIndices: [Int],
                                   impact: Int, W: Int, H: Int) -> [Double]? {
        let n = min(5, max(1, impact - 4))
        guard n >= 1 else { return nil }
        let firstN = Array(sortedIndices.prefix(n))
        guard !firstN.isEmpty else { return nil }
        let WH = W * H
        var sum = [Double](repeating: 0, count: WH)
        var count = 0
        for fi in firstN {
            guard let fr = frameMap[fi] else { continue }
            for row in 0..<H {
                for col in 0..<W {
                    let i = row * W + col
                    sum[i] += Double(0.2989*fr.r(row,col) + 0.5870*fr.g(row,col) + 0.1140*fr.b(row,col))
                }
            }
            count += 1
        }
        guard count > 0 else { return nil }
        let nd = Double(count)
        return sum.map { $0 / nd }
    }

    private func buildWindowBg(frameMap: [Int: EBFSFrame], sortedIndices: [Int],
                               start: Int, end: Int, W: Int, H: Int) -> [Double]? {
        let window = sortedIndices.filter { $0 >= start && $0 <= end }
        guard !window.isEmpty else { return nil }
        let WH = W * H
        var sum = [Double](repeating: 0, count: WH)
        var count = 0
        for fi in window {
            guard let fr = frameMap[fi] else { continue }
            for row in 0..<H {
                for col in 0..<W {
                    let i = row * W + col
                    sum[i] += Double(0.2989*fr.r(row,col) + 0.5870*fr.g(row,col) + 0.1140*fr.b(row,col))
                }
            }
            count += 1
        }
        guard count > 0 else { return nil }
        let nd = Double(count)
        return sum.map { $0 / nd }
    }

    // MARK: - Ball lookup

    private func ballForFrame(_ ctx: EBFSContext, _ fi: Int) -> EBFSBallObs? {
        if let b = ctx.ballObs[fi] { return b }
        // Prefer last known observation BEFORE fi so that missing frames at/near impact
        // use the pre-impact static ball position rather than the post-launch position.
        // Using the launched ball position shifts the ROI and biases the club centroid.
        if let priorKey = ctx.ballObs.keys.filter({ $0 < fi }).max(),
           let b = ctx.ballObs[priorKey] { return b }
        return ctx.ballObs.min(by: { abs($0.key - fi) < abs($1.key - fi) })?.value
    }

    // MARK: - Geometry

    private func roiRect(ballCx: Double, ballCy: Double, ballDia: Double, p: EBFSParams)
                         -> (x0: Double, y0: Double, w: Double, h: Double) {
        let rw = ballDia * p.roiX, rh = ballDia * p.roiY
        // Bias the club-search ROI toward the side the club comes from (travel direction).
        let cx = ballCx - HitDirection.sign * rw * 0.40
        let x0 = max(0.0, cx - rw/2), y0 = max(0.0, ballCy - rh/2)
        let x1 = max(0.0, min(1.0, cx + rw/2)), y1 = max(0.0, min(1.0, ballCy + rh/2))
        return (x0, y0, x1-x0, y1-y0)
    }

    private func getPatch(_ frame: EBFSFrame,
                          roi: (x0: Double, y0: Double, w: Double, h: Double))
                          -> (data: [Float], rows: Int, cols: Int, x0: Int, y0: Int)? {
        let W = frame.W, H = frame.H
        let px0 = max(0, Int(roi.x0 * Double(W))), py0 = max(0, Int(roi.y0 * Double(H)))
        let px1 = min(W, Int((roi.x0+roi.w) * Double(W))), py1 = min(H, Int((roi.y0+roi.h) * Double(H)))
        let cols = px1 - px0, rows = py1 - py0
        guard cols > 0, rows > 0 else { return nil }
        var out = [Float](repeating: 0, count: rows * cols * 3)
        for row in 0..<rows {
            for col in 0..<cols {
                let si = ((py0+row)*W + (px0+col)) * 3
                let di = (row*cols + col) * 3
                out[di] = Float(frame.data[si])
                out[di+1] = Float(frame.data[si+1])
                out[di+2] = Float(frame.data[si+2])
            }
        }
        return (out, rows, cols, px0, py0)
    }

    // MARK: - Pixel math

    private func rgbToGray(_ d: [Float], rows: Int, cols: Int) -> [Double] {
        var g = [Double](repeating: 0, count: rows * cols)
        for i in 0..<(rows * cols) {
            g[i] = Double(0.2989*d[i*3] + 0.5870*d[i*3+1] + 0.1140*d[i*3+2])
        }
        return g
    }

    private func eraseBall(_ d: [Float], rows: Int, cols: Int,
                           cxRoi: Double, cyRoi: Double, diaPx: Double, scale: Double) -> [Float] {
        let r2 = pow(diaPx * max(scale, 0) / 2, 2)
        guard r2 >= 1 else { return d }
        var result = d
        var discIdx = [Int](), ringIdx = [Int]()
        for row in 0..<rows {
            let dy = Double(row) - cyRoi
            for col in 0..<cols {
                let dx = Double(col) - cxRoi
                let dist2 = dx*dx + dy*dy
                let i = row*cols + col
                if dist2 <= r2          { discIdx.append(i) }
                else if dist2 <= r2*4.0 { ringIdx.append(i) }
            }
        }
        guard !discIdx.isEmpty, !ringIdx.isEmpty else { return d }
        var fr = 0.0, fg = 0.0, fb = 0.0
        for i in ringIdx { fr += Double(d[i*3]); fg += Double(d[i*3+1]); fb += Double(d[i*3+2]) }
        let n = Double(ringIdx.count)
        let rv = Float(min(max(fr/n, 0), 255))
        let gv = Float(min(max(fg/n, 0), 255))
        let bv = Float(min(max(fb/n, 0), 255))
        for i in discIdx { result[i*3] = rv; result[i*3+1] = gv; result[i*3+2] = bv }
        return result
    }

    // MARK: - Diff map building

    private func buildMask(_ ctx: EBFSContext, fi: Int, method: String, p: EBFSParams) -> EBFSMaskResult? {
        guard let curFrame = ctx.frames[fi], let prevFrame = ctx.frames[fi - 1] else { return nil }
        guard let ball = ballForFrame(ctx, fi) else { return nil }
        let W = ctx.W, H = ctx.H

        let roi = roiRect(ballCx: ball.cx, ballCy: ball.cy, ballDia: ball.dia, p: p)
        guard let (rawCurr, rows, cols, x0, y0) = getPatch(curFrame,  roi: roi),
              let (rawPrev, _,    _,    _,  _)  = getPatch(prevFrame, roi: roi),
              rawCurr.count == rawPrev.count else { return nil }

        let bxRoi = ball.cx * Double(W) - Double(x0)
        let byRoi = ball.cy * Double(H) - Double(y0)
        let diaPx = ball.dia * Double(W)

        let skipImp    = Int(round(p.skipNearImpact))
        let nearImpact = abs(fi - ctx.impact) <= skipImp

        let patchC  = nearImpact ? rawCurr : eraseBall(rawCurr, rows: rows, cols: cols, cxRoi: bxRoi, cyRoi: byRoi, diaPx: diaPx, scale: 1.0)
        let patchPC = nearImpact ? rawPrev : eraseBall(rawPrev, rows: rows, cols: cols, cxRoi: bxRoi, cyRoi: byRoi, diaPx: diaPx, scale: 1.0)

        var diffMap = [Double](repeating: 0, count: rows * cols)

        switch method {
        case "bgDiff":
            if let bg = ctx.windowBg {
                let grayCurr = rgbToGray(patchC, rows: rows, cols: cols)
                for row in 0..<rows {
                    for col in 0..<cols {
                        let i = row*cols + col
                        let bgVal = bg[(row+y0)*W + (col+x0)]
                        diffMap[i] = abs(grayCurr[i] - bgVal)
                    }
                }
            }
        case "baseline":
            if let base = ctx.baselineGray {
                let grayOrig = rgbToGray(rawCurr, rows: rows, cols: cols)
                for row in 0..<rows {
                    for col in 0..<cols {
                        let i = row*cols + col
                        let bv = base[(row+y0)*W + (col+x0)]
                        let dark   = max(bv - grayOrig[i], 0.0)
                        let bright = max(grayOrig[i] - bv, 0.0)
                        diffMap[i] = max(dark, bright)
                    }
                }
            } else {
                let gc = rgbToGray(patchC,  rows: rows, cols: cols)
                let gp = rgbToGray(patchPC, rows: rows, cols: cols)
                for i in 0..<(rows*cols) { diffMap[i] = abs(gc[i] - gp[i]) }
            }
        default:
            let gc = rgbToGray(patchC,  rows: rows, cols: cols)
            let gp = rgbToGray(patchPC, rows: rows, cols: cols)
            for i in 0..<(rows*cols) { diffMap[i] = abs(gc[i] - gp[i]) }
        }

        // Fill ball disc with surrounding annulus median for non-near-impact frames
        if !nearImpact {
            let ballRFill = diaPx / 2
            let r2   = ballRFill * ballRFill
            let r2a  = ballRFill * ballRFill * 3.24
            var discIdx = [Int](), annIdx = [Int]()
            for row in 0..<rows {
                let dy = Double(row) - byRoi
                for col in 0..<cols {
                    let dx = Double(col) - bxRoi
                    let d2 = dx*dx + dy*dy
                    let i  = row*cols + col
                    if d2 <= r2       { discIdx.append(i) }
                    else if d2 <= r2a { annIdx.append(i) }
                }
            }
            if !discIdx.isEmpty && !annIdx.isEmpty {
                let annVals = annIdx.map { diffMap[$0] }.sorted()
                let med = annVals[annVals.count / 2]
                for i in discIdx { diffMap[i] = med }
            }
        }

        return EBFSMaskResult(diffMap: diffMap, rows: rows, cols: cols, x0: x0, y0: y0, ball: ball)
    }

    // MARK: - BFS blob detection

    private func rightmostBlobFromDiff(_ dm: [Double], rows: Int, cols: Int,
                                       leftmost: Bool, thrScale: Double) -> [(row: Int, col: Int)] {
        guard let peak = dm.max(), peak > 1e-6 else { return [] }
        let norm = dm.map { $0 / peak }
        let minPx = 50
        let nbrs: [(Int, Int)] = [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)]

        func label(thr: Double) -> [[(row: Int, col: Int)]] {
            var visited = [Bool](repeating: false, count: rows*cols)
            var found   = [[(row: Int, col: Int)]]()
            for r0 in 0..<rows {
                for c0 in 0..<cols {
                    let i0 = r0*cols + c0
                    guard norm[i0] >= thr, !visited[i0] else { continue }
                    var comp = [(row: Int, col: Int)]()
                    var queue = [(r0, c0)]
                    var head  = 0
                    visited[i0] = true
                    while head < queue.count {
                        let (r, c) = queue[head]; head += 1
                        comp.append((r, c))
                        for (dr, dc) in nbrs {
                            let nr = r+dr, nc = c+dc
                            guard nr >= 0, nr < rows, nc >= 0, nc < cols else { continue }
                            let ni = nr*cols + nc
                            guard norm[ni] >= thr, !visited[ni] else { continue }
                            visited[ni] = true
                            queue.append((nr, nc))
                        }
                    }
                    if comp.count >= minPx { found.append(comp) }
                }
            }
            return found
        }

        for base in [0.30, 0.20, 0.12, 0.07, 0.04] {
            let blobs = label(thr: base * thrScale)
            guard !blobs.isEmpty else { continue }
            if leftmost {
                return blobs.min(by: { meanCol($0) < meanCol($1) })!
            }
            return blobs.max(by: { meanCol($0) < meanCol($1) })!
        }
        return []
    }

    private func meanCol(_ comp: [(row: Int, col: Int)]) -> Double {
        comp.reduce(0.0) { $0 + Double($1.col) } / Double(comp.count)
    }

    private func componentToBlob(_ comp: [(row: Int, col: Int)], x0: Int, y0: Int,
                                  W: Int, H: Int, refBx: Double, refBy: Double) -> EBFSDetection? {
        guard !comp.isEmpty else { return nil }
        let pxs = comp.map { Double($0.col + x0) }
        let pys = comp.map { Double($0.row + y0) }
        let n   = Double(comp.count)
        let cx  = pxs.reduce(0, +) / n
        let cy  = pys.reduce(0, +) / n

        let dists = (0..<comp.count).map { k -> Double in
            let dx = pxs[k] - refBx, dy = pys[k] - refBy
            return dx*dx + dy*dy
        }
        let faceN = max(1, comp.count / 3)
        let faceIdx = dists.indices.sorted { dists[$0] < dists[$1] }.prefix(faceN)
        var sumFX = 0.0, sumFY = 0.0
        for k in faceIdx { sumFX += pxs[k]; sumFY += pys[k] }
        let fn    = Double(faceN)
        let leadX = sumFX / fn / Double(W)
        let leadY = sumFY / fn / Double(H)

        return EBFSDetection(cx: cx/Double(W), cy: cy/Double(H), count: comp.count,
                             leadX: leadX, leadY: leadY)
    }

    private func findBlobsStreakBFS(_ mr: EBFSMaskResult, ctx: EBFSContext, p: EBFSParams,
                                    impactFi: Int, fi: Int, method: String) -> [EBFSDetection] {
        let W = ctx.W, H = ctx.H
        let rows = mr.rows, cols = mr.cols
        let ball = mr.ball
        let x0 = mr.x0, y0 = mr.y0
        let bxF = ball.cx * Double(W), byF = ball.cy * Double(H)
        let ballR = ball.dia * Double(W) / 2
        let exclR = ballR * p.exclusion

        guard let peak = mr.diffMap.max(), peak > 1e-6 else { return [] }
        var dmDet = mr.diffMap.map { $0 / peak }

        let post = fi > impactFi

        if method == "newDiff" {
            if fi <= impactFi {
                let ballCol = Int(round(bxF)) - x0
                if ballCol >= 0 && ballCol < cols {
                    for row in 0..<rows {
                        for col in ballCol..<cols { dmDet[row*cols+col] = 0.0 }
                    }
                }
            } else {
                let exclR2 = exclR * exclR
                for row in 0..<rows {
                    let dy = Double(row + y0) - byF
                    for col in 0..<cols {
                        let dx = Double(col + x0) - bxF
                        if dx*dx + dy*dy <= exclR2 { dmDet[row*cols+col] = 0.0 }
                    }
                }
            }
        } else {
            // brightBFS
            if fi < impactFi {
                let exclR2 = exclR * exclR
                for row in 0..<rows {
                    let dy = Double(row + y0) - byF
                    for col in 0..<cols {
                        let dx = Double(col + x0) - bxF
                        if dx*dx + dy*dy <= exclR2 { dmDet[row*cols+col] = 0.0 }
                    }
                }
            } else if fi > impactFi {
                let ballR2 = ballR * ballR
                for row in 0..<rows {
                    let dy = Double(row + y0) - byF
                    for col in 0..<cols {
                        let dx = Double(col + x0) - bxF
                        if dx*dx + dy*dy <= ballR2 { dmDet[row*cols+col] = 0.0 }
                    }
                }
            }
            // fi == impactFi: no masking
        }

        let thrScale = method == "newDiff" ? 0.65 : 1.0
        // Leading club edge is on the travel-forward side; reversed hit flips which column that is.
        let leadingIsLeft = HitDirection.reversed ? !post : post
        let comp = rightmostBlobFromDiff(dmDet, rows: rows, cols: cols, leftmost: leadingIsLeft, thrScale: thrScale)
        guard !comp.isEmpty else { return [] }
        guard let blob = componentToBlob(comp, x0: x0, y0: y0, W: W, H: H, refBx: bxF, refBy: byF) else { return [] }
        return [blob]
    }

    // MARK: - Filtering

    private func dedupConsecutiveDets(_ dets: inout [Int: EBFSDetection], W: Int, H: Int) {
        let ordered = dets.keys.sorted()
        for i in 1..<ordered.count {
            let a = ordered[i-1], b = ordered[i]
            guard let da = dets[a], let db = dets[b] else { continue }
            let dx = abs(da.cx - db.cx) * Double(W)
            let dy = abs(da.cy - db.cy) * Double(H)
            if hypot(dx, dy) < 4.0 { dets.removeValue(forKey: a) }
        }
    }

    private func applyMonotonicity(_ dets: inout [Int: EBFSDetection], ctx: EBFSContext, ballImp: EBFSBallObs?) {
        guard let ball = ballImp else { return }
        let W = ctx.W, tol = 5.0 / Double(W), impact = ctx.impact
        let ballCx = ball.cx
        let s = HitDirection.sign   // +1 left→right, −1 right→left; s·cx is "progress toward impact"

        // Pre-impact club must be on the side the ball travels FROM (behind ball along travel).
        for fi in dets.keys where fi < impact {
            if let d = dets[fi], s * (d.cx - ballCx) >= 0 { dets.removeValue(forKey: fi) }
        }

        var ordered = dets.compactMap { k, v -> (Int, Double)? in k < impact ? (k, v.cx) : nil }
                          .sorted { $0.0 < $1.0 }
        guard !ordered.isEmpty else { return }

        // Furthest-behind (start) detection in travel direction: min of s·cx.
        let start = ordered.min(by: { s * $0.1 < s * $1.1 })!
        let startCx = start.1, startFi = start.0
        for (fi, cx) in ordered where fi < startFi && s * cx > s * startCx + tol {
            dets.removeValue(forKey: fi)
        }

        ordered = dets.compactMap { k, v -> (Int, Double)? in k < impact ? (k, v.cx) : nil }
                      .sorted { $0.0 < $1.0 }
        guard ordered.count >= 2 else { return }
        // Monotonic progress: s·cx must be non-decreasing over time toward impact.
        var frontier = s * ordered[0].1
        for i in 1..<ordered.count {
            let (fi, cx) = ordered[i]
            if s * cx < frontier - tol { dets.removeValue(forKey: fi) }
            else { frontier = max(frontier, s * cx) }
        }
    }

    // MARK: - BFS sweep

    private func runBFSSweep(_ ctx: EBFSContext, method: String, maskMethod: String,
                              impact: Int, start: Int, end: Int,
                              ballImp: EBFSBallObs?, p: EBFSParams) -> [Int: EBFSDetection] {
        var rawDets = [Int: EBFSDetection]()
        for fi in start...end {
            if let mr = buildMask(ctx, fi: fi, method: maskMethod, p: p) {
                let blobs = findBlobsStreakBFS(mr, ctx: ctx, p: p, impactFi: impact, fi: fi, method: method)
                if let b = blobs.first { rawDets[fi] = b }
            }
        }
        dedupConsecutiveDets(&rawDets, W: ctx.W, H: ctx.H)
        if method == "newDiff" || method == "ensembleBFS" {
            applyMonotonicity(&rawDets, ctx: ctx, ballImp: ballImp)
        }
        return rawDets
    }

    // MARK: - Club speed (for smash guard)

    private func computeClubSpeed(_ ctx: EBFSContext, dets: [Int: EBFSDetection], p: EBFSParams) -> Double? {
        let W = ctx.W, H = ctx.H, impact = ctx.impact
        let fx = Double(W) / (2.0 * tan(p.fovX * .pi / 360.0))
        let fy = Double(H) / (2.0 * tan(p.fovY * .pi / 360.0))

        guard let ballImp = ballForFrame(ctx, impact) else { return nil }
        let depthM = ctx.ballDepthM ?? (p.ballDiamM * fx / max(ballImp.dia * Double(W), 1.0))

        var spdPts = [(t: Double, x: Double, y: Double)]()
        for fi in dets.keys.sorted() {
            let blob = dets[fi]!
            if blob.predicted || fi > impact { continue }
            if blob.synthetic && fi != impact { continue }
            let t = ctx.frameTimes[fi] ?? Double(fi) / ctx.fps
            let X = (blob.cx - 0.5) * Double(W) / fx * depthM
            let Y = (blob.cy - 0.5) * Double(H) / fy * depthM
            spdPts.append((t, X, Y))
        }
        guard spdPts.count >= 2 else { return nil }

        var pairSpeeds = [Double]()
        for i in 0..<spdPts.count {
            for j in (i+1)..<spdPts.count {
                let a = spdPts[i], b = spdPts[j]
                let dt = b.t - a.t
                guard dt > 1e-9 else { continue }
                let dx = b.x - a.x, dy = b.y - a.y
                pairSpeeds.append(sqrt(dx*dx + dy*dy) / dt * 2.23694)
            }
        }
        guard !pairSpeeds.isEmpty else { return nil }

        let sorted = pairSpeeds.sorted()
        let good: [Double]
        if sorted.count >= 2 {
            let q1 = sorted[sorted.count/4], q3 = sorted[3*sorted.count/4]
            let iqr = q3 - q1
            let lo = q1 - 1.5*iqr, hi = q3 + 1.5*iqr
            let filtered = sorted.filter { $0 >= lo && $0 <= hi }
            good = filtered.isEmpty ? sorted : filtered
        } else {
            good = sorted
        }
        return good.reduce(0, +) / Double(good.count)
    }

    // MARK: - Ensemble pool and fit

    private func ensemblePoolAndFit(_ rawNd: [Int: EBFSDetection], _ rawBf: [Int: EBFSDetection],
                                    ctx: EBFSContext, impact: Int, start: Int, end: Int,
                                    p: EBFSParams) -> [Int: EBFSDetection] {
        let W = ctx.W, H = ctx.H
        guard let ballImp = ballForFrame(ctx, impact) else { return [:] }
        let ballCx = ballImp.cx, ballCy = ballImp.cy

        // Median blob count
        var allCounts = rawNd.values.map { $0.count } + rawBf.values.map { $0.count }
        let medCount: Double
        if allCounts.isEmpty { medCount = 100.0 }
        else {
            allCounts.sort()
            medCount = allCounts.count % 2 == 0
                ? Double(allCounts[allCounts.count/2-1] + allCounts[allCounts.count/2]) / 2
                : Double(allCounts[allCounts.count/2])
        }

        // Step 1: pick best candidate per frame
        var result = [Int: EBFSDetection]()
        for fi in start...end {
            let nd = rawNd[fi], bf = rawBf[fi]
            if nd == nil && bf == nil { continue }
            else if nd == nil   { result[fi] = bf! }
            else if bf == nil   { result[fi] = nd! }
            else {
                let n = nd!, b = bf!
                let ndDiff = abs(Double(n.count) - medCount)
                let bfDiff = abs(Double(b.count) - medCount)
                result[fi] = ndDiff <= bfDiff ? n : b
            }
        }
        dbg("[EBFS-DEBUG] step1 medCount=\(Int(medCount)) after pick-best: \(result.keys.sorted().map{"fi\($0):(\(String(format:"%.4f",result[$0]!.cx)),\(String(format:"%.4f",result[$0]!.cy)))"}.joined(separator:"  "))")

        // Step 1.5: reject near-duplicate (< 6px)
        var prevCx: Double? = nil, prevCy: Double? = nil
        for fi in (start...end).sorted() {
            guard let det = result[fi] else { continue }
            if let pcx = prevCx, let pcy = prevCy {
                let distPx = hypot((det.cx - pcx) * Double(W), (det.cy - pcy) * Double(H))
                if distPx < 6.0 {
                    let nd = rawNd[fi], bf = rawBf[fi]
                    let chosen = result[fi]!
                    let isNd = nd.map { abs($0.cx - chosen.cx) < 1e-9 && abs($0.cy - chosen.cy) < 1e-9 } ?? false
                    let alt: EBFSDetection? = isNd ? bf : nd
                    if let a = alt {
                        let altDist = hypot((a.cx - pcx) * Double(W), (a.cy - pcy) * Double(H))
                        if altDist >= 6.0 { result[fi] = a } else { result.removeValue(forKey: fi) }
                    } else {
                        result.removeValue(forKey: fi)
                    }
                    if result[fi] == nil { continue }
                }
            }
            if let d = result[fi] { prevCx = d.cx; prevCy = d.cy }
        }

        dbg("[EBFS-DEBUG] step1.5 after near-dup reject: \(result.keys.sorted().map{"fi\($0):(\(String(format:"%.4f",result[$0]!.cx)),\(String(format:"%.4f",result[$0]!.cy)))"}.joined(separator:"  "))")

        // Step 2: confirmed set (both methods agree within 15px)
        var confirmed = Set<Int>()
        for fi in start...end {
            if let n = rawNd[fi], let b = rawBf[fi] {
                let dist = hypot((n.cx - b.cx) * Double(W), (n.cy - b.cy) * Double(H))
                if dist < 15.0 { confirmed.insert(fi) }
            }
        }

        dbg("[EBFS-DEBUG] step2 confirmed frames: \(confirmed.sorted())")

        // Step 3: hard physics filters. `s·cx` is progress toward impact (see HitDirection).
        let tolX = 5.0 / Double(W), tolY = 0.12
        let s = HitDirection.sign
        var frontierCx: Double? = nil   // stored in s·cx space (monotone non-decreasing)
        for fi in (start...end).sorted() {
            guard let det = result[fi] else { continue }
            if confirmed.contains(fi) {
                if fi < impact { frontierCx = frontierCx.map { max($0, s * det.cx) } ?? s * det.cx }
                continue
            }
            let cx = det.cx, cy = det.cy
            if fi < impact {
                if s * (cx - ballCx) >= 0 { result.removeValue(forKey: fi); continue }
                if cy < ballCy - tolY { result.removeValue(forKey: fi); continue }
                if let fc = frontierCx, s * cx < fc - tolX { result.removeValue(forKey: fi); continue }
                frontierCx = frontierCx.map { max($0, s * cx) } ?? s * cx
            }
        }

        dbg("[EBFS-DEBUG] step3 after physics: \(result.keys.sorted().map{"fi\($0):(\(String(format:"%.4f",result[$0]!.cx)),\(String(format:"%.4f",result[$0]!.cy)))"}.joined(separator:"  "))")

        // Step 4: LOO polynomial outlier removal (≥5 points, threshold 40px)
        for _ in 0..<10 {
            let real = result.sorted { $0.key < $1.key }
            guard real.count >= 5 else { break }
            let fisArr = real.map { Double($0.key) }
            let cxsArr = real.map { $0.value.cx * Double(W) }
            var worstFi: Int? = nil, worstResid = 40.0
            for i in 0..<real.count {
                let fi = real[i].key
                guard !confirmed.contains(fi) else { continue }
                var fLoo = [Double](), cLoo = [Double]()
                for j in 0..<real.count where j != i { fLoo.append(fisArr[j]); cLoo.append(cxsArr[j]) }
                guard fLoo.count >= 2 else { continue }
                let pred  = polyFitEval(x: fLoo, y: cLoo, degree: min(2, fLoo.count-1), at: fisArr[i])
                let resid = abs(cxsArr[i] - pred)
                if resid > worstResid { worstResid = resid; worstFi = fi }
            }
            guard let wfi = worstFi else { break }
            dbg("[EBFS-DEBUG] step4 LOO removed fi=\(wfi) resid=\(String(format:"%.1f",worstResid))px")
            result.removeValue(forKey: wfi)
        }
        dbg("[EBFS-DEBUG] step4 after LOO: \(result.keys.sorted().map{"fi\($0):(\(String(format:"%.4f",result[$0]!.cx)),\(String(format:"%.4f",result[$0]!.cy)))"}.joined(separator:"  "))")

        // Step 4b: backwards-pair cleanup
        let prePts = result.filter { $0.key < impact }.sorted { $0.key < $1.key }
        if prePts.count == 2 {
            let fiA = prePts[0].key, dA = prePts[0].value
            let dB  = prePts[1].value
            // Later frame must have advanced in travel direction; else drop the earlier point.
            if HitDirection.sign * dB.cx < HitDirection.sign * dA.cx { result.removeValue(forKey: fiA) }
        }

        // Step 4b log
        dbg("[EBFS-DEBUG] step4b after backwards-pair: \(result.keys.sorted().map{"fi\($0)"}.joined(separator:" "))")

        // Step 5: smash guard (iteratively remove worst point until smash ≤ 1.55)
        let ballSpd = ctx.ballSpeedMph
        if ballSpd > 0 {
            if let csInit = computeClubSpeed(ctx, dets: result, p: p) {
                dbg("[EBFS-DEBUG] step5 smash guard: ballSpd=\(String(format:"%.3f",ballSpd)) clubSpd=\(String(format:"%.3f",csInit)) smash=\(String(format:"%.4f",ballSpd/csInit)) depth=\(ctx.ballDepthM.map{String(format:"%.4f",$0)} ?? "dia-derived")")
            } else {
                dbg("[EBFS-DEBUG] step5 smash guard: ballSpd=\(String(format:"%.3f",ballSpd)) clubSpd=nil — guard skipped")
            }
            for _ in 0...(result.count + 1) {
                guard result.count >= 2 else { break }
                guard let cs = computeClubSpeed(ctx, dets: result, p: p), cs > 1e-3 else { break }
                if ballSpd / cs <= 1.55 { break }
                var bestFi: Int? = nil, bestSmash = Double.infinity
                for fiTry in result.keys {
                    var test = result; test.removeValue(forKey: fiTry)
                    guard test.count >= 2,
                          let cs2 = computeClubSpeed(ctx, dets: test, p: p), cs2 > 1e-3 else { continue }
                    let smash = ballSpd / cs2
                    if smash < bestSmash { bestSmash = smash; bestFi = fiTry }
                }
                guard let bfi = bestFi else { break }
                dbg("[EBFS-DEBUG] step5 smash guard removed fi=\(bfi) → new smash would be \(String(format:"%.4f",bestSmash))")
                result.removeValue(forKey: bfi)
            }
        } else {
            dbg("[EBFS-DEBUG] step5 smash guard SKIPPED (ballSpd=0)")
        }
        dbg("[EBFS-DEBUG] FINAL kept=\(result.count): \(result.keys.sorted().map { fi -> String in let d=result[fi]!; return "fi\(fi):cx=\(String(format:"%.5f",d.cx*Double(W)))px cy=\(String(format:"%.5f",d.cy*Double(H)))px" }.joined(separator:"  "))")
        dbg("[EBFS-DEBUG] ═══════════════════════════════════════════════════")

        return result
    }

    // MARK: - Polynomial helpers

    private func polyFitEval(x: [Double], y: [Double], degree: Int, at x0: Double) -> Double {
        let n = x.count, deg = min(degree, n-1), m = deg + 1
        var A = [[Double]](repeating: [Double](repeating: 0, count: m), count: n)
        for i in 0..<n {
            var xp = 1.0
            for j in 0...deg { A[i][deg-j] = xp; xp *= x[i] }
        }
        var AtA = [[Double]](repeating: [Double](repeating: 0, count: m), count: m)
        var Aty = [Double](repeating: 0, count: m)
        for i in 0..<n {
            for j in 0..<m {
                Aty[j] += A[i][j] * y[i]
                for k in 0..<m { AtA[j][k] += A[i][j] * A[i][k] }
            }
        }
        guard let coeffs = gaussSolve(AtA, Aty) else { return y[n/2] }
        var val = 0.0, xp = 1.0
        for j in stride(from: m-1, through: 0, by: -1) { val += coeffs[j] * xp; xp *= x0 }
        return val
    }

    private func gaussSolve(_ A: [[Double]], _ b: [Double]) -> [Double]? {
        let n = b.count
        var M = (0..<n).map { i in A[i] + [b[i]] }
        for col in 0..<n {
            guard let pivotRow = (col..<n).max(by: { abs(M[$0][col]) < abs(M[$1][col]) }) else { return nil }
            M.swapAt(col, pivotRow)
            let pivot = M[col][col]
            guard abs(pivot) > 1e-12 else { return nil }
            for row in (col+1)..<n {
                let f = M[row][col] / pivot
                for j in col...n { M[row][j] -= f * M[col][j] }
            }
        }
        var x = [Double](repeating: 0, count: n)
        for i in stride(from: n-1, through: 0, by: -1) {
            var s = M[i][n]
            for j in (i+1)..<n { s -= M[i][j] * x[j] }
            x[i] = s / M[i][i]
        }
        return x
    }
}
