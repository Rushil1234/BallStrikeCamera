import Foundation

// MARK: - Ground Calibration (IDW lookup matching Python _idw_full)

struct GroundCalibration {
    struct Sample {
        let u: Double
        let v: Double
        let diameter: Double
        let weight: Double
    }

    let samples: [Sample]

    /// Parsed once — the JSON has ~1000 samples and is looked up on every shot analysis.
    static let shared: GroundCalibration? = autoLoad()

    static func autoLoad() -> GroundCalibration? {
        guard let url = ModelResourceLoader.url(forModelResource: "ground_ball_size_calibration"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawSamples = json["samples"] as? [[String: Any]]
        else { return nil }

        let samples = rawSamples.compactMap { d -> Sample? in
            guard let u   = d["u"] as? Double,
                  let v   = d["v"] as? Double,
                  let dia = d["diameter"] as? Double else { return nil }
            let w = d["calibrationSampleWeight"] as? Double ?? 1.0
            return Sample(u: u, v: v, diameter: dia, weight: w)
        }
        guard !samples.isEmpty else { return nil }
        print("[GroundCalibration] Loaded \(samples.count) samples")
        return GroundCalibration(samples: samples)
    }

    /// Matches Python _idw_full(k=12, power=2.0, max_dist=0.25)
    func expectedDiameter(u: Double, v: Double,
                          k: Int = 12, power: Double = 2.0,
                          maxDist: Double = 0.25) -> (diameter: Double?, confidence: Double) {
        guard !samples.isEmpty else { return (nil, 0.0) }

        var near: [(dist: Double, dia: Double, weight: Double)] = []
        for s in samples {
            let d = sqrt((s.u - u) * (s.u - u) + (s.v - v) * (s.v - v))
            if d <= maxDist { near.append((d, s.diameter, s.weight)) }
        }
        guard !near.isEmpty else { return (nil, 0.0) }

        near.sort { $0.dist < $1.dist }
        let kActual = min(k, near.count)
        let topK = Array(near.prefix(kActual))

        if topK[0].dist < 1e-9 { return (topK[0].dia, topK[0].weight) }

        let iw    = topK.map { $0.weight / pow($0.dist, power) }
        let iwSum = iw.reduce(0, +)
        guard iwSum > 0 else { return (nil, 0.0) }
        let est  = zip(iw, topK).reduce(0.0) { $0 + $1.0 * $1.1.dia } / iwSum
        let conf = min(1.0, Double(kActual) / 20.0) * min(1.0, 1.0 - topK[0].dist / maxDist)
        return (est, max(0.0, conf))
    }
}

// MARK: - VLA Model Data

struct VLAModelData {
    let modelType: String
    let features: [String]
    let featureMeans: [String: Double]
    let featureStds: [String: Double]
    let imputationMedians: [String: Double]
    let coefficients: [String: Double]
    let intercept: Double
    let predictionClamp: (Double, Double)
    let trainingShots: Int
    let metrics: [String: Double]
    let featureSearchTopSubset: [String]
    let filePath: String
}

// MARK: - VLA Model Predictor

struct VLAModelPredictor {

    static let defaultModelPaths: [String] = [
        NSHomeDirectory() + "/Documents/vla_model.json",
        NSHomeDirectory() + "/Downloads/vla_model.json",
    ]

    static func load(from path: String) -> VLAModelData? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            print("[VLAModelPredictor] Failed to load: \(path)")
            return nil
        }
        guard
            let features  = json["features"] as? [String],
            let meansRaw  = json["featureMeans"] as? [String: Any],
            let stdsRaw   = json["featureStds"] as? [String: Any],
            let coefsRaw  = json["coefficients"] as? [String: Any],
            let intercept = json["intercept"] as? Double
        else {
            print("[VLAModelPredictor] Invalid model JSON at \(path)")
            return nil
        }

        func toDoubleDict(_ d: [String: Any]) -> [String: Double] {
            d.compactMapValues { $0 as? Double }
        }

        let clampArr  = json["predictionClamp"] as? [Double] ?? [0, 65]
        let clamp     = (clampArr.first ?? 0, clampArr.last ?? 65)
        let medians   = (json["imputationMedians"] as? [String: Any]).map(toDoubleDict) ?? [:]
        let metricsRaw = (json["metrics"] as? [String: Any]).map(toDoubleDict) ?? [:]
        let topSubset = json["featureSearchTopSubset"] as? [String] ?? []

        let model = VLAModelData(
            modelType: json["modelType"] as? String ?? "ridge_regression",
            features: features,
            featureMeans: toDoubleDict(meansRaw),
            featureStds: toDoubleDict(stdsRaw),
            imputationMedians: medians,
            coefficients: toDoubleDict(coefsRaw),
            intercept: intercept,
            predictionClamp: clamp,
            trainingShots: json["trainingShots"] as? Int ?? 0,
            metrics: metricsRaw,
            featureSearchTopSubset: topSubset,
            filePath: path
        )
        print(String(format: "[VLAModelPredictor] Loaded %@ n=%d MAE=%.2f°",
                     model.modelType, model.trainingShots, model.metrics["mae"] ?? 0))
        return model
    }

    static func autoLoad(overridePath: String? = nil) -> VLAModelData? {
        if let url = ModelResourceLoader.url(forModelResource: "vla_model"),
           let model = load(from: url.path) {
            return model
        }
        var paths = [String]()
        if let p = overridePath { paths.append(p) }
        paths.append(contentsOf: defaultModelPaths)
        for path in paths {
            if FileManager.default.fileExists(atPath: path),
               let model = load(from: path) {
                return model
            }
        }
        print("[VLAModelPredictor] No vla_model.json found in bundle or default locations")
        return nil
    }

    static func predict(
        features featureDict: [String: Double],
        model: VLAModelData
    ) -> (raw: Double, clamped: Double, featuresUsed: [String: Double], warnings: [String]) {
        var warnings = [String]()
        var featuresUsed = [String: Double]()
        var dot = 0.0

        for fn in model.features {
            var value: Double
            if let v = featureDict[fn], v.isFinite {
                value = v
            } else {
                let imputed = model.imputationMedians[fn] ?? 0.0
                warnings.append("Feature '\(fn)' missing — imputed \(String(format: "%.4f", imputed))")
                value = imputed
            }
            featuresUsed[fn] = value
            let mean = model.featureMeans[fn] ?? 0.0
            let std  = max(model.featureStds[fn] ?? 1.0, 1e-10)
            let z    = (value - mean) / std
            let coef = model.coefficients[fn] ?? 0.0
            dot += coef * z
        }

        let raw     = dot + model.intercept
        let clamped = min(max(raw, model.predictionClamp.0), model.predictionClamp.1)
        if abs(raw - clamped) > 0.01 {
            warnings.append(String(format: "Trained VLA %.1f° clamped to %.1f°", raw, clamped))
        }
        return (raw, clamped, featuresUsed, warnings)
    }

    // MARK: - Full Feature Extraction (matches Python _compute_shot_vla_features)

    static func extractFeatures(
        from observations: [Ball3DObservation],
        hlaDegrees: Double?,
        ballSpeedMph: Double?,
        impactFrameIndex: Int,
        totalFrames: Int,
        groundCalibration: GroundCalibration? = nil
    ) -> [String: Double] {
        guard observations.count >= 2 else { return [:] }

        // Enrich each observation with ground ratio data via IDW calibration lookup
        struct PostPt {
            let cx: Double; let cy: Double; let dia: Double
            let frameIndex: Int; let relativeTime: Double; let confidence: Double
            let egDia:  Double?   // expected ground diameter
            let gr:     Double?   // ground_diameter_ratio = dia / egDia
            let gex:    Double?   // ground_diameter_excess = dia - egDia
            let gcConf: Double?   // ground calibration confidence
        }

        let postPts: [PostPt] = observations.map { obs in
            let cx  = Double(obs.imageX)
            let cy  = Double(obs.imageY)
            let dia = Double(obs.diameterNorm)
            var egDia:  Double? = nil
            var gcConf: Double? = nil
            if let gc = groundCalibration {
                let (ed, ec) = gc.expectedDiameter(u: cx, v: cy)
                egDia  = ed
                gcConf = ec
            }
            let gr:  Double? = (egDia != nil && dia > 0) ? dia / egDia! : nil
            let gex: Double? = (egDia != nil && dia > 0) ? dia - egDia! : nil
            return PostPt(cx: cx, cy: cy, dia: dia,
                          frameIndex: obs.frameIndex,
                          relativeTime: obs.relativeTime,
                          confidence: obs.confidence,
                          egDia: egDia, gr: gr, gex: gex, gcConf: gcConf)
        }

        // Value arrays
        let cxs    = postPts.map(\.cx)
        let cys    = postPts.map(\.cy)
        let dias   = postPts.map(\.dia)
        let fiVals = postPts.map { Double($0.frameIndex) }
        let rtVals = postPts.map(\.relativeTime)
        let grVals = postPts.compactMap(\.gr)
        let gexVals = postPts.compactMap(\.gex)
        let gcVals  = postPts.compactMap(\.gcConf)

        var feats = [String: Double]()

        // --- Basic scalars ---
        feats["n_valid_post_points"] = Double(postPts.count)
        feats["impact_frame"]        = Double(impactFrameIndex)
        feats["total_frames"]        = Double(totalFrames)
        feats["tracked_frames"]      = Double(observations.count)
        if let hla = hlaDegrees {
            feats["hla_degrees"]     = hla
            feats["abs_hla_degrees"] = abs(hla)
        }
        if let spd = ballSpeedMph { feats["ball_speed_mph"] = spd }

        // --- First / last point ---
        let p0 = postPts.first!;  let pN = postPts.last!
        feats["first_post_cx"]  = p0.cx;  feats["first_post_cy"]  = p0.cy
        feats["first_post_dia"] = p0.dia
        feats["last_post_cx"]   = pN.cx;  feats["last_post_cy"]   = pN.cy
        feats["last_post_dia"]  = pN.dia
        if let gr = p0.gr { feats["first_post_ground_diameter_ratio"] = gr }
        if let gr = pN.gr { feats["last_post_ground_diameter_ratio"]  = gr }

        // --- Ground calibration aggregate stats ---
        if let v = vMean(gcVals)   { feats["mean_ground_calibration_confidence"] = v }
        if let v = vMean(grVals)   { feats["mean_ground_diameter_ratio"]  = v; feats["mean_ground_ratio"]   = v }
        if let v = vMed(grVals)    { feats["median_ground_diameter_ratio"] = v; feats["median_ground_ratio"] = v }
        if let v = grVals.max()    { feats["max_ground_ratio"] = v }
        if let v = grVals.min()    { feats["min_ground_ratio"] = v }
        if let v = vStd(grVals)    { feats["std_ground_ratio"] = v }
        if grVals.count >= 2       { feats["ground_ratio_range"] = grVals.max()! - grVals.min()! }
        if let v = vMean(gexVals)  { feats["mean_ground_excess"] = v }
        if let v = gexVals.max()   { feats["max_ground_excess"]  = v }
        if grVals.count >= 2       { feats["ground_ratio_growth"] = grVals.last! - grVals.first! }

        // --- Geometry stats ---
        feats["max_center_x"]      = cxs.max() ?? 0
        feats["min_center_x"]      = cxs.min() ?? 0
        feats["max_center_y"]      = cys.max() ?? 0
        feats["min_center_y"]      = cys.min() ?? 0
        if cxs.count >= 2 { feats["center_x_range"] = cxs.max()! - cxs.min()! }
        feats["max_diameter_norm"] = dias.max() ?? 0
        feats["min_diameter_norm"] = dias.min() ?? 0
        if let v = vMean(dias)     { feats["mean_diameter_norm"] = v }

        // --- Trajectory ---
        let dxFl = pN.cx - p0.cx
        let dyFl = pN.cy - p0.cy
        feats["forward_progress_total"]      = dxFl
        feats["dx_first_last"]               = dxFl
        feats["vertical_image_change_total"] = dyFl
        if cxs.count >= 2 {
            var pl = 0.0
            for i in 1..<cxs.count {
                pl += sqrt((cxs[i]-cxs[i-1])*(cxs[i]-cxs[i-1]) + (cys[i]-cys[i-1])*(cys[i]-cys[i-1]))
            }
            feats["path_length_norm"] = pl
        }
        let totalDt = rtVals.last! - rtVals.first!
        if totalDt > 1e-6 {
            feats["x_speed_norm"] = dxFl / totalDt
            feats["y_speed_norm"] = dyFl / totalDt
        }

        // --- Path residual (line fit through cx/cy) ---
        if cxs.count >= 3, let prm = pathResidual(xs: cxs, ys: cys) {
            feats["path_residual_mean"] = prm
        }
        if cxs.count >= 2, let sl = linSlope(cxs, cys) {
            feats["straight_line_slope"] = sl
        }

        // --- Diameter features ---
        if p0.dia > 1e-6 {
            let dgr = pN.dia / p0.dia
            feats["diameter_growth_ratio"]         = dgr
            feats["diameter_growth_ratio_squared"] = dgr * dgr
        }
        if dias.count >= 2 {
            let i3 = min(2, dias.count - 1)
            feats["early_diameter_slope_1to3"] = (dias[i3] - dias[0]) / Double(max(1, i3))
        }
        if dias.count >= 2, let sl = linSlope(Array(fiVals.prefix(dias.count)), dias) {
            feats["diameter_slope_over_frame"] = sl
        }

        // --- Ground ratio slopes ---
        var grFi: [Double] = []; var grRt: [Double] = []; var grArr: [Double] = []
        for (i, pt) in postPts.enumerated() {
            if let g = pt.gr { grFi.append(fiVals[i]); grRt.append(rtVals[i]); grArr.append(g) }
        }
        if grArr.count >= 2 {
            if let sl = linSlope(grFi, grArr)     { feats["ground_ratio_slope_over_frame"] = sl }
            if grRt.last! != grRt.first!, let sl = linSlope(grRt, grArr) {
                feats["ground_ratio_slope_over_time"] = sl
            }
            let i3 = min(2, grArr.count - 1); let i5 = min(4, grArr.count - 1)
            feats["early_ground_ratio_slope_1to3"]    = (grArr[i3] - grArr[0]) / Double(max(1, i3))
            feats["early_ground_ratio_slope_1to5"]    = (grArr[i5] - grArr[0]) / Double(max(1, i5))
            feats["final_minus_initial_ground_ratio"] = grArr.last! - grArr.first!
            if let v = vMean(Array(grArr.prefix(3))) { feats["ratio_at_first_3_mean"] = v }
            if let v = vMean(Array(grArr.prefix(5))) { feats["ratio_at_first_5_mean"] = v }
        }

        // --- Window features: first N ---
        for wn in [2, 3, 5, 8, 12] {
            let pts  = Array(postPts.prefix(wn)); guard !pts.isEmpty else { continue }
            let pf   = "first\(wn)_"
            let wcx  = pts.map(\.cx)
            let wcy  = pts.map(\.cy)
            let wdia = pts.map(\.dia)
            let wgr  = pts.compactMap(\.gr)
            if let v = vMean(wcx)  { feats[pf + "mean_cx"]  = v }
            if let v = vMean(wcy)  { feats[pf + "mean_cy"]  = v }
            if let v = vMean(wdia) { feats[pf + "mean_dia"] = v }
            if let v = vMean(wgr)  { feats[pf + "mean_ground_ratio"] = v }
            if let v = wgr.max()   { feats[pf + "max_ground_ratio"]  = v }
            if let v = wgr.min()   { feats[pf + "min_ground_ratio"]  = v }
            if wgr.count >= 2      { feats[pf + "ground_ratio_range"] = wgr.max()! - wgr.min()! }
            if wgr.count >= 2      { feats[pf + "ground_ratio_growth"] = wgr.last! - wgr.first! }
            if pts.count >= 2 {
                feats[pf + "x_progress"] = wcx.last! - wcx.first!
                feats[pf + "y_change"]   = wcy.last! - wcy.first!
                if wdia.first! > 1e-6 { feats[pf + "diameter_growth_ratio"] = wdia.last! / wdia.first! }
                let wfi = pts.map { Double($0.frameIndex) }
                if wdia.count == pts.count, let sl = linSlope(wfi, wdia) {
                    feats[pf + "slope_dia_per_frame"] = sl
                }
                if wgr.count == pts.count, let sl = linSlope(wfi, wgr) {
                    feats[pf + "slope_ground_ratio_per_frame"] = sl
                }
            }
        }

        // --- Window features: last N ---
        for wn in [3, 5, 8] {
            let pts = postPts.count >= wn ? Array(postPts.suffix(wn)) : Array(postPts)
            guard !pts.isEmpty else { continue }
            let pf  = "last\(wn)_"
            let wgr = pts.compactMap(\.gr)
            if let v = vMean(pts.map(\.cx))  { feats[pf + "mean_cx"]  = v }
            if let v = vMean(pts.map(\.cy))  { feats[pf + "mean_cy"]  = v }
            if let v = vMean(pts.map(\.dia)) { feats[pf + "mean_dia"] = v }
            if let v = vMean(wgr)            { feats[pf + "mean_ground_ratio"] = v }
            if wgr.count >= 2                { feats[pf + "ground_ratio_growth"] = wgr.last! - wgr.first! }
        }

        // --- Indexed p1..p10 ---
        for pi in 1...10 {
            let pt: PostPt? = pi <= postPts.count ? postPts[pi - 1] : nil
            let pf = "p\(pi)_"
            if let p = pt {
                feats[pf + "x"]          = p.cx
                feats[pf + "y"]          = p.cy
                feats[pf + "diameter"]   = p.dia
                feats[pf + "radius"]     = p.dia / 2.0
                feats[pf + "confidence"] = p.confidence
                if let gr  = p.gr  { feats[pf + "ground_ratio"]  = gr  }
                if let gex = p.gex { feats[pf + "ground_excess"] = gex }
            }
        }

        // --- Nonlinear transforms ---
        let mgr   = feats["mean_ground_ratio"]
        let maxgr = feats["max_ground_ratio"]
        let hla   = hlaDegrees
        let dgr   = feats["diameter_growth_ratio"]

        func sq(_ v: Double?) -> Double? { v.map { $0 * $0 } }
        func lg(_ v: Double?) -> Double? { v.flatMap { $0 > 0 ? log($0) : nil } }
        func mul(_ a: Double?, _ b: Double?) -> Double? {
            guard let a, let b else { return nil }; return a * b
        }

        if let v = sq(mgr)   { feats["mean_ground_ratio_squared"]  = v }
        if let v = mgr.map({ $0 * $0 * $0 }) { feats["mean_ground_ratio_cubed"] = v }
        if let v = lg(mgr)   { feats["log_mean_ground_ratio"]      = v }
        if let v = sq(maxgr) { feats["max_ground_ratio_squared"]   = v }
        if let v = sq(dgr)   { feats["diameter_growth_ratio_squared"] = v }
        if let v = mul(feats["first_post_cx"] ?? feats["max_center_x"], mgr) {
            feats["mean_cx_times_mean_ground_ratio"] = v
        }
        if let v = mul(feats["first_post_cy"] ?? feats["max_center_y"], mgr) {
            feats["mean_cy_times_mean_ground_ratio"] = v
        }
        if let v = mul(hla, mgr)                        { feats["hla_times_mean_ground_ratio"] = v }
        if let v = mul(feats["max_center_x"], maxgr)    { feats["max_cx_times_max_ground_ratio"] = v }
        for pi in 1...3 {
            let pgr = feats["p\(pi)_ground_ratio"]
            let px  = feats["p\(pi)_x"]
            if let v = sq(pgr)    { feats["p\(pi)_ground_ratio_squared"]  = v }
            if let v = mul(px, pgr) { feats["p\(pi)_x_times_ground_ratio"] = v }
        }

        return feats
    }

    // MARK: - Math helpers

    private static func vMean(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        return xs.reduce(0, +) / Double(xs.count)
    }

    private static func vMed(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted(); let n = s.count
        return n % 2 == 0 ? (s[n/2 - 1] + s[n/2]) / 2.0 : s[n/2]
    }

    private static func vStd(_ xs: [Double]) -> Double? {
        guard xs.count >= 2 else { return nil }
        let m = xs.reduce(0, +) / Double(xs.count)
        let v = xs.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(xs.count)
        return sqrt(v)
    }

    /// Linear slope of ys vs xs — matches np.polyfit(xs, ys, 1)[0]
    private static func linSlope(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count >= 2, xs.count == ys.count else { return nil }
        let n   = Double(xs.count)
        let sx  = xs.reduce(0, +); let sy = ys.reduce(0, +)
        let sxy = zip(xs, ys).map(*).reduce(0, +)
        let sx2 = xs.map { $0 * $0 }.reduce(0, +)
        let d   = n * sx2 - sx * sx
        guard abs(d) > 1e-12 else { return nil }
        return (n * sxy - sx * sy) / d
    }

    /// Mean absolute residual from linear fit of ys vs xs
    private static func pathResidual(xs: [Double], ys: [Double]) -> Double? {
        guard xs.count >= 3, xs.count == ys.count,
              let slope = linSlope(xs, ys) else { return nil }
        let n = Double(xs.count)
        let intercept = (ys.reduce(0, +) - slope * xs.reduce(0, +)) / n
        let resids = zip(xs, ys).map { abs($1 - (slope * $0 + intercept)) }
        return resids.reduce(0, +) / Double(resids.count)
    }
}
