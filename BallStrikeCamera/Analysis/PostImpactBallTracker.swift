import UIKit
import CoreGraphics

// Gated debug logging — off in normal runs (the per-frame trace was flooding the console and
// blocking the analysis thread). Flip to true only when debugging the tracker.
private let kPostImpactDebugLog = false
@inline(__always) private func dbg(_ message: @autoclosure () -> String) {
    if kPostImpactDebugLog { Swift.print(message()) }
}

final class PostImpactBallTracker {

    // MARK: - Configuration

    struct DiameterRefinementConfig {
        var enabled: Bool = true
        var localMaskWindowScale: CGFloat = 1.8
        var maskBrightnessThreshold: Int = 30
        var maskMaxChannelSpread: Int = 65
        var maskPercentile: Int = 85
        var maskPercentileMinBright: Int = 80
        var maskBgDelta: Int = 15
        var smoothingEnabled: Bool = true
        var smoothingWindowSize: Int = 5
    }

    struct ImpactDetectionConfiguration {
        var movementThresholdNorm: CGFloat = 0.006
        var confirmFrames: Int = 2
        var stableWindowCount: Int = 10
        // The live ROI trigger fires when the ball EXITS the impact ROI (~2.5 ball-widths), so
        // it always fires AFTER true impact — instantly for full swings, but ~8-12 frames late
        // for putts/slow shots that take that long to roll out of the ROI. The fallback frame
        // is therefore an UPPER bound on impact: movement-based detection may legitimately
        // land well EARLIER than it, but landing LATER is physically impossible and means the
        // detector latched onto the club. (A symmetric ±4 clamp here previously forced putt
        // impacts from their true frame ~10 back to 20, making the analysis treat 10 frames of
        // rolling ball as "stationary pre-impact".)
        var maxEarlyShiftFrames: Int = 16
        var maxLateShiftFrames: Int = 2
    }

    struct Configuration {
        var sampleStride: Int = 2

        var preBrightnessThreshold: Int = 90
        var preMaxChannelSpread: Int = 90
        var preMinBrightSamples: Int = 6
        var preMinNormWidth: CGFloat = 0.008
        var preMaxNormWidth: CGFloat = 0.090
        var preMinNormHeight: CGFloat = 0.012
        var preMaxNormHeight: CGFloat = 0.130
        var preMinAspect: CGFloat = 0.30
        var preMaxAspect: CGFloat = 2.00

        var postBrightnessThreshold: Int = 92
        var postMaxChannelSpread: Int = 110
        var postMinBrightSamples: Int = 4
        var postMinNormWidth: CGFloat = 0.018
        var postMaxNormWidth: CGFloat = 0.120
        var postMinNormHeight: CGFloat = 0.005
        var postMaxNormHeight: CGFloat = 0.150
        var postMinAspect: CGFloat = 0.12
        var postMaxAspect: CGFloat = 5.00

        var preImpactSearchScale: CGFloat = 5.67
        var impactSearchScale: CGFloat = 8.66
        // Legacy symmetric-scale ROI params (kept for fallback / unused by default)
        var postImpactBaseScale: CGFloat = 5.03
        var postImpactScaleGrowth: CGFloat = 2.00
        var postImpactMaxScale: CGFloat = 12.0
        var postImpactMaxVerticalScale: CGFloat = 3.0

        // Forward-biased oriented ROI (matches Python asymmetric post-impact search)
        var postFwdScale: CGFloat = 10.0            // ball-widths forward along launch direction
        var postBwdScale: CGFloat = 1.2             // ball-widths backward
        var postVertScaleUntracked: CGFloat = 1.5   // ball-widths lateral when no prior post-hit
        var postVertScaleTracked: CGFloat = 2.5     // ball-widths lateral once tracking started
        // 0° = ball goes right (+x). Sign-based so it follows the hand-aware direction:
        // righty (sign −1) → 180°, lefty (sign +1, buffer rotated) → 0°. Config is built fresh
        // per shot, so it picks up the current hand.
        var launchAngleDegrees: CGFloat = HitDirection.sign < 0 ? 180.0 : 0.0

        var diameterRefinement: DiameterRefinementConfig = DiameterRefinementConfig()
        var impactDetection: ImpactDetectionConfiguration = ImpactDetectionConfiguration()
        var isPostImpactDebugLoggingEnabled: Bool = false   // per-frame PARITY spam — off in normal runs
        var enableStrictImpactDiameterGate: Bool = true
        var impactFrameMaxDiameterGrowthRatio: CGFloat = 1.25

        // Absolute normalized-distance gates tuned for full-swing ball speeds. A slow putt observed
        // over even a widened 101-frame window can fail to cross these, leaving launchDir unset and
        // the track never confirmed as terminated. launchLockDistanceNorm: distance from the impact
        // point (fraction of frame width) before the launch direction locks. terminationMinProgressNorm:
        // minimum distance traveled before 3 consecutive misses are treated as the ball leaving frame.
        var launchLockDistanceNorm: CGFloat = 0.02
        var terminationMinProgressNorm: CGFloat = 0.05

        // Candidate selection was purely nearest-to-previous-center, which let bright putter
        // markings (chrome glare, white alignment lines — which travel along the exact ball
        // line during a stroke) steal the track from the ball. The ball's apparent diameter is
        // known and stable, so prefer size-consistent candidates: accepted candidates within
        // [min, max]×expected diameter win; only if none match does it fall back to any
        // accepted candidate (so tracking never goes blind).
        var chosenDiameterRatioMin: CGFloat = 0.55
        var chosenDiameterRatioMax: CGFloat = 1.9
        // Per-shot candidate table: one line per analyzed frame listing every blob considered
        // (center, size, brightness, pixel count, accept/reject reason, chosen marker).
        // Bounded at ~41-101 lines/shot — cheap enough to leave on while tuning.
        var logCandidateDetail: Bool = true

        // Monotonicity constraints — the physics the tracker was ignoring:
        // Pre-impact the ball is STATIONARY at the locked position by definition; any chosen
        // blob further than this many locked-diameters from the lock center is the club, not
        // the ball. (Previously the anchor drifted to whatever was chosen last frame, so one
        // bad pick walked the track onto the club permanently.)
        var preAnchorMaxDriftDiameters: CGFloat = 1.2
        // Post-impact the ball only moves AWAY from the impact point (along launchDir once
        // locked). A chosen blob whose progress regresses more than this is the club swinging
        // back through — reject it and let prediction/rescue or a miss handle the frame.
        var monotonicBacktrackAllowanceNorm: CGFloat = 0.012
        // Once the tracked ball gets this close to any frame edge it is leaving the frame —
        // terminate the track. Without this, the frame after exit the tracker adopted whatever
        // static junk blob sat nearest the edge (observed: ball exits at x=0.059, next frame a
        // dim blob at (0.012,0.775) gets tracked motionless for the rest of the capture).
        var edgeTerminationMarginNorm: CGFloat = 0.06

        // First-pass putter tuning — not yet validated against real slow-roll footage, expect to
        // adjust these two numbers after testing on-device.
        static var putterPreset: Configuration {
            var cfg = Configuration()
            cfg.launchLockDistanceNorm = 0.008
            cfg.terminationMinProgressNorm = 0.02
            return cfg
        }
    }

    struct TrackingResult {
        let observations: [ShotBallObservation]
        let debugInfos: [ShotFrameDebugInfo]
        let fallbackImpactFrameIndex: Int
        let detectedImpactFrameIndex: Int
        let impactDetectionReason: String
        let initialBallCenter: CGPoint?
        let movementThresholdNorm: CGFloat
    }

    private struct ImpactDetectionResult {
        let detectedImpactFrameIndex: Int
        let fallbackImpactFrameIndex: Int
        let impactDetectionReason: String
        let initialBallCenter: CGPoint?
        let movementThresholdNorm: CGFloat
        let initialJitter: CGFloat
    }

    private struct TrackingPassResult {
        let observations: [ShotBallObservation]
        let debugInfos: [ShotFrameDebugInfo]
    }

    private struct ScanConfig {
        let brightnessThreshold: Int
        let maxChannelSpread: Int
        let minimumBrightSamples: Int
        let minNormWidth: CGFloat
        let maxNormWidth: CGFloat
        let minNormHeight: CGFloat
        let maxNormHeight: CGFloat
        let minAspect: CGFloat
        let maxAspect: CGFloat
    }

    private struct RawBlob {
        var minX: Int
        var maxX: Int
        var minY: Int
        var maxY: Int
        var sumX: Int
        var sumY: Int
        var count: Int
        var sumBrightness: Int
    }

    private struct Candidate {
        let rect: CGRect
        let center: CGPoint
        let diameter: CGFloat
        let confidence: Double
        let accepted: Bool
        let rejectionReason: String?
        let brightPixelCount: Int
        let meanBrightness: Int
    }

    private struct MaskComponent {
        var indices: [Int]
        var minCol: Int
        var maxCol: Int
        var minRow: Int
        var maxRow: Int
        var distanceSquared: CGFloat

        var count: Int { indices.count }
    }

    private struct MaskRefineOutput {
        let diameter: CGFloat?
        // Vertical extent of the mask component at FULL pixel resolution (fraction of frame
        // height). The stride-sampled bbox height quantizes in 2px steps (~6" of inferred ball
        // height each); this halves the quantum and is the preferred VLA-from-size input.
        let heightNorm: CGFloat?
        let whitePixelCount: Int
        let reason: String

        init(diameter: CGFloat?, heightNorm: CGFloat? = nil, whitePixelCount: Int, reason: String) {
            self.diameter = diameter
            self.heightNorm = heightNorm
            self.whitePixelCount = whitePixelCount
            self.reason = reason
        }
    }

    private let cfg: Configuration
    private var recentDiameters: [CGFloat] = []
    // Candidate-table lines accumulate here and flush as ONE print after the final pass.
    // ~120 individual print() calls per shot (each flushing to the console) measurably
    // stretched the analyzing screen; a single joined print is near-free.
    private var candidateLogLines: [String] = []

    init(configuration: Configuration = Configuration()) {
        self.cfg = configuration
    }

    // MARK: - Public

    func track(
        frames: [AnalyzedShotFrame],
        lockedBallRect: CGRect,
        impactFrameIndex fallbackImpactFrameIndex: Int
    ) -> TrackingResult {
        if cfg.isPostImpactDebugLoggingEnabled { logConfiguration() }

        let pixelData: [(bytes: [UInt8], width: Int, height: Int)?] = frames.map {
            pixelBytes(from: $0.darkenedHighContrastImage ?? $0.originalFrame.image)
        }

        let preConfig = makeScanConfig(pre: true)
        let postConfig = makeScanConfig(pre: false)

        let firstPass = runTrackingPass(
            frames: frames,
            pixelData: pixelData,
            impactFrameIndex: fallbackImpactFrameIndex,
            lockedBallRect: lockedBallRect,
            preConfig: preConfig,
            postConfig: postConfig
        )

        var impactResult = detectImpact(
            observations: firstPass.observations,
            fallbackImpactIndex: fallbackImpactFrameIndex
        )

        // Asymmetric plausibility window around the live-trigger fallback. The trigger only
        // ever fires AFTER true impact (the ball must exit the impact ROI first), so earlier
        // detections are trigger latency — real and expected, especially on putts. Later
        // detections (or absurdly early ones) mean club contamination → use fallback.
        let shift = impactResult.detectedImpactFrameIndex - fallbackImpactFrameIndex
        if shift < -cfg.impactDetection.maxEarlyShiftFrames || shift > cfg.impactDetection.maxLateShiftFrames {
            print("PostImpactBallTracker: detected impact frame \(impactResult.detectedImpactFrameIndex) is outside plausible window [fallback-\(cfg.impactDetection.maxEarlyShiftFrames), fallback+\(cfg.impactDetection.maxLateShiftFrames)] of \(fallbackImpactFrameIndex) — using fallback")
            impactResult = ImpactDetectionResult(
                detectedImpactFrameIndex: fallbackImpactFrameIndex,
                fallbackImpactFrameIndex: fallbackImpactFrameIndex,
                impactDetectionReason: impactResult.impactDetectionReason + "_rejected_outside_window",
                initialBallCenter: impactResult.initialBallCenter,
                movementThresholdNorm: impactResult.movementThresholdNorm,
                initialJitter: impactResult.initialJitter
            )
        } else if shift != 0 {
            print("PostImpactBallTracker: using movement-detected impact frame \(impactResult.detectedImpactFrameIndex) (live trigger fired \(-shift) frames late — normal for slow shots)")
        }

        let finalPass: TrackingPassResult
        if impactResult.detectedImpactFrameIndex != fallbackImpactFrameIndex {
            dbg("PostImpactBallTracker: re-tracking with detected impact frame \(impactResult.detectedImpactFrameIndex)")
            finalPass = runTrackingPass(
                frames: frames,
                pixelData: pixelData,
                impactFrameIndex: impactResult.detectedImpactFrameIndex,
                lockedBallRect: lockedBallRect,
                preConfig: preConfig,
                postConfig: postConfig
            )
        } else {
            finalPass = firstPass
        }

        // One print for the whole candidate table — individual per-line prints were a
        // measurable chunk of the analyzing-screen latency.
        if cfg.logCandidateDetail, !candidateLogLines.isEmpty {
            print(candidateLogLines.joined(separator: "\n"))
        }

        let result = TrackingResult(
            observations: finalPass.observations,
            debugInfos: finalPass.debugInfos,
            fallbackImpactFrameIndex: impactResult.fallbackImpactFrameIndex,
            detectedImpactFrameIndex: impactResult.detectedImpactFrameIndex,
            impactDetectionReason: impactResult.impactDetectionReason,
            initialBallCenter: impactResult.initialBallCenter,
            movementThresholdNorm: impactResult.movementThresholdNorm
        )
        Self.printSummary(result)
        return result
    }

    static func printSummary(_ result: TrackingResult) {
        dbg("Live post-impact tracking complete")
        dbg("Fallback impact frame: \(result.fallbackImpactFrameIndex)")
        dbg("Detected impact frame: \(result.detectedImpactFrameIndex)")
        dbg("Impact detection reason: \(result.impactDetectionReason)")

        let impact = result.detectedImpactFrameIndex
        let observations = result.observations
        let preObs = observations.filter { $0.frameIndex < impact }
        let postObs = observations.filter { $0.frameIndex > impact }
        let tracked = observations.filter { $0.centerX != nil }
        let preTracked = preObs.filter { $0.centerX != nil }.count
        let postTracked = postObs.filter { $0.centerX != nil }.count

        dbg("Pre-impact tracked: \(preTracked)/\(preObs.count)")
        dbg("Post-impact tracked: \(postTracked)/\(postObs.count)")
        dbg("Total tracked: \(tracked.count)/\(observations.count)")

        let candidateDiameters = tracked.compactMap { $0.candidateDiameter }
        let refinedDiameters = tracked.compactMap { $0.refinedDiameter }
        let finalDiameters = tracked.compactMap { $0.finalDiameter ?? $0.diameter }
        let maskFailed = tracked.count - refinedDiameters.count

        dbg("Diameter refinement summary")
        dbg("Frames refined: \(refinedDiameters.count)")
        dbg("Mask failed: \(maskFailed)")
        dbg(String(format: "Average candidate diameter: %.4f", average(candidateDiameters)))
        dbg(String(format: "Average refined diameter: %.4f", average(refinedDiameters)))
        dbg(String(format: "Average final diameter: %.4f", average(finalDiameters)))

        dbg("--- Live per-frame tracking table ---")
        for obs in observations {
            let marker = obs.frameIndex == impact ? " <- impact" : ""
            if let cx = obs.centerX, let cy = obs.centerY, let d = obs.finalDiameter ?? obs.diameter {
                let cand = obs.candidateDiameter.map { String(format: "%.4f", $0) } ?? "n/a"
                let refined = obs.refinedDiameter.map { String(format: "%.4f", $0) } ?? "n/a"
                dbg(String(format: "frame=%02d t=%+.4f x=%.4f y=%.4f finalD=%.4f candD=%@ refinedD=%@ maskPx=%d reason=%@ conf=%.2f%@",
                             obs.frameIndex, obs.relativeTime, cx, cy, d, cand, refined,
                             obs.maskWhitePixelCount, obs.diameterDebugReason ?? "n/a",
                             obs.confidence, marker))
            } else {
                dbg(String(format: "frame=%02d t=%+.4f miss reason=%@%@",
                             obs.frameIndex, obs.relativeTime, obs.debugReason ?? "unknown", marker))
            }
        }
    }

    // Compatibility helper for older call sites.
    static func printSummary(_ observations: [ShotBallObservation], impactFrameIndex: Int) {
        let result = TrackingResult(
            observations: observations,
            debugInfos: [],
            fallbackImpactFrameIndex: impactFrameIndex,
            detectedImpactFrameIndex: impactFrameIndex,
            impactDetectionReason: "legacy_summary",
            initialBallCenter: nil,
            movementThresholdNorm: 0
        )
        printSummary(result)
    }

    // MARK: - Tracking Pass

    private func runTrackingPass(
        frames: [AnalyzedShotFrame],
        pixelData: [(bytes: [UInt8], width: Int, height: Int)?],
        impactFrameIndex: Int,
        lockedBallRect: CGRect,
        preConfig: ScanConfig,
        postConfig: ScanConfig
    ) -> TrackingPassResult {
        recentDiameters = []
        candidateLogLines = []   // only the final pass's table gets printed

        var observations: [ShotBallObservation] = []
        var debugInfos: [ShotFrameDebugInfo] = []
        var lastPreCenter = lockedBallRect.center
        var postImpactSeedCenter = lockedBallRect.center
        var lastPostCenter: CGPoint?

        // Python-matching accumulated post-impact tracking state
        let initCenter = lockedBallRect.center
        var launchDir: (dx: CGFloat, dy: CGFloat)? = nil
        var ballLaunched = false
        var ballTerminated = false
        var consecutiveMissesAfterLaunch = 0
        // Monotonic progress along the launch path — the ball never comes back.
        var lastProgress: CGFloat = 0
        var expectedDiameter: CGFloat? = nil
        var preFinalDiameters: [CGFloat] = []
        var recentPostPoints: [(x: CGFloat, y: CGFloat, t: Double)] = []
        let maxRecentPostPoints = 4  // Python: deque(maxlen=sc_lookback+1=4)

        for (i, frame) in frames.enumerated() {
            let idx = frame.frameIndex
            guard i < pixelData.count, let pd = pixelData[i] else {
                observations.append(miss(frame, reason: "no_pixel_data"))
                debugInfos.append(ShotFrameDebugInfo(
                    frameIndex: idx,
                    searchROI: nil,
                    candidateCount: 0,
                    rejectionReason: "no_pixel_data",
                    searchCenterSource: "none",
                    searchScale: 0
                ))
                continue
            }

            if idx < impactFrameIndex {
                let roi = expanded(lockedBallRect, scale: cfg.preImpactSearchScale)
                let lockedDiameter = (lockedBallRect.width + lockedBallRect.height) / 2
                // Anchor to the LOCKED center, not the drifting last pick — pre-impact the ball
                // hasn't moved yet, so "nearest to wherever we wandered last frame" is exactly
                // how one club pick walked the whole pre-track onto the club.
                let anchor = lockedBallRect.center
                let (candidates, chosenRaw) = findCandidates(
                    pd,
                    roi: roi,
                    config: preConfig,
                    preferredCenter: anchor,
                    expectedDiameter: lockedDiameter
                )
                var chosen = chosenRaw
                var driftReason: String? = nil
                if let c = chosen {
                    let drift = hypot(c.center.x - anchor.x, c.center.y - anchor.y)
                    let maxDrift = lockedDiameter * cfg.preAnchorMaxDriftDiameters
                    if drift > maxDrift {
                        driftReason = String(format: "pre_drift_reject(%.3f>%.3f)", drift, maxDrift)
                        chosen = nil
                    }
                }
                logCandidateTable(frameIndex: idx, phase: "pre", chosen: chosen,
                                  candidates: candidates, expectedDiameter: lockedDiameter)
                let reason = chosen == nil ? (driftReason ?? firstRejectionReason(candidates)) : nil
                if let c = chosen {
                    let obs = makeHit(frame, c, pd: pd)
                    observations.append(obs)
                    lastPreCenter = c.center
                    postImpactSeedCenter = c.center
                    if let d = obs.finalDiameter ?? obs.diameter { preFinalDiameters.append(d) }
                } else {
                    observations.append(miss(frame, reason: reason ?? "no_candidate"))
                }
                // Part G: parity diagnostic — detailed logging near impact
                if cfg.isPostImpactDebugLoggingEnabled && idx >= impactFrameIndex - 4 {
                    let topCand = candidates.max(by: { $0.brightPixelCount < $1.brightPixelCount })
                    dbg(String(format: "PARITY frame=%02ld phase=pre minBrightPx=%ld stride=%ld roiW=%.3f topCandPx=%ld topCandW=%.4f topCandH=%.4f reason=%@",
                                 idx, preConfig.minimumBrightSamples, cfg.sampleStride,
                                 Double(roi.width),
                                 topCand?.brightPixelCount ?? 0,
                                 Double(topCand?.rect.width ?? 0),
                                 Double(topCand?.rect.height ?? 0),
                                 reason ?? (chosen != nil ? "ok" : "no_blobs")))
                }
                debugInfos.append(ShotFrameDebugInfo(
                    frameIndex: idx,
                    searchROI: roi,
                    candidateCount: candidates.reduce(0) { $0 + $1.brightPixelCount },
                    rejectionReason: reason,
                    searchCenterSource: "lockedBall",
                    searchScale: cfg.preImpactSearchScale
                ))
            } else if idx == impactFrameIndex {
                let roi = expanded(lockedBallRect, scale: cfg.impactSearchScale)
                let lockedDiameter = (lockedBallRect.width + lockedBallRect.height) / 2
                let (candidates, chosenRaw) = findCandidates(
                    pd,
                    roi: roi,
                    config: preConfig,
                    preferredCenter: lastPreCenter,
                    expectedDiameter: lockedDiameter
                )
                logCandidateTable(frameIndex: idx, phase: "impact", chosen: chosenRaw,
                                  candidates: candidates, expectedDiameter: lockedDiameter)
                var chosen = chosenRaw
                // Strict impact diameter gate: reject if candidate is >1.25× pre-impact median diameter
                if cfg.enableStrictImpactDiameterGate, let c = chosen {
                    let preImpactDiameters = observations.compactMap { $0.finalDiameter ?? $0.diameter }
                    if !preImpactDiameters.isEmpty {
                        let sorted = preImpactDiameters.sorted()
                        let median = sorted[sorted.count / 2]
                        let ratio = c.diameter / median
                        if median > 1e-6 && ratio > cfg.impactFrameMaxDiameterGrowthRatio {
                            dbg("[PostImpactBallTracker] Strict impact gate: frame=\(idx) ratio=\(String(format:"%.2f",ratio)) > \(cfg.impactFrameMaxDiameterGrowthRatio), rejecting merged candidate")
                            chosen = nil
                        }
                    }
                }
                let reason: String?
                if chosen == nil && chosenRaw != nil {
                    reason = "rejected_strict_impact_diameter_gate"
                } else {
                    reason = chosen == nil ? firstRejectionReason(candidates) : nil
                }
                if let c = chosen {
                    let obs = makeHit(frame, c, pd: pd)
                    observations.append(obs)
                    lastPreCenter = c.center
                    if let d = obs.finalDiameter ?? obs.diameter { preFinalDiameters.append(d) }
                } else {
                    observations.append(miss(frame, reason: reason ?? "no_candidate"))
                }
                debugInfos.append(ShotFrameDebugInfo(
                    frameIndex: idx,
                    searchROI: roi,
                    candidateCount: candidates.reduce(0) { $0 + $1.brightPixelCount },
                    rejectionReason: reason,
                    searchCenterSource: "lockedBall",
                    searchScale: cfg.impactSearchScale
                ))
            } else {
                // === Python-matching post-impact tracking ===

                // Set expectedDiameter from pre-impact median on first post-impact frame
                if expectedDiameter == nil, !preFinalDiameters.isEmpty {
                    let sorted = preFinalDiameters.sorted()
                    expectedDiameter = sorted[sorted.count / 2]
                }

                // After termination, emit miss for all remaining frames
                if ballTerminated {
                    observations.append(miss(frame, reason: "terminated"))
                    debugInfos.append(ShotFrameDebugInfo(
                        frameIndex: idx, searchROI: nil, candidateCount: 0,
                        rejectionReason: "terminated", searchCenterSource: "terminated", searchScale: 0
                    ))
                    continue
                }

                // ROI center: last tracked post position, or pre-impact seed
                let roiCenter = lastPostCenter ?? postImpactSeedCenter
                let hasTracking = lastPostCenter != nil

                // Linear prediction from recent post points (Python: compute_predicted)
                let predictedPos = computePredictedPosition(recentPostPoints, initCenter: initCenter)

                // Forward-biased oriented ROI using tracked launch direction when known
                let roi = forwardBiasedPostROI(
                    center: roiCenter,
                    base: lockedBallRect.width,
                    hasTracking: hasTracking,
                    launchDir: launchDir
                )

                // Find all candidates (accepted + rejected) for rescue. Expected size: the
                // pre-impact median when available, else the locked-rect diameter.
                let postExpectedDiameter = expectedDiameter
                    ?? (lockedBallRect.width + lockedBallRect.height) / 2
                let (allCandidates, chosen0) = findCandidates(
                    pd, roi: roi, config: postConfig, preferredCenter: roiCenter,
                    expectedDiameter: postExpectedDiameter
                )
                var chosen: Candidate? = chosen0
                logCandidateTable(frameIndex: idx, phase: "post", chosen: chosen0,
                                  candidates: allCandidates, expectedDiameter: postExpectedDiameter)

                // Prediction cross rescue: if no normal candidate, search ALL raw candidates
                // near the predicted position — including size-rejected blobs (Python: enable_prediction_cross_rescue)
                if chosen == nil, let pred = predictedPos {
                    chosen = predictionCrossRescue(
                        allCandidates: allCandidates,
                        predictedPos: pred,
                        launchDir: launchDir,
                        initCenter: initCenter,
                        ballLaunched: ballLaunched,
                        expectedDiameter: expectedDiameter,
                        pd: pd,
                        frameIndex: idx
                    )
                }

                // Monotonicity: the ball only moves away from the impact point (along the launch
                // direction once locked). A pick whose progress regresses is the club swinging
                // through the same region — drop it (better a miss than a track that teleports
                // back to the clubhead, which is what the user observed).
                if let c = chosen {
                    let progress: CGFloat
                    if let ld = launchDir {
                        progress = (c.center.x - initCenter.x) * ld.dx + (c.center.y - initCenter.y) * ld.dy
                    } else {
                        progress = hypot(c.center.x - initCenter.x, c.center.y - initCenter.y)
                    }
                    if progress < lastProgress - cfg.monotonicBacktrackAllowanceNorm {
                        if cfg.logCandidateDetail {
                            candidateLogLines.append(String(format: "[TrackDebug] f=%02d post MONOTONIC REJECT (%.3f,%.3f) progress=%.4f < last=%.4f",
                                         idx, c.center.x, c.center.y, progress, lastProgress))
                        }
                        chosen = nil
                    } else {
                        lastProgress = max(lastProgress, progress)
                    }
                }

                // Debug log (Part G: detailed parity diagnostics for early post-impact frames)
                if cfg.isPostImpactDebugLoggingEnabled {
                    let roiStr = String(format: "(x=%.3f y=%.3f w=%.3f h=%.3f)",
                                       roi.minX, roi.minY, roi.width, roi.height)
                    let predStr = predictedPos.map { String(format: "pred=(%.4f,%.4f)", $0.x, $0.y) } ?? "pred=nil"
                    if let c = chosen {
                        dbg(String(format: "frame=%02d postROI=%@ %@ selected=(x=%.4f y=%.4f d=%.4f conf=%.2f)",
                                     idx, roiStr, predStr, c.center.x, c.center.y, c.diameter, c.confidence))
                    } else {
                        let bright = allCandidates.reduce(0) { $0 + $1.brightPixelCount }
                        dbg(String(format: "frame=%02d postROI=%@ %@ selected=nil reason=%@ bright=%d",
                                     idx, roiStr, predStr, firstRejectionReason(allCandidates), bright))
                    }
                    // Part G: extended per-candidate diagnostics for early frames
                    let postOffset = idx - impactFrameIndex
                    if postOffset <= 6 {
                        for cand in allCandidates {
                            let passesPython = cand.brightPixelCount >= 4
                                && cand.rect.width >= 0.018
                                && cand.rect.height >= 0.005
                            dbg(String(format: "  PARITY frame=%02d phase=post%d minPx=%d stride=%d cand=(x=%.4f y=%.4f nw=%.4f nh=%.4f px=%d) reason=%@ wouldPassPython=%@",
                                         idx, postOffset, postConfig.minimumBrightSamples, cfg.sampleStride,
                                         cand.center.x, cand.center.y,
                                         cand.rect.width, cand.rect.height,
                                         cand.brightPixelCount,
                                         cand.rejectionReason ?? "ok",
                                         passesPython ? "yes" : "no"))
                        }
                        if allCandidates.isEmpty {
                            dbg(String(format: "  PARITY frame=%02d phase=post%d minPx=%d stride=%d NO_BLOBS_FOUND",
                                         idx, postOffset, postConfig.minimumBrightSamples, cfg.sampleStride))
                        }
                    }
                }

                // Build observation and update state
                let observation: ShotBallObservation
                if let c = chosen {
                    observation = makeHit(frame, c, pd: pd)
                    lastPostCenter = c.center

                    // Accumulate recent post points for prediction (Python: sc_lookback=3 → maxlen=4)
                    recentPostPoints.append((x: c.center.x, y: c.center.y, t: frame.relativeTime))
                    if recentPostPoints.count > maxRecentPostPoints { recentPostPoints.removeFirst() }
                    consecutiveMissesAfterLaunch = 0

                    // Lock launch direction once ball has traveled ≥ sc_lock_dist (0.02) from impact position
                    if !ballLaunched {
                        let ddx = c.center.x - initCenter.x
                        let ddy = c.center.y - initCenter.y
                        let dist = hypot(ddx, ddy)
                        if dist >= cfg.launchLockDistanceNorm {
                            launchDir = (dx: ddx / dist, dy: ddy / dist)
                            ballLaunched = true
                            dbg(String(format: "Ball launched at frame %d dir=(%.3f,%.3f)", idx, ddx / dist, ddy / dist))
                        }
                    }

                    // The ball has reached the frame edge — it's leaving. End the track here so
                    // subsequent frames can't adopt static junk blobs near the border.
                    let em = cfg.edgeTerminationMarginNorm
                    if c.center.x < em || c.center.x > 1 - em || c.center.y < em || c.center.y > 1 - em {
                        ballTerminated = true
                        if cfg.logCandidateDetail {
                            candidateLogLines.append(String(format: "[TrackDebug] f=%02d ball at frame edge (%.3f,%.3f) — track terminated", idx, c.center.x, c.center.y))
                        }
                    }
                } else {
                    observation = miss(frame, reason: firstRejectionReason(allCandidates))
                    if ballLaunched {
                        consecutiveMissesAfterLaunch += 1
                        // Termination: Python sc_term_miss_limit=3, sc_term_min_progress=0.05 (default)
                        let maxProgress: CGFloat = lastPostCenter.map {
                            hypot($0.x - initCenter.x, $0.y - initCenter.y)
                        } ?? 0
                        if consecutiveMissesAfterLaunch >= 3 && maxProgress >= cfg.terminationMinProgressNorm {
                            ballTerminated = true
                            dbg(String(format: "Ball track terminated at frame %d after %d misses maxProgress=%.4f",
                                         idx, consecutiveMissesAfterLaunch, maxProgress))
                        }
                    }
                }

                observations.append(observation)
                debugInfos.append(ShotFrameDebugInfo(
                    frameIndex: idx,
                    searchROI: roi,
                    candidateCount: allCandidates.reduce(0) { $0 + $1.brightPixelCount },
                    rejectionReason: chosen == nil ? firstRejectionReason(allCandidates) : nil,
                    searchCenterSource: hasTracking ? "previousDetection" : "seedCenter_fallback",
                    searchScale: hasTracking ? cfg.postVertScaleTracked : cfg.postVertScaleUntracked
                ))
            }
        }

        return TrackingPassResult(observations: observations, debugInfos: debugInfos)
    }

    // MARK: - Prediction (Python: compute_predicted)

    private func computePredictedPosition(
        _ points: [(x: CGFloat, y: CGFloat, t: Double)],
        initCenter: CGPoint
    ) -> CGPoint? {
        if points.count >= 2 {
            let last = points[points.count - 1]
            let prev = points[points.count - 2]
            let dt = last.t - prev.t
            if abs(dt) < 1e-9 {
                return CGPoint(x: last.x + (last.x - prev.x), y: last.y + (last.y - prev.y))
            }
            let vx = CGFloat((last.x - prev.x) / CGFloat(dt))
            let vy = CGFloat((last.y - prev.y) / CGFloat(dt))
            return CGPoint(x: last.x + vx * CGFloat(dt), y: last.y + vy * CGFloat(dt))
        }
        // Single-point prediction: project from initCenter through first post point
        if let p = points.first {
            let dx = p.x - initCenter.x
            let dy = p.y - initCenter.y
            let dist = hypot(dx, dy)
            guard dist > 1e-6 else { return nil }
            let step = min(max(dist, 0.006), 0.12)
            return CGPoint(x: p.x + dx / dist * step, y: p.y + dy / dist * step)
        }
        return nil
    }

    // MARK: - Prediction Cross Rescue (Python: enable_prediction_cross_rescue)
    // Searches ALL raw candidates (including size-rejected blobs with count≥4) near the
    // predicted position. This is Python's primary recovery mechanism for frames where the
    // ball produces a faint/narrow detection that fails normal quality gates.

    private func predictionCrossRescue(
        allCandidates: [Candidate],
        predictedPos: CGPoint,
        launchDir: (dx: CGFloat, dy: CGFloat)?,
        initCenter: CGPoint,
        ballLaunched: Bool,
        expectedDiameter: CGFloat?,
        pd: (bytes: [UInt8], width: Int, height: Int),
        frameIndex: Int
    ) -> Candidate? {
        let rescueRadius: CGFloat = 0.055       // prediction_rescue_radius_norm
        let circleScale: CGFloat = 1.25         // prediction_rescue_inside_circle_scale
        let maxLineResidX3: CGFloat = 0.075     // prediction_rescue_max_line_residual * 3 (generous)
        let rescueMinDr: CGFloat = 0.35         // prediction_rescue_min_diam_ratio
        let rescueMinPx = 8                     // prediction_rescue_min_mask_pixels

        var bestCandidate: Candidate? = nil
        var bestScore: CGFloat = -999

        for candidate in allCandidates {
            // Python: skip extremely tiny blobs (1-3 pixels)
            guard candidate.brightPixelCount >= 4 else { continue }

            // Python: skip if diameter is wildly wrong vs expected
            if let exp = expectedDiameter, exp > 0 {
                let dr = candidate.diameter / exp
                guard dr >= 0.20 && dr <= 5.0 else { continue }
            }

            // Proximity checks to predicted position
            let predDist = hypot(candidate.center.x - predictedPos.x, candidate.center.y - predictedPos.y)
            let candRadius = candidate.diameter / 2.0
            let insideRect = candidate.rect.contains(predictedPos)
            let insideCircle = predDist <= candRadius * circleScale
            let nearPred = predDist <= rescueRadius
            guard insideRect || insideCircle || nearPred else { continue }

            // Forward progress gate (Python: prediction_rescue_require_forward_progress)
            if let ld = launchDir, ballLaunched {
                let fwd = (candidate.center.x - initCenter.x) * ld.dx
                    + (candidate.center.y - initCenter.y) * (-ld.dy)
                guard fwd >= -0.015 else { continue }  // cone_backward_allowance
            }

            // Line residual gate — generous 3× threshold (Python: prediction_rescue_max_line_residual)
            if let ld = launchDir, ballLaunched {
                let dx = candidate.center.x - initCenter.x
                let dy = candidate.center.y - initCenter.y
                let perp = abs(dx * ld.dy - dy * ld.dx)
                guard perp <= maxLineResidX3 else { continue }
            }

            // Run mask refinement
            let maskOutput = maskRefineDiameter(
                pd, center: candidate.center,
                candidateDiameter: candidate.diameter,
                config: cfg.diameterRefinement
            )

            // Hard minimum: mask must have ≥ 4 white pixels
            guard maskOutput.whitePixelCount >= 4 else { continue }

            // Quality gate: relaxed for strong prediction (inside rect or circle)
            let predStrong = insideRect || insideCircle
            if maskOutput.whitePixelCount < rescueMinPx && !predStrong { continue }

            // Diameter ratio gate
            let refDia = maskOutput.diameter ?? candidate.diameter
            if let exp = expectedDiameter, exp > 0, refDia / exp < rescueMinDr { continue }

            // Compute rescue score (Python: inside bonus + near bonus + quality)
            var score: CGFloat = 0
            if insideRect { score += 12.0 }
            if insideCircle { score += 12.0 * 0.7 }
            if nearPred { score += 7.0 * (1.0 - predDist / max(rescueRadius, 1e-6)) }
            score += min(1.0, CGFloat(maskOutput.whitePixelCount) / 20.0)

            if score > bestScore {
                bestScore = score
                bestCandidate = candidate
            }
        }

        if let best = bestCandidate {
            dbg(String(format: "frame=%02d pred_cross_rescue: (%.4f,%.4f) score=%.2f count=%d",
                         frameIndex, best.center.x, best.center.y, bestScore, best.brightPixelCount))
        }
        return bestCandidate
    }

    // MARK: - Connected-Components Candidate Scanner

    private func findCandidates(
        _ pd: (bytes: [UInt8], width: Int, height: Int),
        roi: CGRect,
        config: ScanConfig,
        preferredCenter: CGPoint,
        expectedDiameter: CGFloat? = nil
    ) -> ([Candidate], Candidate?) {
        let (bytes, width, height) = pd
        let step = max(1, cfg.sampleStride)

        let xStart = max(0, Int(roi.minX * CGFloat(width)))
        let xEnd = min(width, Int(roi.maxX * CGFloat(width)))
        let yStart = max(0, Int(roi.minY * CGFloat(height)))
        let yEnd = min(height, Int(roi.maxY * CGFloat(height)))
        guard xEnd > xStart, yEnd > yStart else {
            return ([], nil)
        }

        let cols = (xEnd - xStart + step - 1) / step
        let rows = (yEnd - yStart + step - 1) / step
        var bright = [Bool](repeating: false, count: cols * rows)
        var visited = [Bool](repeating: false, count: cols * rows)
        var lumaGrid = [UInt8](repeating: 0, count: cols * rows)

        for row in 0..<rows {
            let py = yStart + row * step
            let baseRow = py * width * 4
            for col in 0..<cols {
                let px = xStart + col * step
                let i = baseRow + px * 4
                let r = Int(bytes[i])
                let g = Int(bytes[i + 1])
                let b = Int(bytes[i + 2])
                let brightness = (r + g + b) / 3
                let spread = max(r, max(g, b)) - min(r, min(g, b))
                bright[row * cols + col] = brightness >= config.brightnessThreshold
                    && spread <= config.maxChannelSpread
                lumaGrid[row * cols + col] = UInt8(brightness)
            }
        }

        var blobs: [RawBlob] = []
        for startRow in 0..<rows {
            for startCol in 0..<cols {
                let startIndex = startRow * cols + startCol
                guard bright[startIndex], !visited[startIndex] else { continue }

                var blob = RawBlob(
                    minX: Int.max,
                    maxX: 0,
                    minY: Int.max,
                    maxY: 0,
                    sumX: 0,
                    sumY: 0,
                    count: 0,
                    sumBrightness: 0
                )
                var queue = [startIndex]
                var head = 0
                visited[startIndex] = true

                while head < queue.count {
                    let index = queue[head]
                    head += 1
                    let col = index % cols
                    let row = index / cols
                    let px = xStart + col * step
                    let py = yStart + row * step

                    blob.count += 1
                    blob.sumX += px
                    blob.sumY += py
                    blob.sumBrightness += Int(lumaGrid[index])
                    if px < blob.minX { blob.minX = px }
                    if px > blob.maxX { blob.maxX = px }
                    if py < blob.minY { blob.minY = py }
                    if py > blob.maxY { blob.maxY = py }

                    for offset in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                        let nextCol = col + offset.0
                        let nextRow = row + offset.1
                        guard nextCol >= 0, nextCol < cols, nextRow >= 0, nextRow < rows else {
                            continue
                        }
                        let nextIndex = nextRow * cols + nextCol
                        if bright[nextIndex], !visited[nextIndex] {
                            visited[nextIndex] = true
                            queue.append(nextIndex)
                        }
                    }
                }
                blobs.append(blob)
            }
        }

        let candidates = blobs.map {
            evaluateBlob($0, step: step, width: width, height: height, config: config)
        }
        let accepted = candidates.filter { $0.accepted }

        // Prefer candidates whose size matches the known ball diameter. A bright putter
        // marking (alignment line, chrome glare) can sit closer to the previous center than
        // the ball itself — proximity alone picked it. Only when no candidate is
        // size-consistent do we fall back to any accepted candidate.
        let pool: [Candidate]
        if let expected = expectedDiameter, expected > 1e-6 {
            let sizeConsistent = accepted.filter {
                let ratio = $0.diameter / expected
                return ratio >= cfg.chosenDiameterRatioMin && ratio <= cfg.chosenDiameterRatioMax
            }
            pool = sizeConsistent.isEmpty ? accepted : sizeConsistent
        } else {
            pool = accepted
        }

        let chosen = pool.min {
            hypot($0.center.x - preferredCenter.x, $0.center.y - preferredCenter.y)
                < hypot($1.center.x - preferredCenter.x, $1.center.y - preferredCenter.y)
        }

        return (candidates, chosen)
    }

    // One compact line per frame: every blob the scanner considered, with the chosen one
    // starred. This is the "what else did it see and why didn't it pick the ball" view.
    private func logCandidateTable(
        frameIndex: Int, phase: String, chosen: Candidate?,
        candidates: [Candidate], expectedDiameter: CGFloat?
    ) {
        guard cfg.logCandidateDetail else { return }
        let expStr = expectedDiameter.map { String(format: "%.4f", $0) } ?? "n/a"
        if candidates.isEmpty {
            candidateLogLines.append("[TrackDebug] f=\(String(format: "%02d", frameIndex)) \(phase) expD=\(expStr) NO BLOBS")
            return
        }
        // Largest blobs first; cap the line at 6 entries to stay readable.
        let sorted = candidates.sorted { $0.brightPixelCount > $1.brightPixelCount }.prefix(6)
        let entries = sorted.map { c -> String in
            let star = (chosen != nil && c.center == chosen!.center && c.diameter == chosen!.diameter) ? "*" : ""
            let status = c.accepted ? "ok" : (c.rejectionReason ?? "rej")
            return String(format: "%@(%.3f,%.3f d=%.4f br=%d px=%d %@)",
                          star, c.center.x, c.center.y, c.diameter, c.meanBrightness, c.brightPixelCount, status)
        }
        candidateLogLines.append("[TrackDebug] f=\(String(format: "%02d", frameIndex)) \(phase) expD=\(expStr) cands: \(entries.joined(separator: " "))")
    }

    private func evaluateBlob(
        _ blob: RawBlob,
        step: Int,
        width: Int,
        height: Int,
        config: ScanConfig
    ) -> Candidate {
        let cx = CGFloat(blob.sumX) / CGFloat(blob.count) / CGFloat(width)
        let cy = CGFloat(blob.sumY) / CGFloat(blob.count) / CGFloat(height)
        let boxWidth = CGFloat(blob.maxX - blob.minX + step)
        let boxHeight = CGFloat(blob.maxY - blob.minY + step)
        let normWidth = boxWidth / CGFloat(width)
        let normHeight = boxHeight / CGFloat(height)
        let aspect = normWidth / max(normHeight, 1e-6)
        let diameter = (normWidth + normHeight) / 2
        let rect = CGRect(
            x: CGFloat(blob.minX) / CGFloat(width),
            y: CGFloat(blob.minY) / CGFloat(height),
            width: normWidth,
            height: normHeight
        )
        let confidence = min(1.0, Double(blob.count) / Double(config.minimumBrightSamples * 4))

        let reason: String?
        if blob.count < config.minimumBrightSamples {
            reason = "too_few_pixels(\(blob.count)<\(config.minimumBrightSamples))"
        } else if normWidth < config.minNormWidth {
            reason = "w_small(\(String(format: "%.4f", normWidth)))"
        } else if normWidth > config.maxNormWidth {
            reason = "w_large(\(String(format: "%.4f", normWidth)))"
        } else if normHeight < config.minNormHeight {
            reason = "h_small(\(String(format: "%.4f", normHeight)))"
        } else if normHeight > config.maxNormHeight {
            reason = "h_large(\(String(format: "%.4f", normHeight)))"
        } else if aspect < config.minAspect {
            reason = "asp_low(\(String(format: "%.2f", aspect)))"
        } else if aspect > config.maxAspect {
            reason = "asp_high(\(String(format: "%.2f", aspect)))"
        } else {
            reason = nil
        }

        return Candidate(
            rect: rect,
            center: CGPoint(x: cx, y: cy),
            diameter: diameter,
            confidence: reason == nil ? confidence : 0,
            accepted: reason == nil,
            rejectionReason: reason,
            brightPixelCount: blob.count,
            meanBrightness: blob.count > 0 ? blob.sumBrightness / blob.count : 0
        )
    }

    // MARK: - Diameter Refinement

    private func makeHit(
        _ frame: AnalyzedShotFrame,
        _ candidate: Candidate,
        pd: (bytes: [UInt8], width: Int, height: Int)
    ) -> ShotBallObservation {
        let candidateDiameter = candidate.diameter
        let maskOutput = cfg.diameterRefinement.enabled
            ? maskRefineDiameter(
                pd,
                center: candidate.center,
                candidateDiameter: candidateDiameter,
                config: cfg.diameterRefinement
            )
            : MaskRefineOutput(diameter: nil, whitePixelCount: 0, reason: "refinement_disabled")

        let baseDiameter = maskOutput.diameter ?? candidateDiameter
        recentDiameters.append(baseDiameter)
        let windowSize = max(2, cfg.diameterRefinement.smoothingWindowSize)
        if recentDiameters.count > windowSize {
            recentDiameters.removeFirst()
        }

        let smoothedDiameter: CGFloat?
        if cfg.diameterRefinement.smoothingEnabled, recentDiameters.count >= 2 {
            smoothedDiameter = median(recentDiameters)
        } else {
            smoothedDiameter = nil
        }

        let finalDiameter = smoothedDiameter ?? maskOutput.diameter ?? candidateDiameter
        let diameterReason: String
        if smoothedDiameter != nil {
            diameterReason = "smoothed"
        } else if maskOutput.diameter != nil {
            diameterReason = maskOutput.reason
        } else if cfg.diameterRefinement.enabled {
            diameterReason = maskOutput.reason
        } else {
            diameterReason = "candidate_no_refinement"
        }

        return ShotBallObservation(
            frameIndex: frame.frameIndex,
            timestamp: frame.timestamp,
            relativeTime: frame.relativeTime,
            centerX: candidate.center.x,
            centerY: candidate.center.y,
            diameter: finalDiameter,
            candidateDiameter: candidateDiameter,
            refinedDiameter: maskOutput.diameter,
            smoothedDiameter: smoothedDiameter,
            finalDiameter: finalDiameter,
            confidence: candidate.confidence,
            wasInterpolated: false,
            debugReason: "ok",
            diameterDebugReason: diameterReason,
            maskWhitePixelCount: maskOutput.whitePixelCount,
            // Prefer the pixel-resolution mask height (1px quanta) over the stride-sampled
            // candidate bbox (2px quanta) — VLA-from-size is quantization-limited.
            bboxHeightNorm: maskOutput.heightNorm ?? candidate.rect.height
        )
    }

    private func maskRefineDiameter(
        _ pd: (bytes: [UInt8], width: Int, height: Int),
        center: CGPoint,
        candidateDiameter: CGFloat,
        config: DiameterRefinementConfig
    ) -> MaskRefineOutput {
        let (bytes, width, height) = pd
        let cx = Int((center.x * CGFloat(width)).rounded())
        let cy = Int((center.y * CGFloat(height)).rounded())
        guard cx >= 0, cx < width, cy >= 0, cy < height else {
            return MaskRefineOutput(
                diameter: nil,
                whitePixelCount: 0,
                reason: "mask_failed_center_oob"
            )
        }

        let radiusPx = max(
            4,
            Int((config.localMaskWindowScale * candidateDiameter * CGFloat(width) / 2).rounded())
        )
        let cropSize = radiusPx * 2 + 1
        let cropOriginX = cx - radiusPx
        let cropOriginY = cy - radiusPx

        let x0 = max(0, cx - radiusPx)
        let x1 = min(width - 1, cx + radiusPx)
        let y0 = max(0, cy - radiusPx)
        let y1 = min(height - 1, cy + radiusPx)

        var patchBrightness: [Int] = []
        for py in y0...y1 {
            for px in x0...x1 {
                let pixelIndex = py * width * 4 + px * 4
                let r = Int(bytes[pixelIndex])
                let g = Int(bytes[pixelIndex + 1])
                let b = Int(bytes[pixelIndex + 2])
                patchBrightness.append((r + g + b) / 3)
            }
        }
        let effectiveMaskThreshold: Int
        if config.maskPercentile > 0, !patchBrightness.isEmpty {
            let sorted = patchBrightness.sorted()
            let pctIdx = min(Int(Double(sorted.count) * Double(config.maskPercentile) / 100.0), sorted.count - 1)
            let pctThresh = sorted[pctIdx]
            let medianThresh = sorted[sorted.count / 2] + config.maskBgDelta
            let rawThresh = max(config.maskBrightnessThreshold, max(pctThresh, medianThresh))
            effectiveMaskThreshold = max(config.maskPercentileMinBright, min(245, rawThresh))
        } else {
            effectiveMaskThreshold = config.maskBrightnessThreshold
        }

        var thresholdMask = [Bool](repeating: false, count: cropSize * cropSize)
        for py in y0...y1 {
            for px in x0...x1 {
                let col = px - cropOriginX
                let row = py - cropOriginY
                guard col >= 0, col < cropSize, row >= 0, row < cropSize else { continue }

                let pixelIndex = py * width * 4 + px * 4
                let r = Int(bytes[pixelIndex])
                let g = Int(bytes[pixelIndex + 1])
                let b = Int(bytes[pixelIndex + 2])
                let brightness = (r + g + b) / 3
                thresholdMask[row * cropSize + col] = brightness >= effectiveMaskThreshold
            }
        }

        let selection = mainMaskComponent(
            in: thresholdMask,
            cropSize: cropSize,
            targetCol: cx - cropOriginX,
            targetRow: cy - cropOriginY,
            maxCenterDriftPx: max(2, candidateDiameter * CGFloat(width) * 0.55)
        )

        guard let component = selection.component else {
            return MaskRefineOutput(
                diameter: nil,
                whitePixelCount: 0,
                reason: selection.failureReason
            )
        }

        let bboxWidthPx = component.maxCol - component.minCol + 1
        let bboxHeightPx = component.maxRow - component.minRow + 1
        let diameterPx = max(bboxWidthPx, bboxHeightPx)
        let refinedDiameter = CGFloat(diameterPx) / CGFloat(width)

        return MaskRefineOutput(
            diameter: refinedDiameter,
            heightNorm: CGFloat(bboxHeightPx) / CGFloat(height),
            whitePixelCount: component.count,
            reason: "mask_refined_threshold_\(effectiveMaskThreshold)_connected"
        )
    }

    private func mainMaskComponent(
        in mask: [Bool],
        cropSize: Int,
        targetCol: Int,
        targetRow: Int,
        maxCenterDriftPx: CGFloat
    ) -> (component: MaskComponent?, failureReason: String) {
        guard cropSize > 0, mask.count == cropSize * cropSize else {
            return (nil, "mask_failed_invalid_crop")
        }

        var visited = [Bool](repeating: false, count: mask.count)
        var components: [MaskComponent] = []

        for startIndex in mask.indices {
            guard mask[startIndex], !visited[startIndex] else { continue }

            var queue = [startIndex]
            var head = 0
            var indices: [Int] = []
            var minCol = Int.max
            var maxCol = 0
            var minRow = Int.max
            var maxRow = 0
            visited[startIndex] = true

            while head < queue.count {
                let index = queue[head]
                head += 1
                indices.append(index)

                let col = index % cropSize
                let row = index / cropSize
                if col < minCol { minCol = col }
                if col > maxCol { maxCol = col }
                if row < minRow { minRow = row }
                if row > maxRow { maxRow = row }

                for offset in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nextCol = col + offset.0
                    let nextRow = row + offset.1
                    guard nextCol >= 0, nextCol < cropSize, nextRow >= 0, nextRow < cropSize else {
                        continue
                    }
                    let nextIndex = nextRow * cropSize + nextCol
                    if mask[nextIndex], !visited[nextIndex] {
                        visited[nextIndex] = true
                        queue.append(nextIndex)
                    }
                }
            }

            let centerCol = CGFloat(minCol + maxCol) / 2
            let centerRow = CGFloat(minRow + maxRow) / 2
            let dx = centerCol - CGFloat(targetCol)
            let dy = centerRow - CGFloat(targetRow)
            components.append(MaskComponent(
                indices: indices,
                minCol: minCol,
                maxCol: maxCol,
                minRow: minRow,
                maxRow: maxRow,
                distanceSquared: dx * dx + dy * dy
            ))
        }

        guard !components.isEmpty else {
            return (nil, "mask_failed_no_white_pixels")
        }

        let substantial = components.filter { $0.count >= 3 }
        let usable = substantial.isEmpty ? components : substantial
        guard let selected = usable.min(by: {
            if $0.distanceSquared == $1.distanceSquared {
                return $0.count > $1.count
            }
            return $0.distanceSquared < $1.distanceSquared
        }) else {
            return (nil, "mask_failed_no_white_pixels")
        }

        guard sqrt(selected.distanceSquared) <= maxCenterDriftPx else {
            return (nil, "mask_failed_component_drift_fallback_candidate")
        }

        return (selected, "")
    }

    // MARK: - Dynamic Impact Detection

    private func detectImpact(
        observations: [ShotBallObservation],
        fallbackImpactIndex: Int
    ) -> ImpactDetectionResult {
        dbg("PostImpactBallTracker dynamic impact detection")
        dbg("  Fallback impact frame: \(fallbackImpactIndex)")

        let windowSize = max(3, cfg.impactDetection.stableWindowCount)
        let cutoff = min(windowSize, fallbackImpactIndex)
        let stableObs = observations
            .filter { $0.frameIndex < cutoff && $0.centerX != nil }
            .sorted { $0.frameIndex < $1.frameIndex }

        dbg("  Stable window: frames 0..<\(cutoff), found \(stableObs.count) tracked")

        guard stableObs.count >= 3 else {
            dbg("  Insufficient stable frames (\(stableObs.count)) - fallback")
            return fallbackImpact(
                fallbackImpactIndex,
                center: nil,
                threshold: cfg.impactDetection.movementThresholdNorm,
                jitter: 0,
                reason: "fallback_insufficient_stable_frames(\(stableObs.count))"
            )
        }

        let centersX = stableObs.compactMap { $0.centerX }.sorted()
        let centersY = stableObs.compactMap { $0.centerY }.sorted()
        let medianX = centersX[centersX.count / 2]
        let medianY = centersY[centersY.count / 2]
        let initialCenter = CGPoint(x: medianX, y: medianY)

        let diameters = stableObs.compactMap { $0.finalDiameter ?? $0.diameter }.sorted()
        let medianDiameter = diameters.isEmpty ? 0.030 : diameters[diameters.count / 2]

        let jitters = stableObs.compactMap { observation -> CGFloat? in
            guard let cx = observation.centerX, let cy = observation.centerY else { return nil }
            return hypot(cx - medianX, cy - medianY)
        }.sorted()
        let jitter = jitters.isEmpty ? 0 : jitters[jitters.count / 2]
        let threshold = max(cfg.impactDetection.movementThresholdNorm, medianDiameter * 0.20)

        dbg(String(format: "  Initial center: x=%.4f y=%.4f", medianX, medianY))
        dbg(String(format: "  Initial jitter: %.4f", jitter))
        dbg(String(format: "  Median diameter: %.4f", medianDiameter))
        dbg(String(format: "  Movement threshold: %.4f (config=%.4f)",
                     threshold, cfg.impactDetection.movementThresholdNorm))

        let scanStartFrame = stableObs.last.map { $0.frameIndex + 1 } ?? cutoff
        // Python: scan ALL frames from scan_start, including misses.
        // First miss = bad_detection_minus_one (Python fires immediately and breaks).
        let allScanFrames = observations
            .filter { $0.frameIndex >= scanStartFrame }
            .sorted { $0.frameIndex < $1.frameIndex }

        var consecutiveCount = 0
        var firstMovingFrame: Int?
        var lastFrameIndex = scanStartFrame - 2

        for observation in allScanFrames {
            guard let cx = observation.centerX, let cy = observation.centerY else {
                // Python detect_impact_frame lines 304-309:
                // if not chosen: event_frame = idx; event_reason = "bad_detection_minus_one"; break
                let detectedFrame = max(0, observation.frameIndex - 1)
                dbg(String(format: "  Detected impact: bad_detection at frame %d -> minus_one -> frame %d",
                             observation.frameIndex, detectedFrame))
                return ImpactDetectionResult(
                    detectedImpactFrameIndex: detectedFrame,
                    fallbackImpactFrameIndex: fallbackImpactIndex,
                    impactDetectionReason: "bad_detection_minus_one",
                    initialBallCenter: initialCenter,
                    movementThresholdNorm: threshold,
                    initialJitter: jitter
                )
            }

            let displacement = hypot(cx - medianX, cy - medianY)
            let isConsecutive = observation.frameIndex == lastFrameIndex + 1

            if displacement > threshold {
                if consecutiveCount == 0 {
                    firstMovingFrame = observation.frameIndex
                    consecutiveCount = 1
                } else if isConsecutive {
                    consecutiveCount += 1
                } else {
                    firstMovingFrame = observation.frameIndex
                    consecutiveCount = 1
                }

                if consecutiveCount >= cfg.impactDetection.confirmFrames,
                   let firstMovingFrame {
                    let detectedFrame = max(0, firstMovingFrame - 1)
                    dbg(String(format: "  Detected impact: first_movement at frame %d -> minus_one -> frame %d (disp=%.4f, confirmed over %d frames)",
                                 firstMovingFrame, detectedFrame, displacement, consecutiveCount))
                    return ImpactDetectionResult(
                        detectedImpactFrameIndex: detectedFrame,
                        fallbackImpactFrameIndex: fallbackImpactIndex,
                        impactDetectionReason: "first_movement_minus_one",
                        initialBallCenter: initialCenter,
                        movementThresholdNorm: threshold,
                        initialJitter: jitter
                    )
                }
            } else {
                consecutiveCount = 0
                firstMovingFrame = nil
            }

            lastFrameIndex = observation.frameIndex
        }

        if let firstMovingFrame, cfg.impactDetection.confirmFrames <= 1 {
            return ImpactDetectionResult(
                detectedImpactFrameIndex: firstMovingFrame,
                fallbackImpactFrameIndex: fallbackImpactIndex,
                impactDetectionReason: "first_movement_unconfirmed",
                initialBallCenter: initialCenter,
                movementThresholdNorm: threshold,
                initialJitter: jitter
            )
        }

        dbg("  No confirmed movement - fallback to \(fallbackImpactIndex)")
        return ImpactDetectionResult(
            detectedImpactFrameIndex: fallbackImpactIndex,
            fallbackImpactFrameIndex: fallbackImpactIndex,
            impactDetectionReason: "fallback_no_movement_detected",
            initialBallCenter: initialCenter,
            movementThresholdNorm: threshold,
            initialJitter: jitter
        )
    }

    private func fallbackImpact(
        _ index: Int,
        center: CGPoint?,
        threshold: CGFloat,
        jitter: CGFloat,
        reason: String
    ) -> ImpactDetectionResult {
        ImpactDetectionResult(
            detectedImpactFrameIndex: index,
            fallbackImpactFrameIndex: index,
            impactDetectionReason: reason,
            initialBallCenter: center,
            movementThresholdNorm: threshold,
            initialJitter: jitter
        )
    }

    // MARK: - Helpers

    private func miss(_ frame: AnalyzedShotFrame, reason: String? = "no_candidate") -> ShotBallObservation {
        ShotBallObservation(
            frameIndex: frame.frameIndex,
            timestamp: frame.timestamp,
            relativeTime: frame.relativeTime,
            centerX: nil,
            centerY: nil,
            diameter: nil,
            confidence: 0,
            wasInterpolated: false,
            debugReason: reason,
            diameterDebugReason: nil,
            maskWhitePixelCount: 0
        )
    }

    private func firstRejectionReason(_ candidates: [Candidate]) -> String {
        candidates.first(where: { !$0.accepted })?.rejectionReason
            ?? (candidates.isEmpty ? "no_blobs" : "no_accepted_candidate")
    }

    private func makeScanConfig(pre: Bool) -> ScanConfig {
        if pre {
            return ScanConfig(
                brightnessThreshold: cfg.preBrightnessThreshold,
                maxChannelSpread: cfg.preMaxChannelSpread,
                minimumBrightSamples: cfg.preMinBrightSamples,
                minNormWidth: cfg.preMinNormWidth,
                maxNormWidth: cfg.preMaxNormWidth,
                minNormHeight: cfg.preMinNormHeight,
                maxNormHeight: cfg.preMaxNormHeight,
                minAspect: cfg.preMinAspect,
                maxAspect: cfg.preMaxAspect
            )
        }

        return ScanConfig(
            brightnessThreshold: cfg.postBrightnessThreshold,
            maxChannelSpread: cfg.postMaxChannelSpread,
            minimumBrightSamples: cfg.postMinBrightSamples,
            minNormWidth: cfg.postMinNormWidth,
            maxNormWidth: cfg.postMaxNormWidth,
            minNormHeight: cfg.postMinNormHeight,
            maxNormHeight: cfg.postMaxNormHeight,
            minAspect: cfg.postMinAspect,
            maxAspect: cfg.postMaxAspect
        )
    }

    private func logConfiguration() {
        // SWIFT/PYTHON PARITY CHECK
        // Expected Python result on SampleShot_001 / ShotExport_20260504_141936:
        //   tracked=23/41  impact=18  fallback=20  reason=first_movement_minus_one
        //   ball_speed=99.2 mph  HLA=7.9° R  VLA=22.2° (if model loaded)  carry=141 yd  total=147 yd
        dbg("SWIFT/PYTHON PARITY CHECK")
        dbg("  sample = SampleShot_001 / ShotExport_20260504_141936")
        dbg("  expected_python_tracked = 23/41")
        dbg("  expected_python_impact = 18 (first_movement_minus_one)")
        dbg("  expected_python_launch_frames = 19/21")
        dbg("  expected_python_termination = 25 (3 misses after launch)")

        dbg(String(format: "PostImpactBallTracker live config: sampleStride=%d preBrightnessThreshold=%d preMinBrightSamples=%d postBrightnessThreshold=%d postMinBrightSamples=%d preImpactSearchScale=%.2f impactSearchScale=%.2f",
                     cfg.sampleStride,
                     cfg.preBrightnessThreshold,
                     cfg.preMinBrightSamples,
                     cfg.postBrightnessThreshold,
                     cfg.postMinBrightSamples,
                     cfg.preImpactSearchScale,
                     cfg.impactSearchScale))
        dbg(String(format: "PostImpactBallTracker ROI config (Python-parity): postFwdScale=%.1f postBwdScale=%.1f postVertUntracked=%.1f postVertTracked=%.1f launchAngle=%.1f°",
                     cfg.postFwdScale, cfg.postBwdScale,
                     cfg.postVertScaleUntracked, cfg.postVertScaleTracked,
                     cfg.launchAngleDegrees))
        dbg(String(format: "PostImpactBallTracker mask config: postMinNormWidth=%.4f maskPercentile=%d maskPercentileMinBright=%d maskBgDelta=%d localMaskWindowScale=%.2f smoothingWindow=%d",
                     cfg.postMinNormWidth,
                     cfg.diameterRefinement.maskPercentile,
                     cfg.diameterRefinement.maskPercentileMinBright,
                     cfg.diameterRefinement.maskBgDelta,
                     cfg.diameterRefinement.localMaskWindowScale,
                     cfg.diameterRefinement.smoothingWindowSize))
        dbg("PostImpactBallTracker analysis mode: DarkenedHighContrast (gamma=0.909 matches Python)")
    }

    private func pixelBytes(from image: UIImage) -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width
        let height = cg.height
        guard width > 0, height > 0 else { return nil }

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        return (bytes, width, height)
    }

    // Forward-biased post-impact ROI: narrow backward, wide forward, capped vertically.
    // Geometry matches Python's asymmetric oriented post-impact ROI (use_asymmetric_roi=True).
    // Uses tracked launchDir when available (Python: theta_post = atan2(-ldy, ldx)), else cfg angle.
    private func forwardBiasedPostROI(
        center: CGPoint, base: CGFloat, hasTracking: Bool,
        launchDir: (dx: CGFloat, dy: CGFloat)? = nil
    ) -> CGRect {
        let theta: CGFloat
        if let ld = launchDir {
            theta = atan2(-ld.dy, ld.dx)   // Python: atan2(-_ldy, _ldx)
        } else {
            theta = CGFloat(cfg.launchAngleDegrees) * .pi / 180.0
        }
        let fx = cos(theta)    // forward unit vector x (positive = rightward at 0°)
        let fy = -sin(theta)   // forward unit vector y (image +y = downward, so -sin)
        let px = -fy           // perpendicular unit x
        let py = fx            // perpendicular unit y

        let fwd  = cfg.postFwdScale * base
        let bwd  = cfg.postBwdScale * base
        let vert = (hasTracking ? cfg.postVertScaleTracked : cfg.postVertScaleUntracked) * base

        let cx = center.x, cy = center.y
        let cornersX: [CGFloat] = [
            cx - bwd*fx - vert*px,
            cx + fwd*fx - vert*px,
            cx + fwd*fx + vert*px,
            cx - bwd*fx + vert*px
        ]
        let cornersY: [CGFloat] = [
            cy - bwd*fy - vert*py,
            cy + fwd*fy - vert*py,
            cy + fwd*fy + vert*py,
            cy - bwd*fy + vert*py
        ]
        let x0 = max(0, cornersX.min()!), x1 = min(1, cornersX.max()!)
        let y0 = max(0, cornersY.min()!), y1 = min(1, cornersY.max()!)
        return CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }

    private func expanded(_ rect: CGRect, scale: CGFloat) -> CGRect {
        expandedAround(rect.center, rect: rect, scale: scale)
    }

    private func expandedAround(_ center: CGPoint, rect: CGRect, scale: CGFloat, verticalScaleCap: CGFloat? = nil) -> CGRect {
        let width = rect.width * scale
        let effectiveVertScale = verticalScaleCap.map { min(scale, $0) } ?? scale
        let height = rect.height * effectiveVertScale
        return CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
        .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private static func average(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / CGFloat(values.count)
    }

    private func median(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
