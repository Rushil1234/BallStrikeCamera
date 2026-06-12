// ensemble_bfs.swift  —  EnsembleBFS club head detector, pure Swift CLI
// Mirrors the Python _ensemble_pool_and_fit pipeline in club_lab.py exactly.
//
// Build:  swiftc -O ensemble_bfs.swift -o ensemble_bfs
// Usage:  ./ensemble_bfs <shot_folder> '<params_json>'
// Stdout: {"detections":[{"frame":N,"cx":f,"cy":f,"count":N},...]}

import Foundation
import CoreGraphics
import ImageIO

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Data types
// ─────────────────────────────────────────────────────────────────────────────

struct Params {
    var diffThresh:     Double = 7.731
    var exclusion:      Double = 1.003
    var roiX:           Double = 22.0
    var roiY:           Double = 6.0
    var dilate:         Double = 2.0
    var skipNearImpact: Double = 2.0
    var fovX:           Double = 70.0
    var fovY:           Double = 45.0
    var ballDiamM:      Double = 0.04276

    init(_ json: [String: Any]) {
        func d(_ k: String, _ def: Double) -> Double { (json[k] as? Double) ?? def }
        diffThresh     = d("diff_thresh",      diffThresh)
        exclusion      = d("exclusion",        exclusion)
        roiX           = d("roi_x",            roiX)
        roiY           = d("roi_y",            roiY)
        dilate         = d("dilate",           dilate)
        skipNearImpact = d("skip_near_impact", skipNearImpact)
        fovX           = d("fov_x",            fovX)
        fovY           = d("fov_y",            fovY)
        ballDiamM      = d("ball_diam_m",      ballDiamM)
    }
}

struct BallObs {
    let cx: Double   // 0-1 normalised in frame
    let cy: Double
    let dia: Double
}

// Flat RGB [UInt8], row-major, length H*W*3
struct Frame {
    let data: [UInt8]
    let W: Int, H: Int

    func r(_ row: Int, _ col: Int) -> Float { Float(data[(row*W+col)*3])   }
    func g(_ row: Int, _ col: Int) -> Float { Float(data[(row*W+col)*3+1]) }
    func b(_ row: Int, _ col: Int) -> Float { Float(data[(row*W+col)*3+2]) }
}

struct ShotData {
    let name: String
    let frames: [Frame]
    let W: Int, H: Int, N: Int
    let impact: Int
    let fps: Double
    let ballObs: [Int: BallObs]
    let ballDepthM: Double?
    let ballSpeedMph: Double
}

struct MaskResult {
    let diffMap: [Double]   // rows*cols flat, with ball-disc annulus fill applied
    let rows: Int, cols: Int
    let x0: Int, y0: Int    // pixel offset of ROI in full frame
    let ball: BallObs
}

struct Detection {
    var cx: Double          // normalised 0-1 in frame
    var cy: Double
    var count: Int
    var leadX: Double = 0
    var leadY: Double = 0
    var passId: Int = 1
    var predicted: Bool = false
    var synthetic: Bool = false
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Image loading
// ─────────────────────────────────────────────────────────────────────────────

func loadPNG(_ path: String) -> Frame? {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let src = CGImageSourceCreateWithURL(url, nil),
          let cg  = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    let W = cg.width, H = cg.height
    var rgba = [UInt8](repeating: 0, count: W * H * 4)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: &rgba, width: W, height: H,
                        bitsPerComponent: 8, bytesPerRow: W * 4, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
    // RGBA → RGB (alpha ≈ 255 for all camera frames)
    var rgb = [UInt8](repeating: 0, count: W * H * 3)
    for i in 0..<(W*H) { rgb[i*3]=rgba[i*4]; rgb[i*3+1]=rgba[i*4+1]; rgb[i*3+2]=rgba[i*4+2] }
    return Frame(data: rgb, W: W, H: H)
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Shot loading
// ─────────────────────────────────────────────────────────────────────────────

func loadShot(_ folder: String) -> ShotData? {
    let fm = FileManager.default
    let pngs: [String] = ((try? fm.contentsOfDirectory(atPath: folder)) ?? [])
        .filter { $0.hasPrefix("frame_") && $0.hasSuffix(".png") }
        .sorted()
        .map { (folder as NSString).appendingPathComponent($0) }
    guard !pngs.isEmpty, let first = loadPNG(pngs[0]) else { return nil }

    var frames = [Frame](); frames.reserveCapacity(pngs.count)
    for p in pngs { guard let f = loadPNG(p) else { return nil }; frames.append(f) }

    let W = first.W, H = first.H, N = frames.count
    var impact = 20, fps = 240.0

    func readJSON(_ name: String) -> [String: Any]? {
        let p = (folder as NSString).appendingPathComponent(name)
        guard let d = try? Data(contentsOf: URL(fileURLWithPath: p)) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }

    if let m = readJSON("metadata.json") {
        impact = (m["impact_frame_index"] as? Int)    ?? impact
        fps    = (m["fps_estimate"]       as? Double) ?? fps
    }

    var ballObs = [Int: BallObs]()
    if let t = readJSON("tracking.json"),
       let obs = t["observations"] as? [[String: Any]] {
        for o in obs {
            let fi = (o["frame_index"] as? Int) ?? (o["frameIndex"] as? Int) ?? 0
            let det = (o["detected"] as? Bool) ?? false
            let conf = (o["confidence"] as? Double) ?? 0.0
            guard det || conf > 0 else { continue }
            if let cx  = o["center_x"]  as? Double,
               let cy  = o["center_y"]  as? Double,
               let dia = o["diameter"]  as? Double {
                ballObs[fi] = BallObs(cx: cx, cy: cy, dia: dia)
            }
        }
    }

    var ballDepthM: Double? = nil, ballSpeedMph = 0.0
    if let e = readJSON("python_experimental_metrics.json") {
        if let i = e["detectedImpactFrameIndex"] as? Int { impact = i }
        if let m = e["metrics"] as? [String: Any],
           let bs = m["ballSpeedMph"] as? Double { ballSpeedMph = bs }
        if let b3d = e["ball3DObservations"] as? [[String: Any]], !b3d.isEmpty {
            let closest = b3d.min(by: {
                abs(($0["frameIndex"] as? Int ?? 0) - impact) <
                abs(($1["frameIndex"] as? Int ?? 0) - impact)
            })
            if let pos = closest?["positionMeters"] as? [String: Double],
               let z = pos["z"], z > 0.1 { ballDepthM = z }
        }
    }

    return ShotData(name: (folder as NSString).lastPathComponent,
                    frames: frames, W: W, H: H, N: N, impact: impact, fps: fps,
                    ballObs: ballObs, ballDepthM: ballDepthM, ballSpeedMph: ballSpeedMph)
}

func ballForFrame(_ shot: ShotData, _ fi: Int) -> BallObs? {
    if let b = shot.ballObs[fi] { return b }
    return shot.ballObs.min(by: { abs($0.key - fi) < abs($1.key - fi) })?.value
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Geometry
// ─────────────────────────────────────────────────────────────────────────────

func roiRect(ballCx: Double, ballCy: Double, ballDia: Double, p: Params)
             -> (x0: Double, y0: Double, w: Double, h: Double) {
    let rw = ballDia * p.roiX, rh = ballDia * p.roiY
    let cx = ballCx - rw * 0.40
    let x0 = max(0.0, cx - rw/2), y0 = max(0.0, ballCy - rh/2)
    let x1 = max(0.0, min(1.0, cx + rw/2)), y1 = max(0.0, min(1.0, ballCy + rh/2))
    return (x0, y0, x1-x0, y1-y0)
}

func getPatch(_ frame: Frame,
              roi: (x0: Double, y0: Double, w: Double, h: Double))
             -> (data: [Float], rows: Int, cols: Int, x0: Int, y0: Int)? {
    let W = frame.W, H = frame.H
    let px0 = max(0, Int(roi.x0 * Double(W))), py0 = max(0, Int(roi.y0 * Double(H)))
    let px1 = min(W, Int((roi.x0+roi.w) * Double(W))), py1 = min(H, Int((roi.y0+roi.h) * Double(H)))
    let cols = px1-px0, rows = py1-py0
    guard cols > 0, rows > 0 else { return nil }
    var out = [Float](repeating: 0, count: rows*cols*3)
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

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Pixel math
// ─────────────────────────────────────────────────────────────────────────────

func rgbToGray(_ d: [Float], rows: Int, cols: Int) -> [Double] {
    var g = [Double](repeating: 0, count: rows*cols)
    for i in 0..<(rows*cols) {
        g[i] = Double(0.2989*d[i*3] + 0.5870*d[i*3+1] + 0.1140*d[i*3+2])
    }
    return g
}

// Erase ball disc (radius = diaPx*scale/2) with surrounding ring mean
func eraseBall(_ d: [Float], rows: Int, cols: Int,
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

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Background computation (cached per shot)
// ─────────────────────────────────────────────────────────────────────────────

var baselineCache  = [String: [Double]]()     // name → full-frame gray H*W
var windowBgCache  = [String: [Double]]()     // "name:s:e" → full-frame gray H*W

func getBaselineFrame(_ shot: ShotData) -> [Double]? {
    if let c = baselineCache[shot.name] { return c }
    let n = min(5, max(1, shot.impact - 4))
    guard n >= 1 else { return nil }
    let WH = shot.W * shot.H
    var sum = [Double](repeating: 0, count: WH)
    for fi in 0..<n {
        let fr = shot.frames[fi]
        for row in 0..<shot.H {
            for col in 0..<shot.W {
                let i = row*shot.W + col
                sum[i] += Double(0.2989*fr.r(row,col) + 0.5870*fr.g(row,col) + 0.1140*fr.b(row,col))
            }
        }
    }
    let nd = Double(n)
    let result = sum.map { $0 / nd }
    baselineCache[shot.name] = result
    return result
}

func getWindowBg(_ shot: ShotData, start: Int, end: Int) -> [Double]? {
    let key = "\(shot.name):\(start):\(end)"
    if let c = windowBgCache[key] { return c }
    let lo = max(0, start), hi = min(shot.N-1, end)
    guard lo <= hi else { return nil }
    let WH = shot.W * shot.H
    var sum = [Double](repeating: 0, count: WH)
    var count = 0
    for fi in lo...hi {
        let fr = shot.frames[fi]
        for row in 0..<shot.H {
            for col in 0..<shot.W {
                let i = row*shot.W + col
                sum[i] += Double(0.2989*fr.r(row,col) + 0.5870*fr.g(row,col) + 0.1140*fr.b(row,col))
            }
        }
        count += 1
    }
    let nd = Double(count)
    let result = sum.map { $0 / nd }
    windowBgCache[key] = result
    return result
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Diff map building
// ─────────────────────────────────────────────────────────────────────────────

func buildMask(_ shot: ShotData, fi: Int, method: String, p: Params,
               winStart: Int? = nil, winEnd: Int? = nil) -> MaskResult? {
    guard fi > 0 else { return nil }
    guard let ball = ballForFrame(shot, fi) else { return nil }
    let W = shot.W, H = shot.H

    let roi = roiRect(ballCx: ball.cx, ballCy: ball.cy, ballDia: ball.dia, p: p)
    guard let (rawCurr, rows, cols, x0, y0) = getPatch(shot.frames[fi],   roi: roi),
          let (rawPrev, _,    _,    _,  _)  = getPatch(shot.frames[fi-1], roi: roi),
          rawCurr.count == rawPrev.count else { return nil }

    let bxRoi = ball.cx * Double(W) - Double(x0)
    let byRoi = ball.cy * Double(H) - Double(y0)
    let diaPx = ball.dia * Double(W)

    let skipImp    = Int(round(p.skipNearImpact))
    let nearImpact = abs(fi - shot.impact) <= skipImp

    let patchC  = nearImpact ? rawCurr : eraseBall(rawCurr, rows: rows, cols: cols, cxRoi: bxRoi, cyRoi: byRoi, diaPx: diaPx, scale: 1.0)
    let patchPC = nearImpact ? rawPrev : eraseBall(rawPrev, rows: rows, cols: cols, cxRoi: bxRoi, cyRoi: byRoi, diaPx: diaPx, scale: 1.0)

    var diffMap = [Double](repeating: 0, count: rows*cols)

    switch method {
    case "bgDiff":
        let ws = winStart ?? max(1, shot.impact - 3)
        let we = winEnd   ?? min(shot.N - 1, shot.impact + 1)
        if let bg = getWindowBg(shot, start: ws, end: we) {
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
        if let base = getBaselineFrame(shot) {
            // Uses ORIGINAL patch (not erased) — matches Python comment "ball cancels"
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
            // Fallback: abs frame diff
            let gc = rgbToGray(patchC,  rows: rows, cols: cols)
            let gp = rgbToGray(patchPC, rows: rows, cols: cols)
            for i in 0..<(rows*cols) { diffMap[i] = abs(gc[i] - gp[i]) }
        }
    default:
        // abs diff fallback
        let gc = rgbToGray(patchC,  rows: rows, cols: cols)
        let gp = rgbToGray(patchPC, rows: rows, cols: cols)
        for i in 0..<(rows*cols) { diffMap[i] = abs(gc[i] - gp[i]) }
    }

    // For non-near-impact: fill ball disc with surrounding annulus median
    if !nearImpact {
        let ballRFill = diaPx / 2
        let r2   = ballRFill * ballRFill
        let r2a  = ballRFill * ballRFill * 3.24   // (1.8*r)^2
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

    return MaskResult(diffMap: diffMap, rows: rows, cols: cols, x0: x0, y0: y0, ball: ball)
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - BFS blob detection
// ─────────────────────────────────────────────────────────────────────────────

// Input dm is already normalised 0-1; this function normalises again by (post-masking) peak.
// Matches Python's double-normalisation: find_blobs_streak_bfs normalises once,
// then _rightmost_blob_from_diff normalises again.
func rightmostBlobFromDiff(_ dm: [Double], rows: Int, cols: Int,
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

func componentToBlob(_ comp: [(row: Int, col: Int)], x0: Int, y0: Int,
                     W: Int, H: Int, refBx: Double, refBy: Double) -> Detection? {
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
    let faceN = max(1, comp.count/3)
    let faceIdx = dists.indices.sorted { dists[$0] < dists[$1] }.prefix(faceN)
    var sumFX = 0.0, sumFY = 0.0
    for k in faceIdx { sumFX += pxs[k]; sumFY += pys[k] }
    let fn   = Double(faceN)
    let leadX = sumFX / fn / Double(W)
    let leadY = sumFY / fn / Double(H)

    return Detection(cx: cx/Double(W), cy: cy/Double(H), count: comp.count, leadX: leadX, leadY: leadY)
}

func findBlobsStreakBFS(_ mr: MaskResult, shot: ShotData, p: Params,
                         impactFi: Int, fi: Int, method: String) -> [Detection] {
    let W = shot.W, H = shot.H
    let rows = mr.rows, cols = mr.cols
    let ball = mr.ball
    let x0 = mr.x0, y0 = mr.y0
    let bxF = ball.cx * Double(W), byF = ball.cy * Double(H)
    let ballR = ball.dia * Double(W) / 2
    let exclR = ballR * p.exclusion

    // First normalisation (matches Python dm_n = dm / max(...))
    guard let peak = mr.diffMap.max(), peak > 1e-6 else { return [] }
    var dmDet = mr.diffMap.map { $0 / peak }

    // Ball masking (using full-frame pixel coords for each ROI pixel)
    let post = fi > impactFi

    if method == "newDiff" {
        if fi <= impactFi {
            // Zero columns from ball_col rightward
            let ballCol = Int(round(bxF)) - x0
            if ballCol >= 0 && ballCol < cols {
                for row in 0..<rows {
                    for col in ballCol..<cols { dmDet[row*cols+col] = 0.0 }
                }
            }
        } else {
            // Post-impact: mask exclusion disc
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
        // brightBFS (baseline)
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
    let comp = rightmostBlobFromDiff(dmDet, rows: rows, cols: cols, leftmost: post, thrScale: thrScale)
    guard !comp.isEmpty else { return [] }
    guard let blob = componentToBlob(comp, x0: x0, y0: y0, W: W, H: H, refBx: bxF, refBy: byF) else { return [] }
    return [blob]
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Filtering
// ─────────────────────────────────────────────────────────────────────────────

// Remove adjacent static detections (< 4px movement)
func dedupConsecutiveDets(_ dets: inout [Int: Detection], W: Int, H: Int) {
    let ordered = dets.keys.sorted()
    for i in 1..<ordered.count {
        let a = ordered[i-1], b = ordered[i]
        guard let da = dets[a], let db = dets[b] else { continue }
        let dx = abs(da.cx - db.cx) * Double(W)
        let dy = abs(da.cy - db.cy) * Double(H)
        if hypot(dx, dy) < 4.0 { dets.removeValue(forKey: a) }
    }
}

// Enforce left→right monotonicity for pre-impact detections
func applyMonotonicity(_ dets: inout [Int: Detection], shot: ShotData, ballImp: BallObs?) {
    guard let ball = ballImp else { return }
    let W = shot.W, tol = 5.0 / Double(W), impact = shot.impact
    let ballCx = ball.cx

    // Step 1: pre-impact must be left of ball
    for fi in dets.keys where fi < impact {
        if let d = dets[fi], d.cx >= ballCx { dets.removeValue(forKey: fi) }
    }

    var ordered = dets.compactMap { k, v -> (Int, Double)? in k < impact ? (k, v.cx) : nil }
                      .sorted { $0.0 < $1.0 }
    guard !ordered.isEmpty else { return }

    // Step 2: anchor on leftmost detection — earlier ghost to right must be removed
    let leftmost = ordered.min(by: { $0.1 < $1.1 })!
    let leftCx = leftmost.1, leftFi = leftmost.0
    for (fi, cx) in ordered where fi < leftFi && cx > leftCx + tol {
        dets.removeValue(forKey: fi)
    }

    // Step 3: strict left-to-right monotonicity
    ordered = dets.compactMap { k, v -> (Int, Double)? in k < impact ? (k, v.cx) : nil }
                  .sorted { $0.0 < $1.0 }
    guard ordered.count >= 2 else { return }
    var frontier = ordered[0].1
    for i in 1..<ordered.count {
        let (fi, cx) = ordered[i]
        if cx < frontier - tol { dets.removeValue(forKey: fi) }
        else { frontier = max(frontier, cx) }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - BFS sweep
// ─────────────────────────────────────────────────────────────────────────────

func runBFSSweep(_ shot: ShotData, method: String, maskMethod: String,
                 impact: Int, start: Int, end: Int, ballImp: BallObs?,
                 p: Params) -> [Int: Detection] {
    var rawDets = [Int: Detection]()
    for fi in start...end {
        if let mr = buildMask(shot, fi: fi, method: maskMethod, p: p, winStart: start, winEnd: end) {
            let blobs = findBlobsStreakBFS(mr, shot: shot, p: p, impactFi: impact, fi: fi, method: method)
            if let b = blobs.first { rawDets[fi] = b }
        }
    }
    dedupConsecutiveDets(&rawDets, W: shot.W, H: shot.H)
    if method == "newDiff" || method == "ensembleBFS" {
        applyMonotonicity(&rawDets, shot: shot, ballImp: ballImp)
    }
    return rawDets
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Speed (for smash guard)
// ─────────────────────────────────────────────────────────────────────────────

func computeClubSpeed(_ shot: ShotData, dets: [Int: Detection], p: Params) -> Double? {
    let W = shot.W, H = shot.H, impact = shot.impact, fps = shot.fps
    guard let ballImp = ballForFrame(shot, impact) else { return nil }
    let fovX = p.fovX, fovY = p.fovY
    let fx = Double(W) / (2 * tan(fovX * .pi / 360))
    let fy = Double(H) / (2 * tan(fovY * .pi / 360))
    let depthM: Double
    if let d = shot.ballDepthM {
        depthM = d
    } else {
        depthM = p.ballDiamM * fx / max(ballImp.dia * Double(W), 1.0)
    }

    var spdPts = [(t: Double, x: Double, y: Double, z: Double)]()
    for fi in dets.keys.sorted() {
        let blob = dets[fi]!
        if blob.predicted || fi > impact { continue }
        if blob.synthetic && fi != impact { continue }
        let X = (blob.cx - 0.5) * Double(W) / fx * depthM
        let Y = (blob.cy - 0.5) * Double(H) / fy * depthM
        spdPts.append((Double(fi)/fps, X, Y, depthM))
    }
    guard spdPts.count >= 2 else { return nil }

    var pairSpeeds = [Double]()
    for i in 0..<spdPts.count {
        for j in (i+1)..<spdPts.count {
            let a = spdPts[i], b = spdPts[j]
            let dt = b.t - a.t
            guard dt > 1e-9 else { continue }
            let dx = b.x-a.x, dy = b.y-a.y, dz = b.z-a.z
            pairSpeeds.append(sqrt(dx*dx + dy*dy + dz*dz) / dt * 2.23694)
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

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Ensemble pool and fit
// ─────────────────────────────────────────────────────────────────────────────

func ensemblePoolAndFit(_ rawNd: [Int: Detection], _ rawBf: [Int: Detection],
                         shot: ShotData, impact: Int, start: Int, end: Int,
                         p: Params) -> [Int: Detection] {
    let W = shot.W, H = shot.H
    guard let ballImp = ballForFrame(shot, impact) else { return [:] }
    let ballCx = ballImp.cx, ballCy = ballImp.cy

    // Median blob count across all candidates
    var allCounts = rawNd.values.map { $0.count } + rawBf.values.map { $0.count }
    let medCount: Double
    if allCounts.isEmpty { medCount = 100.0 }
    else {
        allCounts.sort()
        medCount = allCounts.count % 2 == 0
            ? Double(allCounts[allCounts.count/2-1] + allCounts[allCounts.count/2]) / 2
            : Double(allCounts[allCounts.count/2])
    }

    // Step 1: pick best candidate per frame (count closest to median)
    var result = [Int: Detection]()
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

    // Step 1.5: reject near-duplicate (< 6px) detections
    var prevCx: Double? = nil, prevCy: Double? = nil
    for fi in (start...end).sorted() {
        guard let det = result[fi] else { continue }
        if let pcx = prevCx, let pcy = prevCy {
            let distPx = hypot((det.cx - pcx) * Double(W), (det.cy - pcy) * Double(H))
            if distPx < 6.0 {
                let nd = rawNd[fi], bf = rawBf[fi]
                let chosen = result[fi]!
                // Try the other method
                let isNd = nd.map { abs($0.cx - chosen.cx) < 1e-9 && abs($0.cy - chosen.cy) < 1e-9 } ?? false
                let alt: Detection? = isNd ? bf : nd
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

    // Step 2: confirmed set (both methods agree within 15px)
    var confirmed = Set<Int>()
    for fi in start...end {
        if let n = rawNd[fi], let b = rawBf[fi] {
            let dist = hypot((n.cx - b.cx) * Double(W), (n.cy - b.cy) * Double(H))
            if dist < 15.0 { confirmed.insert(fi) }
        }
    }

    // Step 3: hard physics filters (skip confirmed)
    let tolX = 5.0 / Double(W), tolY = 0.12
    var frontierCx: Double? = nil
    for fi in (start...end).sorted() {
        guard let det = result[fi] else { continue }
        if confirmed.contains(fi) {
            if fi < impact { frontierCx = frontierCx.map { max($0, det.cx) } ?? det.cx }
            continue
        }
        let cx = det.cx, cy = det.cy
        if fi < impact {
            if cx >= ballCx { result.removeValue(forKey: fi); continue }
            if cy < ballCy - tolY { result.removeValue(forKey: fi); continue }
            if let fc = frontierCx, cx < fc - tolX { result.removeValue(forKey: fi); continue }
            frontierCx = frontierCx.map { max($0, cx) } ?? cx
        }
    }

    // Step 4: LOO polynomial outlier removal (≥5 points, confirmed protected, threshold 40px)
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
        result.removeValue(forKey: wfi)
    }

    // Step 4b: backwards-pair cleanup
    let prePts = result.filter { $0.key < impact }.sorted { $0.key < $1.key }
    if prePts.count == 2 {
        let fiA = prePts[0].key, dA = prePts[0].value
        let dB  = prePts[1].value
        if dB.cx < dA.cx { result.removeValue(forKey: fiA) }
    }

    // Step 5: smash guard (iteratively remove worst point until smash ≤ 1.55)
    let ballSpd = shot.ballSpeedMph
    if ballSpd > 0 {
        for _ in 0...(result.count + 1) {
            guard result.count >= 2 else { break }
            guard let cs = computeClubSpeed(shot, dets: result, p: p), cs > 1e-3 else { break }
            if ballSpd / cs <= 1.55 { break }
            var bestFi: Int? = nil, bestSmash = Double.infinity
            for fiTry in result.keys {
                var test = result; test.removeValue(forKey: fiTry)
                guard test.count >= 2,
                      let cs2 = computeClubSpeed(shot, dets: test, p: p), cs2 > 1e-3 else { continue }
                let smash = ballSpd / cs2
                if smash < bestSmash { bestSmash = smash; bestFi = fiTry }
            }
            guard let bfi = bestFi else { break }
            result.removeValue(forKey: bfi)
        }
    }

    let ndKept  = rawNd.count, bfKept = rawBf.count, outKept = result.count
    fputs("  [ensembleBFS] nd=\(ndKept)  bf=\(bfKept)  kept=\(outKept)  med_count=\(Int(medCount))\n", stderr)
    return result
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Polynomial helpers (LOO outlier removal)
// ─────────────────────────────────────────────────────────────────────────────

// Fit polynomial of given degree and evaluate at x0 — mirrors numpy.polyfit + polyval
func polyFitEval(x: [Double], y: [Double], degree: Int, at x0: Double) -> Double {
    let n = x.count, deg = min(degree, n-1), m = deg + 1
    // Build Vandermonde (highest power first, matches numpy convention)
    var A = [[Double]](repeating: [Double](repeating: 0, count: m), count: n)
    for i in 0..<n {
        var xp = 1.0
        for j in 0...deg { A[i][deg-j] = xp; xp *= x[i] }
    }
    // Normal equations AtA * c = Aty
    var AtA = [[Double]](repeating: [Double](repeating: 0, count: m), count: m)
    var Aty = [Double](repeating: 0, count: m)
    for i in 0..<n {
        for j in 0..<m {
            Aty[j] += A[i][j] * y[i]
            for k in 0..<m { AtA[j][k] += A[i][j] * A[i][k] }
        }
    }
    guard let coeffs = gaussSolve(AtA, Aty) else { return y[n/2] }
    // Evaluate: coeffs[0]*x0^deg + ... + coeffs[deg]*x0^0
    var val = 0.0, xp = 1.0
    for j in stride(from: m-1, through: 0, by: -1) { val += coeffs[j] * xp; xp *= x0 }
    return val
}

func gaussSolve(_ A: [[Double]], _ b: [Double]) -> [Double]? {
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

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Main
// ─────────────────────────────────────────────────────────────────────────────

func main() {
    let args = CommandLine.arguments
    guard args.count >= 3 else {
        fputs("Usage: ensemble_bfs <shot_folder> '<params_json>'\n", stderr)
        exit(1)
    }
    guard let paramsData = args[2].data(using: .utf8),
          let paramsJson = try? JSONSerialization.jsonObject(with: paramsData) as? [String: Any]
    else { fputs("ERROR: invalid params JSON\n", stderr); exit(1) }
    let p = Params(paramsJson)

    guard let shot = loadShot(args[1]) else {
        print("{\"detections\":[]}")
        exit(0)
    }

    let impact  = shot.impact
    let start   = max(1, impact - 3)
    let end     = min(shot.N - 1, impact + 1)
    let ballImp = ballForFrame(shot, impact)

    let rawNd = runBFSSweep(shot, method: "newDiff",   maskMethod: "bgDiff",
                             impact: impact, start: start, end: end, ballImp: ballImp, p: p)
    let rawBf = runBFSSweep(shot, method: "brightBFS", maskMethod: "baseline",
                             impact: impact, start: start, end: end, ballImp: ballImp, p: p)

    let ensemble = ensemblePoolAndFit(rawNd, rawBf, shot: shot,
                                      impact: impact, start: start, end: end, p: p)

    var out = [[String: Any]]()
    for fi in ensemble.keys.sorted() {
        let det = ensemble[fi]!
        out.append(["frame": fi, "cx": det.cx, "cy": det.cy, "count": det.count,
                    "lead_x": det.leadX, "lead_y": det.leadY])
    }

    let resultJson: [String: Any] = ["detections": out]
    if let data = try? JSONSerialization.data(withJSONObject: resultJson) {
        print(String(data: data, encoding: .utf8) ?? "{\"detections\":[]}")
    } else {
        print("{\"detections\":[]}")
    }
}

main()
