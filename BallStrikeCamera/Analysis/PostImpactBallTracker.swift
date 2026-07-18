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
        // Baseline-difference mask (post-impact only): a pixel belongs to the ball when it is
        // this much brighter than that pixel's own pre-impact median. Percentile thresholds
        // bleed into bright background (glare) and inflate the radius; against the per-pixel
        // baseline the moving ball is the only thing that stands out, so the component bbox
        // hugs the true disc. Lower than glareBaselineMinDelta (35) on purpose — the disc's
        // dimmer rim still clears ~20 while scan-level suppression wants a stronger signal.
        var maskBaselineDelta: Int = 22
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
        // Frame drops are routine (July 12: 92% of shots, gaps up to 4 periods between stored
        // frames) — between two STORED frames a driven ball can cross most of the frame, so a
        // ball-width-scaled forward extent silently strands the ball outside the ROI and the
        // club gets tracked instead (observed on the Simulate Shot sample). The forward search
        // always reaches the frame edge along the launch direction; 1.5 normalized covers any
        // center/direction inside the unit square before corner clamping.
        var postFwdMinNormExtent: CGFloat = 1.5
        // 4.0 untracked (was 2.5, was 1.5): the first post-impact frame has no track yet, and
        // with dropped frames a rising drive is several ball-widths above the seed's horizontal
        // band by the first stored post frame (12.5ms gap @ VLA 15° ≈ 5 ball-widths of climb).
        var postVertScaleUntracked: CGFloat = 4.0   // ball-widths lateral when no prior post-hit
        var postVertScaleTracked: CGFloat = 3.0     // ball-widths lateral once tracking started
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
        // At locked 1/8000-class shutters the white ball is decisively the brightest object
        // in the darkened analysis frames (measured 134-174 mean brightness across sessions,
        // vs 96-116 for club, grass glare, and noise specks). Nearest-to-previous alone chose
        // a dim px=18 speck beside the seed over the real ball three ball-widths downrange —
        // when any candidate reaches this tier, only tier members compete on distance.
        var brightBallTierMinBrightness: Int = 125
        // The tier is also RELATIVE: only candidates within this many brightness levels of
        // the frame's brightest accepted candidate compete on distance. A flat 125 floor let
        // a br=131 clubface into the tier one frame after impact, where nearest-to-seed beat
        // the br=159 ball — the ball IS the brightest ball-sized object in the frame, so
        // anything decisively dimmer than the best candidate is not the ball.
        var brightBallTierBandwidth: Int = 12
        // Per-shot candidate table: one line per analyzed frame listing every blob considered
        // (center, size, brightness, pixel count, accept/reject reason, chosen marker).
        // Bounded at ~41-101 lines/shot — cheap enough to leave on while tuning.
        var logCandidateDetail: Bool = true

        // Monotonicity constraints — the physics the tracker was ignoring:
        // Pre-impact the ball is STATIONARY at the locked position by definition; any chosen
        // blob further than this many locked-diameters from the lock center is the club, not
        // the ball. (Previously the anchor drifted to whatever was chosen last frame, so one
        // bad pick walked the track onto the club permanently.)
        // 0.5 diameters ≈ one ball radius: the live lock jitters by ~0.01 normalized, while
        // glare-session noise specks sat 0.086 away and passed the old 1.2 allowance — those
        // fake "movements" dragged the detected impact 11 frames early.
        var preAnchorMaxDriftDiameters: CGFloat = 0.5
        // Post-impact the ball only moves AWAY from the impact point (along launchDir once
        // locked). A chosen blob whose progress regresses more than this is the club swinging
        // back through — reject it and let prediction/rescue or a miss handle the frame.
        var monotonicBacktrackAllowanceNorm: CGFloat = 0.012
        // Once the tracked ball gets this close to any frame edge it is leaving the frame —
        // terminate the track. Without this, the frame after exit the tracker adopted whatever
        // static junk blob sat nearest the edge (observed: ball exits at x=0.059, next frame a
        // dim blob at (0.012,0.775) gets tracked motionless for the rest of the capture).
        var edgeTerminationMarginNorm: CGFloat = 0.06
        // Post-launch picks must sit on the launch line: reject when the perpendicular offset
        // exceeds this fraction of the pick's downrange progress (0.35 ≈ 19° off-line) or the
        // absolute floor. The club's follow-through crosses the flight corridor on a different
        // line — this is what stops it stealing the track between ball exit and termination.
        var pathResidualFractionOfProgress: CGFloat = 0.35
        var pathResidualFloorNorm: CGFloat = 0.05

        // Static-glare suppression: post-impact scans ignore pixels that were ALREADY bright
        // before impact. Sunlit turf floods the absolute brightness gates — the July 12 range
        // session measured ~10k qualifying pixels per frame against a ~50-150 px ball, and the
        // tracker chased turf glare on most of 100 shots. The per-pixel MEDIAN luma of the
        // pre-impact frames is a map of that static glare (median over ≥5 samples is robust to
        // the club or an early-launching ball sweeping through), and everything the strike set
        // in motion reads brighter than its own pre-impact baseline. Pre-impact and impact-frame
        // scans stay unsuppressed — the stationary ball IS baseline-bright by definition. A
        // frame whose suppressed scan finds nothing falls back to the unsuppressed scan, so
        // this can only ever remove clutter, never a previously-findable ball.
        var staticGlareSuppressionEnabled: Bool = true
        var glareBaselineMinDelta: Int = 35

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

        // Per-pixel static-glare map from the pre-impact frames (see Configuration docs).
        // Built once per shot; both tracking passes and the launch-chain scan share it.
        let glareBaseline = cfg.staticGlareSuppressionEnabled
            ? Self.buildGlareBaseline(pixelData: pixelData, frames: frames,
                                      beforeFrameIndex: fallbackImpactFrameIndex - 1)
            : nil
        if glareBaseline != nil {
            dbg("[PostImpactBallTracker] static-glare baseline built from pre-impact frames")
        }

        let firstPass = runTrackingPass(
            frames: frames,
            pixelData: pixelData,
            impactFrameIndex: fallbackImpactFrameIndex,
            lockedBallRect: lockedBallRect,
            preConfig: preConfig,
            postConfig: postConfig,
            glareBaseline: glareBaseline
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
                postConfig: postConfig,
                glareBaseline: glareBaseline
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

        // Always-on one-liner: the per-frame table above is opt-in, but "did tracking actually
        // follow the ball" must be visible in every session log — a discarded shot with
        // post=0 tracked frames explains itself.
        let impactIdx = result.detectedImpactFrameIndex
        let preObs  = result.observations.filter { $0.frameIndex < impactIdx }
        let postObs = result.observations.filter { $0.frameIndex > impactIdx }
        let preTracked  = preObs.filter { $0.centerX != nil }.count
        let postTracked = postObs.filter { $0.centerX != nil }.count
        let lockHeld = preObs.filter { $0.debugReason == "pre_lock_hold" }.count
        let impactHit = result.observations.first { $0.frameIndex == impactIdx }?.centerX != nil
        print("[TrackSummary] pre=\(preTracked)/\(preObs.count) (lockHold=\(lockHeld)) impactFrame=\(impactIdx) impactTracked=\(impactHit) post=\(postTracked)/\(postObs.count) reason=\(result.impactDetectionReason)")

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
        postConfig: ScanConfig,
        glareBaseline: [UInt8]? = nil
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
        // Configured launch direction as a unit vector (screen y-down): righty 180° → (-1, 0).
        let launchTheta = cfg.launchAngleDegrees * .pi / 180
        let launchU = (dx: cos(launchTheta), dy: -sin(launchTheta))
        // Set when a pre-impact frame shows a ball-sized candidate displaced FORWARD beyond the
        // drift allowance — the ball has left early (detected impact is late). From then on
        // lock-holds are forbidden: holding the anchor after departure feeds stationary points
        // to movement-based impact detection and masks the launch entirely (observed: 6
        // straight holds while the ball was mid-flight, impact detected 6 frames late).
        var preBallDeparted = false
        // Ballistic launch chain (see findLaunchChain) — frameIndex → pinned candidate.
        var launchChain: [Int: Candidate] = [:]
        var launchChainTried = false
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
                    expectedDiameter: lockedDiameter,
                    frameIndex: idx,
                    rescueMayReplacePick: true
                )
                var chosen = chosenRaw
                var driftReason: String? = nil
                if let c = chosen {
                    let drift = hypot(c.center.x - anchor.x, c.center.y - anchor.y)
                    let maxDrift = lockedDiameter * cfg.preAnchorMaxDriftDiameters
                    if drift > maxDrift {
                        // Ball-sized candidate displaced FORWARD past the allowance = the ball
                        // is launching during nominally-pre frames (detected impact is late).
                        // Brightness gate: dim static glare blobs also sit forward of the lock
                        // (observed br=105 at 1 ball-width forward killing an entire pre-track);
                        // the launching ball reads distinctly bright (observed 121-168).
                        let fwd = (c.center.x - anchor.x) * launchU.dx + (c.center.y - anchor.y) * launchU.dy
                        if fwd > maxDrift, c.meanBrightness >= 120 {
                            preBallDeparted = true
                            driftReason = String(format: "pre_ball_departed(fwd=%.3f br=%d)", fwd, c.meanBrightness)
                            // KEEP the candidate: this IS the ball, one or two frames into its
                            // flight. Nil-ing it (old behavior) threw away up to half of the
                            // only airborne observations a driver produces — at 100+ mph the
                            // ball leaves the frame ~2 frames after contact — and left impact
                            // detection to infer the launch from a missing frame instead of a
                            // moving center.
                        } else {
                            driftReason = String(format: "pre_drift_reject(%.3f>%.3f)", drift, maxDrift)
                            chosen = nil
                        }
                    }
                }
                // Glare-proof launch detection: when the normal scan lost the ball (merged with
                // glare / drift-rejected), rescan a forward launch corridor WITH static-glare
                // suppression. Pre-impact everything is static by definition — so a ball-sized
                // moving-bright blob displaced forward of the lock is the ball LAUNCHING, and
                // this frame is really post-impact (detected impact was late). Without this the
                // July 12 failure repeats: LOCK-HOLD pins the pre-track to the anchor, impact
                // detection sees zero movement, and by the fallback impact frame the ball has
                // already left the frame entirely. Among eligible blobs prefer the FARTHEST
                // forward — the ball outruns the clubhead from the first frame after contact.
                if chosen == nil, let baseline = glareBaseline {
                    let unit = max(lockedBallRect.width, 0.02)
                    let p2 = CGPoint(x: anchor.x + launchU.dx * 16 * unit,
                                     y: anchor.y + launchU.dy * 16 * unit)
                    let lat = 4 * unit
                    let corridor = CGRect(x: min(anchor.x, p2.x) - lat, y: min(anchor.y, p2.y) - lat,
                                          width: abs(p2.x - anchor.x) + 2 * lat,
                                          height: abs(p2.y - anchor.y) + 2 * lat)
                        .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                    let (dCands, _) = findCandidates(pd, roi: corridor, config: preConfig,
                                                     preferredCenter: anchor,
                                                     expectedDiameter: lockedDiameter,
                                                     frameIndex: idx,
                                                     glareBaseline: baseline)
                    let departed = dCands
                        .filter { c in
                            guard c.accepted else { return false }
                            // The launching ball is decisively BRIGHT (measured 121-168
                            // across sessions; junk and suppressed glare remnants sit
                            // 97-115). Without this gate, a dim blob at the far end of the
                            // corridor read as "the ball left" on frame 0 of a glare-flooded
                            // capture and hijacked the entire pre-track — which then poisoned
                            // movement-based impact detection. Same 120 bar as the
                            // drift-keep departure path above.
                            guard c.meanBrightness >= 120 else { return false }
                            let ratio = c.diameter / max(lockedDiameter, 1e-6)
                            guard ratio >= 0.35 && ratio <= 1.9 else { return false }
                            let fwd = (c.center.x - anchor.x) * launchU.dx + (c.center.y - anchor.y) * launchU.dy
                            return fwd >= lockedDiameter * 1.0
                        }
                        .max { a, b in
                            let fa = (a.center.x - anchor.x) * launchU.dx + (a.center.y - anchor.y) * launchU.dy
                            let fb = (b.center.x - anchor.x) * launchU.dx + (b.center.y - anchor.y) * launchU.dy
                            return fa < fb
                        }
                    if let c = departed {
                        let fwd = (c.center.x - anchor.x) * launchU.dx + (c.center.y - anchor.y) * launchU.dy
                        preBallDeparted = true
                        chosen = c
                        driftReason = nil
                        if cfg.logCandidateDetail {
                            candidateLogLines.append(String(
                                format: "[TrackDebug] f=%02d pre BALL DEPARTED (glare-suppressed) — moving blob fwd=%.3f d=%.4f br=%d",
                                idx, fwd, c.diameter, c.meanBrightness))
                        }
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
                } else if !preBallDeparted, candidates.contains(where: { $0.rect.intersects(lockedBallRect) }) {
                    // Scanner failed, but a bright mass overlaps the lock — the ball is merged
                    // with glare, not gone. Pre-impact the ball hasn't moved BY DEFINITION (the
                    // live pipeline locked it stationary and the trigger hasn't fired yet), so
                    // hold the locked position rather than dropping the frame. This keeps the
                    // pre-track and expected diameter sane for impact detection and metrics.
                    if cfg.logCandidateDetail {
                        candidateLogLines.append(String(
                            format: "[TrackDebug] f=%02d pre LOCK-HOLD — ball merged with glare, holding locked center (%.3f,%.3f d=%.4f)",
                            idx, anchor.x, anchor.y, lockedDiameter))
                    }
                    observations.append(ShotBallObservation(
                        frameIndex: idx,
                        timestamp: frame.timestamp,
                        relativeTime: frame.relativeTime,
                        centerX: anchor.x,
                        centerY: anchor.y,
                        diameter: lockedDiameter,
                        candidateDiameter: lockedDiameter,
                        finalDiameter: lockedDiameter,
                        confidence: 0.25,
                        wasInterpolated: true,
                        debugReason: "pre_lock_hold",
                        diameterDebugReason: "locked_rect",
                        bboxHeightNorm: lockedBallRect.height
                    ))
                    lastPreCenter = anchor
                    postImpactSeedCenter = anchor
                    preFinalDiameters.append(lockedDiameter)
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
                    expectedDiameter: lockedDiameter,
                    frameIndex: idx,
                    rescueMayReplacePick: true
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
                        var ratio = c.diameter / median
                        // The raw candidate bbox is stride-sampled (2px quanta) and reads
                        // ~25% fat on a perfectly clean ball, while the pre median it is
                        // compared against is mask-REFINED — that mismatch rejected a real
                        // un-merged impact ball at ratio 1.26 (Simulate Shot sample, f17).
                        // Refine the candidate the same way before declaring it merged.
                        if median > 1e-6, ratio > cfg.impactFrameMaxDiameterGrowthRatio,
                           cfg.diameterRefinement.enabled,
                           let refined = maskRefineDiameter(pd, center: c.center,
                                                            candidateDiameter: c.diameter,
                                                            config: cfg.diameterRefinement).diameter {
                            ratio = refined / median
                        }
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
                    // The locked rect is the most trusted size in the pipeline (20 stable live
                    // frames); a pre median far outside it means the pre track refined noise
                    // specks, not the ball (observed: expD=0.0083 vs lock 0.082, which made
                    // size-consistency PREFER specks and exclude the real ball post-impact).
                    let lockedDiameter = (lockedBallRect.width + lockedBallRect.height) / 2
                    if let d = expectedDiameter, d < lockedDiameter * 0.5 || d > lockedDiameter * 1.5 {
                        if cfg.logCandidateDetail {
                            candidateLogLines.append(String(
                                format: "[TrackDebug] f=%02d expectedDiameter %.4f implausible vs locked %.4f — using locked",
                                idx, d, lockedDiameter))
                        }
                        expectedDiameter = lockedDiameter
                    }
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
                    expectedDiameter: postExpectedDiameter,
                    frameIndex: idx,
                    glareBaseline: glareBaseline,
                    requireBrightTier: !ballLaunched
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

                // Ballistic launch chain: per-frame selection can't beat glare remnants sitting
                // next to the seed when the ball is already several ball-widths downrange one
                // frame after impact. Search the launch window ONCE for the best multi-frame,
                // constant-velocity, forward-moving chain of ball-sized blobs and pin the
                // tracker to it. Frames before the chain starts are forced to misses so a junk
                // pick can't lock a bogus launch direction first.
                if !launchChainTried, !ballLaunched {
                    launchChainTried = true
                    launchChain = findLaunchChain(
                        frames: frames,
                        pixelData: pixelData,
                        firstPostIndex: idx,
                        seedCenter: postImpactSeedCenter,
                        launchU: launchU,
                        lockedBallRect: lockedBallRect,
                        expectedDiameter: postExpectedDiameter,
                        config: postConfig,
                        glareBaseline: glareBaseline
                    )
                }
                if let chainStart = launchChain.keys.min() {
                    if let pinned = launchChain[idx] {
                        chosen = pinned
                    } else if idx < chainStart {
                        chosen = nil
                    }
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

                // Path consistency: a launched ball travels a near-straight image line from the
                // impact point; the clubhead's follow-through crosses the same region on a
                // DIFFERENT line. A pick whose perpendicular offset from the locked launch line
                // is out of proportion to how far downrange it claims to be is the club, not
                // the ball. Proportional (not absolute) so a direction locked from a short
                // first step doesn't strangle a legitimately rising shot.
                if let c = chosen, ballLaunched, let ld = launchDir {
                    let dx = c.center.x - initCenter.x
                    let dy = c.center.y - initCenter.y
                    let progress = dx * ld.dx + dy * ld.dy
                    let perp = abs(dx * ld.dy - dy * ld.dx)
                    if perp > max(cfg.pathResidualFloorNorm, cfg.pathResidualFractionOfProgress * max(progress, 0)) {
                        if cfg.logCandidateDetail {
                            candidateLogLines.append(String(format: "[TrackDebug] f=%02d post PATH REJECT (%.3f,%.3f) perp=%.4f progress=%.4f — off the launch line",
                                         idx, c.center.x, c.center.y, perp, progress))
                        }
                        chosen = nil
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
                    observation = makeHit(frame, c, pd: pd, glareBaseline: glareBaseline)
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

                    // Predictive exit: with a measured velocity and the NEXT frame's real
                    // timestamp we KNOW where the ball will be — if that's outside the frame,
                    // the track ends now. Waiting for 3 misses left a multi-frame window in
                    // which the club's follow-through (bright, moving the same general
                    // direction) could re-steal the track after the ball was already gone.
                    if !ballTerminated, recentPostPoints.count >= 2, i + 1 < frames.count {
                        let p1 = recentPostPoints[recentPostPoints.count - 2]
                        let p2 = recentPostPoints[recentPostPoints.count - 1]
                        let dt = p2.t - p1.t
                        if dt > 1e-6 {
                            let nextDt = frames[i + 1].relativeTime - frame.relativeTime
                            let px = p2.x + (p2.x - p1.x) / CGFloat(dt) * CGFloat(nextDt)
                            let py = p2.y + (p2.y - p1.y) / CGFloat(dt) * CGFloat(nextDt)
                            if px < em || px > 1 - em || py < em || py > 1 - em {
                                ballTerminated = true
                                if cfg.logCandidateDetail {
                                    candidateLogLines.append(String(format: "[TrackDebug] f=%02d predictive exit — next-frame position (%.3f,%.3f) is off-frame, track terminated", idx, px, py))
                                }
                            }
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

    // MARK: - Launch Chain Search
    //
    // What uniquely identifies the ball right after impact is not brightness or proximity —
    // it's MULTI-FRAME CONSISTENCY: a ball-sized blob advancing along the launch direction at
    // near-constant image velocity. (Observed failure: the real ball at br=112 lost every
    // frame to dim px=18 specks beside the seed because nearest-to-previous ruled.) This runs
    // once when post-impact tracking starts: scan a wide launch corridor in the first few
    // post frames, enumerate velocity-consistent forward chains, keep the best.
    private func findLaunchChain(
        frames: [AnalyzedShotFrame],
        pixelData: [(bytes: [UInt8], width: Int, height: Int)?],
        firstPostIndex: Int,
        seedCenter: CGPoint,
        launchU: (dx: CGFloat, dy: CGFloat),
        lockedBallRect: CGRect,
        expectedDiameter: CGFloat,
        config: ScanConfig,
        glareBaseline: [UInt8]? = nil
    ) -> [Int: Candidate] {
        let windowLen = 8
        let w = max(lockedBallRect.width, 0.02)
        // Corridor: 1.5 ball-widths behind the seed, forward all the way to the frame edge
        // (dropped frames put the first airborne observation most of a frame downrange),
        // ±4 lateral.
        let fwdExtent = max(16 * w, 1.5)
        let p1 = CGPoint(x: seedCenter.x - launchU.dx * 1.5 * w, y: seedCenter.y - launchU.dy * 1.5 * w)
        let p2 = CGPoint(x: seedCenter.x + launchU.dx * fwdExtent, y: seedCenter.y + launchU.dy * fwdExtent)
        let lat = 4 * w
        let roi = CGRect(x: min(p1.x, p2.x) - lat, y: min(p1.y, p2.y) - lat,
                         width: abs(p2.x - p1.x) + 2 * lat, height: abs(p2.y - p1.y) + 2 * lat)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard roi.width > 0, roi.height > 0 else { return [:] }

        var perFrame: [(frameIndex: Int, cands: [Candidate])] = []
        for (i, frame) in frames.enumerated() {
            let idx = frame.frameIndex
            guard idx >= firstPostIndex, idx < firstPostIndex + windowLen,
                  i < pixelData.count, let pd = pixelData[i] else { continue }
            let (cands, _) = findCandidates(pd, roi: roi, config: config,
                                            preferredCenter: seedCenter,
                                            expectedDiameter: expectedDiameter,
                                            frameIndex: idx,
                                            glareBaseline: glareBaseline)
            let eligible = Array(
                cands.filter { c in
                    guard c.accepted else { return false }
                    let ratio = c.diameter / max(expectedDiameter, 1e-6)
                    return ratio >= 0.35 && ratio <= 2.2
                }
                .sorted { $0.meanBrightness > $1.meanBrightness }
                .prefix(8)
            )
            if !eligible.isEmpty { perFrame.append((idx, eligible)) }
        }
        // Always explain the chain's inputs — when it comes up empty on-device the per-frame
        // eligible lists are the only way to see WHICH gate starved it.
        if cfg.logCandidateDetail {
            for (fi, cands) in perFrame {
                let desc = cands.map { String(format: "(%.3f,%.3f br=%d d=%.4f px=%d)",
                                              $0.center.x, $0.center.y, $0.meanBrightness,
                                              $0.diameter, $0.brightPixelCount) }
                    .joined(separator: " ")
                candidateLogLines.append("[TrackDebug] CHAIN f=\(String(format: "%02d", fi)) eligible: \(desc)")
            }
        }
        guard perFrame.count >= 2 else { return [:] }

        struct Link { let frameIdx: Int; let cand: Candidate }
        var best: (score: CGFloat, chain: [Link])? = nil
        var expansions = 0

        // Real capture time per stored frame index. Frame drops are routine — the July 12
        // session stored consecutive indices whose timestamps are 2-4 capture periods apart —
        // so every velocity here is normalized by elapsed 240fps PERIODS, never index gaps.
        // (Index-gap division read a normal drive as 2-4× ball speed and the fwd<=0.30 gate
        // rejected every real chain, which is how the club stole the Simulate Shot track.)
        let timeByIdx = Dictionary(frames.map { ($0.frameIndex, $0.relativeTime) },
                                   uniquingKeysWith: { a, _ in a })
        func elapsedPeriods(_ aIdx: Int, _ bIdx: Int) -> CGFloat {
            if let ta = timeByIdx[aIdx], let tb = timeByIdx[bIdx], tb > ta {
                return max(1, CGFloat((tb - ta) * 240.0))
            }
            return max(1, CGFloat(bIdx - aIdx))
        }

        // Per-period velocity between two links (1-frame gap or one skipped frame). Must move
        // forward at a plausible ball speed with limited lateral drift.
        func velocity(_ a: Link, _ b: Link) -> CGPoint? {
            let g = CGFloat(b.frameIdx - a.frameIdx)
            guard g >= 1, g <= 2 else { return nil }
            let periods = elapsedPeriods(a.frameIdx, b.frameIdx)
            let vx = (b.cand.center.x - a.cand.center.x) / periods
            let vy = (b.cand.center.y - a.cand.center.y) / periods
            let fwd = vx * launchU.dx + vy * launchU.dy
            let latV = -vx * launchU.dy + vy * launchU.dx
            guard fwd >= 0.015, fwd <= 0.30, abs(latV) <= max(0.02, 0.5 * fwd) else { return nil }
            return CGPoint(x: vx, y: vy)
        }

        func finalize(_ chain: [Link]) {
            guard chain.count >= 2, let first = chain.first, let last = chain.last else { return }
            let fwdProgress = (last.cand.center.x - first.cand.center.x) * launchU.dx
                + (last.cand.center.y - first.cand.center.y) * launchU.dy
            // A 2-point "chain" is only trusted when it covers real distance AND both points
            // look like the ball (observed: a dim px-blob chained to the real ball across a
            // skipped frame produced a bogus 150mph 2-pointer); 3+ points carry their own
            // consistency evidence.
            guard chain.count >= 3
                || (fwdProgress >= 0.08 && chain.allSatisfy { $0.cand.meanBrightness >= 115 })
            else { return }
            let n = CGFloat(chain.count)
            let avgBr = chain.reduce(CGFloat(0)) { $0 + CGFloat($1.cand.meanBrightness) } / n
            let frameSpan = elapsedPeriods(first.frameIdx, last.frameIdx)
            let avgVel = frameSpan > 0 ? fwdProgress / frameSpan : 0
            // Weighting matters: pure length let a 7-point slow dim club chain (v≈0.025,
            // br≈117) beat the real 5-point ball (v≈0.068, br≈145). Velocity and brightness
            // are what distinguish a struck ball from anything else that moves.
            let score = n * 60 + fwdProgress * 250 + max(0, avgBr - 100) * 6 + avgVel * 800
            if best == nil || score > best!.score { best = (score, chain) }
        }

        func extend(_ chain: [Link], lastVel: CGPoint?) {
            guard expansions < 30_000 else { finalize(chain); return }
            expansions += 1
            guard let lastLink = chain.last else { return }
            var extended = false
            for (fIdx, cands) in perFrame where fIdx > lastLink.frameIdx && fIdx <= lastLink.frameIdx + 2 {
                for cand in cands {
                    let link = Link(frameIdx: fIdx, cand: cand)
                    guard let vel = velocity(lastLink, link) else { continue }
                    if let lv = lastVel {
                        // Perspective decelerates the ball in image space, so allow generous
                        // change frame-to-frame — but not teleports.
                        let dv = hypot(vel.x - lv.x, vel.y - lv.y)
                        guard dv <= max(0.025, 0.55 * hypot(lv.x, lv.y) + 0.01) else { continue }
                    }
                    extended = true
                    extend(chain + [link], lastVel: vel)
                }
            }
            if !extended { finalize(chain) }
        }

        // Chains may start in any of the first 3 candidate-bearing window frames (the exact
        // impact frame is itself uncertain). The start must not be behind the seed.
        for (fIdx, cands) in perFrame.prefix(3) {
            for cand in cands {
                let fwd0 = (cand.center.x - seedCenter.x) * launchU.dx
                    + (cand.center.y - seedCenter.y) * launchU.dy
                guard fwd0 >= -w else { continue }
                extend([Link(frameIdx: fIdx, cand: cand)], lastVel: nil)
            }
        }

        guard let found = best else {
            if cfg.logCandidateDetail {
                candidateLogLines.append("[TrackDebug] LAUNCH CHAIN none in f=\(firstPostIndex)..\(firstPostIndex + windowLen - 1)")
            }
            return [:]
        }
        if cfg.logCandidateDetail {
            let pts = found.chain.map {
                String(format: "f%02d(%.3f,%.3f br=%d)", $0.frameIdx, $0.cand.center.x, $0.cand.center.y, $0.cand.meanBrightness)
            }
            candidateLogLines.append(String(format: "[TrackDebug] LAUNCH CHAIN %d pts score=%.0f: %@",
                                            found.chain.count, found.score, pts.joined(separator: " -> ")))
        }
        var map: [Int: Candidate] = [:]
        for link in found.chain { map[link.frameIdx] = link.cand }
        return map
    }

    // MARK: - Connected-Components Candidate Scanner

    private func findCandidates(
        _ pd: (bytes: [UInt8], width: Int, height: Int),
        roi: CGRect,
        config: ScanConfig,
        preferredCenter: CGPoint,
        expectedDiameter: CGFloat? = nil,
        frameIndex: Int = -1,
        rescueMayReplacePick: Bool = false,
        glareBaseline: [UInt8]? = nil,
        requireBrightTier: Bool = false
    ) -> ([Candidate], Candidate?) {
        let (bytes, width, height) = pd
        let step = max(1, cfg.sampleStride)
        // Only trust a baseline whose geometry matches this frame's buffer.
        let baseline: [UInt8]? = (glareBaseline?.count == width * height) ? glareBaseline : nil

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
                // Lime range ball: fails the spread cap (saturated yellow-green) but its
                // BLUE channel collapses — b/g ≈ 0.18 vs turf's 0.60 (measured on
                // shot_20260712_081756_933). Frames here are darkened, so the brightness
                // floor is relative to the configured threshold, not an absolute.
                let isLime = g - b >= 110 && r < g && r * 2 > g
                var qualifies = (brightness >= config.brightnessThreshold
                    && spread <= config.maxChannelSpread)
                    || (isLime && brightness >= config.brightnessThreshold - 25)
                // Static-glare suppression: a pixel must be brighter than its own pre-impact
                // baseline to count — turf glare is bright in BOTH, the moving ball only now.
                if qualifies, let base = baseline {
                    qualifies = brightness - Int(base[py * width + px]) >= cfg.glareBaselineMinDelta
                }
                bright[row * cols + col] = qualifies
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

        // Never go blind from suppression alone: if the baseline filtered out every last
        // pixel (ball dim, or still overlapping its own pre-impact position on a slow shot),
        // rescan this frame the old unsuppressed way — worst case is the old behavior.
        if blobs.isEmpty, baseline != nil {
            dbg("[PostImpactBallTracker] f=\(frameIndex) glare-suppressed scan empty — falling back to unsuppressed")
            return findCandidates(pd, roi: roi, config: config, preferredCenter: preferredCenter,
                                  expectedDiameter: expectedDiameter, frameIndex: frameIndex,
                                  rescueMayReplacePick: rescueMayReplacePick, glareBaseline: nil)
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

        // Bright-tier preference: see brightBallTierMinBrightness/Bandwidth. Absolute floor
        // AND relative band — the ball outshines everything else that moves, so only
        // candidates within the band of the brightest one may compete on distance. Falls
        // back to the whole pool when nothing reaches the tier (dim ball / overcast) so
        // tracking never goes blind.
        let maxPoolBrightness = pool.map(\.meanBrightness).max() ?? 0
        let brightTier = pool.filter {
            $0.meanBrightness >= cfg.brightBallTierMinBrightness
                && $0.meanBrightness >= maxPoolBrightness - cfg.brightBallTierBandwidth
        }
        // Pre-launch the ball is ALWAYS decisively bright (freshly struck, full face to the
        // sun/exposure lock) — a frame whose pool is all-dim does not contain a findable
        // ball, and picking "the nearest dim blob" is how a junk pick locked a bogus launch
        // direction that then walled out the real ball. Callers set requireBrightTier for
        // pre-launch frames: no tier, no pick.
        if requireBrightTier, brightTier.isEmpty {
            return (candidates, nil)
        }
        let selectionPool = brightTier.isEmpty ? pool : brightTier
        var chosen = selectionPool.min {
            hypot($0.center.x - preferredCenter.x, $0.center.y - preferredCenter.y)
                < hypot($1.center.x - preferredCenter.x, $1.center.y - preferredCenter.y)
        }

        // An OVERSIZED blob sits right where the ball should be — in glare the ball and the
        // bright patch around it merge into one blob the size gates reject (observed live:
        // ball locked at d=0.064 inside a w=0.267 blob). The live-view detector survives this
        // because it demands bright AND color-neutral pixels; re-scan the merged blob with
        // that stricter criterion to split the white ball back out of the glare.
        // When `rescueMayReplacePick` (pre-impact/impact, where the ball is stationary at the
        // lock by definition), the rescue can also OVERRIDE an accepted pick that is a stray
        // speck far from the expected spot while a merged blob covers that spot — a session
        // showed noise specks 0.086 from the lock winning every pre frame because they were
        // "accepted" while the actual ball sat rejected inside the glare blob. Post-impact the
        // override stays off: after launch, glare still covering the ball's OLD spot must not
        // beat the real ball that has moved on.
        var allCandidates = candidates
        let chosenDist = chosen.map { hypot($0.center.x - preferredCenter.x, $0.center.y - preferredCenter.y) }
        let mergedCoversExpectedSpot = candidates.contains { c in
            guard let r = c.rejectionReason,
                  r.hasPrefix("w_large") || r.hasPrefix("h_large") else { return false }
            return c.rect.contains(preferredCenter)
        }
        let pickIsSuspect = chosenDist.map { $0 > max(expectedDiameter ?? 0, 0.03) * 0.75 } ?? true
        let rescueTrigger = chosen == nil
            || (rescueMayReplacePick && mergedCoversExpectedSpot && pickIsSuspect)
        if rescueTrigger,
           let rescued = rescueMergedBlob(
               pd, candidates: candidates, config: config,
               preferredCenter: preferredCenter, expectedDiameter: expectedDiameter,
               frameIndex: frameIndex, glareBaseline: baseline
           ) {
            let rescuedDist = hypot(rescued.center.x - preferredCenter.x, rescued.center.y - preferredCenter.y)
            if chosenDist == nil || rescuedDist < chosenDist! {
                allCandidates.append(rescued)
                chosen = rescued
            }
        }

        return (allCandidates, chosen)
    }

    /// Splits a ball+glare merged blob by re-thresholding just that blob's bounding box at
    /// escalating brightness with the live detector's channel-spread cap (white, not colored).
    /// Returns the first sub-blob that passes the normal size gates, preferring size-consistent
    /// candidates nearest `preferredCenter`.
    private func rescueMergedBlob(
        _ pd: (bytes: [UInt8], width: Int, height: Int),
        candidates: [Candidate],
        config: ScanConfig,
        preferredCenter: CGPoint,
        expectedDiameter: CGFloat?,
        frameIndex: Int,
        glareBaseline: [UInt8]? = nil
    ) -> Candidate? {
        let reach = max(expectedDiameter ?? 0, 0.05)
        let mergedBlobs = candidates
            .filter { c in
                guard let r = c.rejectionReason,
                      r.hasPrefix("w_large") || r.hasPrefix("h_large") else { return false }
                return c.rect.insetBy(dx: -reach, dy: -reach).contains(preferredCenter)
            }
            .sorted {
                hypot($0.center.x - preferredCenter.x, $0.center.y - preferredCenter.y)
                    < hypot($1.center.x - preferredCenter.x, $1.center.y - preferredCenter.y)
            }
        guard !mergedBlobs.isEmpty else { return nil }

        let (bytes, width, height) = pd
        let spreadCap = min(config.maxChannelSpread, 72)   // live BallDetector's white criterion

        for blob in mergedBlobs.prefix(2) {
            let x0 = max(0, Int(blob.rect.minX * CGFloat(width)))
            let x1 = min(width - 1, Int(blob.rect.maxX * CGFloat(width)))
            let y0 = max(0, Int(blob.rect.minY * CGFloat(height)))
            let y1 = min(height - 1, Int(blob.rect.maxY * CGFloat(height)))
            guard x1 > x0, y1 > y0 else { continue }
            let cols = x1 - x0 + 1
            let rows = y1 - y0 + 1
            guard cols * rows <= 200_000 else { continue }   // runaway blob — not worth a full-res pass

            var thr = config.brightnessThreshold + 25
            while thr <= 235 {
                var bright = [Bool](repeating: false, count: cols * rows)
                var luma = [UInt8](repeating: 0, count: cols * rows)
                for row in 0..<rows {
                    let base = (y0 + row) * width * 4
                    for col in 0..<cols {
                        let i = base + (x0 + col) * 4
                        let r = Int(bytes[i]); let g = Int(bytes[i + 1]); let b = Int(bytes[i + 2])
                        let brightness = (r + g + b) / 3
                        let spread = max(r, max(g, b)) - min(r, min(g, b))
                        let idx = row * cols + col
                        var qualifies = brightness >= thr && spread <= spreadCap
                        // Same static-glare gate as the main scan — a merged blob being split
                        // here is usually ball+glare, and the glare half is baseline-bright.
                        if qualifies, let base = glareBaseline, base.count == width * height {
                            qualifies = brightness - Int(base[(y0 + row) * width + (x0 + col)]) >= cfg.glareBaselineMinDelta
                        }
                        bright[idx] = qualifies
                        luma[idx] = UInt8(brightness)
                    }
                }

                var visited = [Bool](repeating: false, count: cols * rows)
                var subCandidates: [Candidate] = []
                for startRow in 0..<rows {
                    for startCol in 0..<cols {
                        let startIndex = startRow * cols + startCol
                        guard bright[startIndex], !visited[startIndex] else { continue }
                        var sub = RawBlob(minX: Int.max, maxX: 0, minY: Int.max, maxY: 0,
                                          sumX: 0, sumY: 0, count: 0, sumBrightness: 0)
                        var queue = [startIndex]
                        var head = 0
                        visited[startIndex] = true
                        while head < queue.count {
                            let index = queue[head]
                            head += 1
                            let col = index % cols
                            let row = index / cols
                            let px = x0 + col
                            let py = y0 + row
                            sub.count += 1
                            sub.sumX += px
                            sub.sumY += py
                            sub.sumBrightness += Int(luma[index])
                            if px < sub.minX { sub.minX = px }
                            if px > sub.maxX { sub.maxX = px }
                            if py < sub.minY { sub.minY = py }
                            if py > sub.maxY { sub.maxY = py }
                            for offset in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                                let nc = col + offset.0
                                let nr = row + offset.1
                                guard nc >= 0, nc < cols, nr >= 0, nr < rows else { continue }
                                let ni = nr * cols + nc
                                if bright[ni], !visited[ni] {
                                    visited[ni] = true
                                    queue.append(ni)
                                }
                            }
                        }
                        let cand = evaluateBlob(sub, step: 1, width: width, height: height, config: config)
                        if cand.accepted { subCandidates.append(cand) }
                    }
                }

                if !subCandidates.isEmpty {
                    // The rescue exists to find the BALL, whose size is known — unlike the main
                    // scanner there is no fall-back to any-sized blob (observed: a px=6 speck
                    // "rescued" after the ball had already launched out of the glare).
                    let pool: [Candidate]
                    if let expected = expectedDiameter, expected > 1e-6 {
                        pool = subCandidates.filter {
                            let ratio = $0.diameter / expected
                            return ratio >= cfg.chosenDiameterRatioMin && ratio <= cfg.chosenDiameterRatioMax
                        }
                    } else {
                        pool = subCandidates
                    }
                    if let best = pool.min(by: {
                        hypot($0.center.x - preferredCenter.x, $0.center.y - preferredCenter.y)
                            < hypot($1.center.x - preferredCenter.x, $1.center.y - preferredCenter.y)
                    }) {
                        if cfg.logCandidateDetail {
                            candidateLogLines.append(String(
                                format: "[TrackDebug] f=%02d MERGED-BLOB RESCUE thr=%d spread<=%d split w=%.4f blob -> ball (%.3f,%.3f d=%.4f px=%d)",
                                frameIndex, thr, spreadCap, blob.rect.width,
                                best.center.x, best.center.y, best.diameter, best.brightPixelCount))
                        }
                        return best
                    }
                }
                thr += 20
            }
        }
        return nil
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
        pd: (bytes: [UInt8], width: Int, height: Int),
        glareBaseline: [UInt8]? = nil
    ) -> ShotBallObservation {
        let candidateDiameter = candidate.diameter
        let maskOutput = cfg.diameterRefinement.enabled
            ? maskRefineDiameter(
                pd,
                center: candidate.center,
                candidateDiameter: candidateDiameter,
                config: cfg.diameterRefinement,
                glareBaseline: glareBaseline
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
        config: DiameterRefinementConfig,
        glareBaseline: [UInt8]? = nil
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

        // Baseline-difference mask first (post-impact only — callers pass the baseline). The
        // in-flight ball is the one thing brighter than its own pixel's pre-impact median, so
        // the component bbox is a tight fit of the true disc regardless of background glare.
        // Any failure falls through to the percentile-brightness mask below.
        if let baseline = glareBaseline, baseline.count == width * height {
            var diffMask = [Bool](repeating: false, count: cropSize * cropSize)
            for py in y0...y1 {
                for px in x0...x1 {
                    let col = px - cropOriginX
                    let row = py - cropOriginY
                    guard col >= 0, col < cropSize, row >= 0, row < cropSize else { continue }
                    let pixelIndex = py * width * 4 + px * 4
                    let brightness = (Int(bytes[pixelIndex]) + Int(bytes[pixelIndex + 1]) + Int(bytes[pixelIndex + 2])) / 3
                    diffMask[row * cropSize + col] = brightness >= config.maskBrightnessThreshold
                        && brightness - Int(baseline[py * width + px]) >= config.maskBaselineDelta
                }
            }
            let diffSelection = mainMaskComponent(
                in: diffMask,
                cropSize: cropSize,
                targetCol: cx - cropOriginX,
                targetRow: cy - cropOriginY,
                maxCenterDriftPx: max(2, candidateDiameter * CGFloat(width) * 0.55)
            )
            if let component = diffSelection.component, component.count >= 3 {
                let bboxWidthPx = component.maxCol - component.minCol + 1
                let bboxHeightPx = component.maxRow - component.minRow + 1
                return MaskRefineOutput(
                    diameter: CGFloat(max(bboxWidthPx, bboxHeightPx)) / CGFloat(width),
                    heightNorm: CGFloat(bboxHeightPx) / CGFloat(height),
                    whitePixelCount: component.count,
                    reason: "mask_refined_baseline_diff_\(config.maskBaselineDelta)"
                )
            }
        }

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

    /// Per-pixel MEDIAN luma across up to 7 evenly-spaced pre-impact frames — the static-glare
    /// map (see Configuration.staticGlareSuppressionEnabled). Median over ≥5 samples is robust
    /// to the club or an early-launching ball sweeping through: a moving object holds any one
    /// pixel for at most 1-2 of the sampled frames. Returns nil when there aren't enough
    /// uniform pre-impact frames to trust (suppression then simply stays off for the shot).
    private static func buildGlareBaseline(
        pixelData: [(bytes: [UInt8], width: Int, height: Int)?],
        frames: [AnalyzedShotFrame],
        beforeFrameIndex: Int
    ) -> [UInt8]? {
        let preArrayIdx = frames.indices.filter { i in
            frames[i].frameIndex < beforeFrameIndex && i < pixelData.count && pixelData[i] != nil
        }
        guard preArrayIdx.count >= 3, let firstPD = pixelData[preArrayIdx[0]] else { return nil }
        let width = firstPD.width, height = firstPD.height
        guard width > 0, height > 0 else { return nil }

        let sampleCount = min(7, preArrayIdx.count)
        let chosen = (0..<sampleCount).map { preArrayIdx[$0 * (preArrayIdx.count - 1) / max(1, sampleCount - 1)] }

        var planes: [[UInt8]] = []
        for i in chosen {
            guard let pd = pixelData[i], pd.width == width, pd.height == height else { continue }
            var plane = [UInt8](repeating: 0, count: width * height)
            pd.bytes.withUnsafeBufferPointer { buf in
                for p in 0..<(width * height) {
                    let o = p * 4
                    plane[p] = UInt8((Int(buf[o]) + Int(buf[o + 1]) + Int(buf[o + 2])) / 3)
                }
            }
            planes.append(plane)
        }
        guard planes.count >= 3 else { return nil }

        var baseline = [UInt8](repeating: 0, count: width * height)
        var vals = [UInt8](repeating: 0, count: planes.count)
        for p in 0..<(width * height) {
            for (k, plane) in planes.enumerated() { vals[k] = plane[p] }
            vals.sort()
            baseline[p] = vals[vals.count / 2]
        }
        return baseline
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

        // Forward extent always reaches the frame edge (corner clamp below trims the excess) —
        // ball-width scaling alone loses the ball across dropped-frame gaps.
        let fwd  = max(cfg.postFwdScale * base, cfg.postFwdMinNormExtent)
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

// MARK: - ═══════════════ V2 Engine (label-trained, July 2026) ═══════════════
// Faithful Swift port of tools/experimental detector2/track_optimizer/metrics_kfold —
// the pipeline validated against 223 hand-labeled shots (ball 97.4%, club 77.8%) and
// the July 12 Garmin session. Runs on the ORIGINAL color frames (hue carries the
// signal), consumes real per-frame timestamps (frame drops are routine), and feeds
// learned heads whose outputs are clamped to what the pixels physically allow.
// Models: Resources/Models/tc_v2_models.json (retrain via tools/experimental + THURSDAY.md).

/// One per-frame ball sighting from V2's sequential tracker — the label-trained detector's
/// view of where the ball is, in normalized coordinates (diameter normalized by frame WIDTH,
/// matching the legacy convention).
struct V2FrameObservation {
    let frameIndex: Int
    let cxNorm: Double
    let cyNorm: Double
    let diaNorm: Double
    let confidence: Double
    /// true = airborne sighting (>= 1 lock radius from the rest position)
    let isFlight: Bool
}

/// One per-frame clubhead sighting from V2's GBT club scorer (approach window only).
struct V2ClubObservation {
    let frameIndex: Int
    let cxNorm: Double
    let cyNorm: Double
    let confidence: Double
}

struct V2Output {
    var ballSpeedMph: Double?
    var clubSpeedMph: Double?
    var vlaDegrees: Double?
    var confident: Bool
    var flightPointCount: Int
    var notes: [String]
    /// V2's own impact frame (ball-motion detected, launch-cone gated).
    var impactFrameIndex: Int = 0
    /// The full per-frame track — rest sightings pre-impact, flight sightings post. Present
    /// even when metrics are withheld: the track is useful to the review/3D pipeline
    /// regardless of whether a speed could be fit.
    var frameObservations: [V2FrameObservation] = []
    /// GBT-scored clubhead sightings across the approach window (impact-6 … impact+1).
    /// The EnsembleBFS club tracker is precise when it fires (4.2px median vs labels) but
    /// covered only 29% of labeled approach frames; these fill the coverage gap that was
    /// starving club path/speed fits.
    var clubObservations: [V2ClubObservation] = []
}

final class V2Engine {

    // MARK: Models

    private struct LinearHead: Decodable {
        let mu: [Double]; let sd: [Double]; let w: [Double]; let intercept: Double
        let clamp: [Double]?
        func predict(_ x: [Double]) -> Double {
            var z = intercept
            for i in 0..<min(w.count, x.count) { z += w[i] * (x[i] - mu[i]) / sd[i] }
            return z
        }
    }
    private struct BallScorerModel: Decodable { let w: [Double]; let b: Double; let threshold: Double }
    private struct ClubGBTModel: Decodable {
        let base: Double; let stumps: [[Double]]; let threshold: Double
        func prob(_ x: [Double]) -> Double {
            var f = base
            for s in stumps where s.count == 4 {
                let j = Int(s[0])
                f += (j < x.count && x[j] <= s[1]) ? s[2] : s[3]
            }
            return 1.0 / (1.0 + exp(-max(-30, min(30, f))))
        }
    }
    private struct Models: Decodable {
        let version: String
        let ball_scorer: BallScorerModel
        let club_gbt: ClubGBTModel
        let ball_head: LinearHead
        let vla_head: LinearHead
        let club_head: LinearHead?
    }

    private static let models: Models? = {
        guard let url = Bundle.main.url(forResource: "tc_v2_models", withExtension: "json", subdirectory: "Models"),
              let data = try? Data(contentsOf: url),
              let m = try? JSONDecoder().decode(Models.self, from: data) else {
            print("[V2] models missing — engine disabled")
            return nil
        }
        print("[V2] models loaded (\(m.version))")
        return m
    }()

    static var isAvailable: Bool { models != nil }

    // MARK: Per-frame planes

    struct Planes {
        let W: Int, H: Int
        var dh: [UInt8]      // hue-distance channel (the winning separation)
        var v: [UInt8]       // HSV value 0-255
        var s: [UInt8]       // HSV saturation 0-255
        var luma: [Float]
        var h: [UInt8]       // OpenCV-style hue 0-180 — ball color identity (July 16)
        var yel: [Float]     // yellowness r+g-2b — yellow range balls the dh mask misses (July 17)
        var turfHue: Int     // scene turf hue the dh channel was built against (July 17)
    }

    static func planes(from image: UIImage, gain: Double = 1.0, turfOverride: Int? = nil) -> Planes? {
        guard let cg = image.cgImage else { return nil }
        let W = cg.width, H = cg.height
        var rgba = [UInt8](repeating: 0, count: W * H * 4)
        guard let ctx = CGContext(data: &rgba, width: W, height: H, bitsPerComponent: 8,
                                  bytesPerRow: W * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))

        var hplane = [UInt8](repeating: 0, count: W * H)   // OpenCV-style H in 0-180
        var vplane = [UInt8](repeating: 0, count: W * H)
        var splane = [UInt8](repeating: 0, count: W * H)
        var luma = [Float](repeating: 0, count: W * H)
        var yel = [Float](repeating: 0, count: W * H)      // r+g-2b yellowness (July 17)
        var lime = [Bool](repeating: false, count: W * H)  // collapsed-blue lime-ball signature
        var hist = [Int](repeating: 0, count: 181)         // turf-hue histogram (s>=60, v>=60)

        for p in 0..<(W * H) {
            var r = Int(rgba[p * 4]), g = Int(rgba[p * 4 + 1]), b = Int(rgba[p * 4 + 2])
            if gain != 1.0 {
                r = min(255, Int(Double(r) * gain))
                g = min(255, Int(Double(g) * gain))
                b = min(255, Int(Double(b) * gain))
            }
            let mx = max(r, g, b), mn = min(r, g, b)
            let vv = mx
            let ss = mx == 0 ? 0 : (255 * (mx - mn)) / mx
            var hdeg = 0.0
            if mx != mn {
                let d = Double(mx - mn)
                if mx == r { hdeg = 60 * (Double(g - b) / d).truncatingRemainder(dividingBy: 6) }
                else if mx == g { hdeg = 60 * (Double(b - r) / d + 2) }
                else { hdeg = 60 * (Double(r - g) / d + 4) }
                if hdeg < 0 { hdeg += 360 }
            }
            let h180 = UInt8(min(180, Int(hdeg / 2.0)))
            hplane[p] = h180
            vplane[p] = UInt8(vv)
            splane[p] = UInt8(ss)
            luma[p] = Float(r + g + b) / 3.0
            yel[p] = Float(r + g - 2 * b)
            // Lime range ball: hue sits only ~25-30 steps from turf, so the hue-distance
            // channel below is blind to it — but its blue channel collapses (b/g 0.18 vs
            // turf 0.60, measured) while staying bright. Mark it directly.
            lime[p] = g - b >= 110 && r < g && r * 2 > g && (r + g + b) / 3 >= 130
            if ss >= 60 && vv >= 60 { hist[Int(h180)] += 1 }
        }
        // median turf hue from the histogram. A ball-centered CROP has no turf majority —
        // the ball wins the histogram, its hue-distance collapses to 0, and the subpixel
        // centroid lands on garbage (synthetic-720 A/B: 0.5%→60.8% speed error). Patch
        // callers pass the parent frame's turf hue instead.
        var turf = turfOverride ?? 60
        if turfOverride == nil {
            let total = hist.reduce(0, +)
            if total > 500 {
                var acc = 0
                for (i, c) in hist.enumerated() { acc += c; if acc >= total / 2 { turf = i; break } }
            }
        }
        var dh = [UInt8](repeating: 0, count: W * H)
        for p in 0..<(W * H) {
            if vplane[p] < 60 { dh[p] = 0; continue }
            if splane[p] < 40 { dh[p] = 255; continue }
            if lime[p] { dh[p] = 255; continue }
            let d0 = abs(Int(hplane[p]) - turf)
            let d = min(d0, 180 - d0)
            dh[p] = UInt8(min(255, d * 4))
        }
        return Planes(W: W, H: H, dh: dh, v: vplane, s: splane, luma: luma, h: hplane, yel: yel,
                      turfHue: turf)
    }

    // MARK: Binary morphology (separable rect kernels)

    private static func morph(_ mask: inout [Bool], W: Int, H: Int, k: Int, dilate: Bool) {
        guard k > 1 else { return }
        let r = k / 2
        var tmp = mask
        for y in 0..<H {                       // horizontal pass
            let row = y * W
            for x in 0..<W {
                var acc = dilate ? false : true
                for dx in -r...r {
                    let xx = x + dx
                    let val = (xx >= 0 && xx < W) ? mask[row + xx] : false
                    if dilate { acc = acc || val } else { acc = acc && val }
                    if dilate && acc { break }
                    if !dilate && !acc { break }
                }
                tmp[row + x] = acc
            }
        }
        for x in 0..<W {                       // vertical pass
            for y in 0..<H {
                var acc = dilate ? false : true
                for dy in -r...r {
                    let yy = y + dy
                    let val = (yy >= 0 && yy < H) ? tmp[yy * W + x] : false
                    if dilate { acc = acc || val } else { acc = acc && val }
                    if dilate && acc { break }
                    if !dilate && !acc { break }
                }
                mask[y * W + x] = acc
            }
        }
    }

    private static func openClose(_ mask: inout [Bool], W: Int, H: Int, openK: Int, closeK: Int) {
        morph(&mask, W: W, H: H, k: openK, dilate: false)
        morph(&mask, W: W, H: H, k: openK, dilate: true)
        morph(&mask, W: W, H: H, k: closeK, dilate: true)
        morph(&mask, W: W, H: H, k: closeK, dilate: false)
    }

    // MARK: Blobs

    // ── V3 flow, step 1 (Noah's spec, July 17 night): identify the ball COLOR at lock
    // and record its exact signature. Every later stage keys off this — one ball, one
    // color, one mask family. No generic scoring of "maybe-balls".
    enum BallColor: String { case white, yellow, lime }
    struct BallSignature {
        let color: BallColor
        let hue: Double          // OpenCV 0-180 mean inside the rest disk
        let sat: Double          // 0-255
        let val: Double          // 0-255
        let yellowness: Double   // r+g-2b mean inside the rest disk
        let restRadius: Double   // subpixel disk radius at rest (the VLA anchor)
    }

    /// Samples the disk at the lock in an early frame and classifies the ball.
    /// Yellow range ball: strong r+g-2b (measured 278-290 vs turf 29-35, white -12).
    /// Lime: the existing collapsed-blue signature. Everything else: white.
    static func classifyBall(_ pl: Planes, lock: CGPoint, r0: Double) -> BallSignature {
        let W = pl.W, H = pl.H
        var n = 0.0, hs = 0.0, ss = 0.0, vs = 0.0, ys = 0.0
        let R = max(2.0, r0 * 0.85)   // stay inside the disk — edges mix background
        for yy in max(0, Int(lock.y - R))...min(H - 1, Int(lock.y + R)) {
            for xx in max(0, Int(lock.x - R))...min(W - 1, Int(lock.x + R))
            where hypot(Double(xx) - lock.x, Double(yy) - lock.y) <= R {
                let p = yy * W + xx
                hs += Double(pl.h[p]); ss += Double(pl.s[p]); vs += Double(pl.v[p])
                ys += Double(pl.yel[p]); n += 1
            }
        }
        guard n > 0 else {
            return BallSignature(color: .white, hue: 0, sat: 0, val: 200, yellowness: 0, restRadius: r0)
        }
        let hue = hs / n, sat = ss / n, val = vs / n, yel = ys / n
        let color: BallColor
        if yel >= 150 && hue >= 15 && hue <= 45 {
            color = .yellow
        } else if yel >= 150 {
            color = .lime
        } else {
            color = .white
        }
        return BallSignature(color: color, hue: hue, sat: sat, val: val, yellowness: yel, restRadius: r0)
    }

    struct Blob {
        var src: String
        var area: Double, circ: Double, r: Double
        var cx: Double, cy: Double
        var w: Int, h: Int
        var theta: Double, elong: Double
        var border: Bool
        var mot: Double, dhMean: Double, vMean: Double
        var hMean: Double = 0, sMean: Double = 0
        var prob: Double = 0
    }

    private static func blobs(mask: [Bool], planes: Planes, motion: [Float]?, src: String, minArea: Double,
                              connectivity8: Bool = false) -> [Blob] {
        let W = planes.W, H = planes.H
        var visited = [Bool](repeating: false, count: W * H)
        var out: [Blob] = []
        var queue = [Int]()
        for start in 0..<(W * H) where mask[start] && !visited[start] {
            visited[start] = true
            queue.removeAll(keepingCapacity: true)
            queue.append(start)
            var head = 0
            var pix: [Int] = []
            while head < queue.count {
                let p = queue[head]; head += 1
                pix.append(p)
                let x = p % W, y = p / W
                // 8-connectivity matches OpenCV connectedComponents (club-union model was
                // trained on it; thin diagonal club shapes fragment under 4-connectivity).
                let neigh: [(Int, Int)] = connectivity8
                    ? [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)]
                    : [(-1, 0), (1, 0), (0, -1), (0, 1)]
                for (dx, dy) in neigh {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < W, ny >= 0, ny < H else { continue }
                    let np = ny * W + nx
                    if mask[np] && !visited[np] { visited[np] = true; queue.append(np) }
                }
            }
            let area = Double(pix.count)
            if area < minArea { continue }
            var sx = 0.0, sy = 0.0
            var minX = W, maxX = 0, minY = H, maxY = 0
            for p in pix {
                let x = p % W, y = p / W
                sx += Double(x); sy += Double(y)
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
            let cx = sx / area, cy = sy / area
            var mu20 = 0.0, mu02 = 0.0, mu11 = 0.0, er2 = 0.0
            var motSum = 0.0, dhSum = 0.0, vSum = 0.0, hSum = 0.0, sSum = 0.0
            for p in pix {
                let x = Double(p % W) - cx, y = Double(p / W) - cy
                mu20 += x * x; mu02 += y * y; mu11 += x * y
                er2 = max(er2, x * x + y * y)
                motSum += motion.map { Double($0[p]) } ?? 0
                dhSum += Double(planes.dh[p]); vSum += Double(planes.v[p])
                hSum += Double(planes.h[p]); sSum += Double(planes.s[p])
            }
            mu20 /= area; mu02 /= area; mu11 /= area
            let theta = (mu20 != mu02 || mu11 != 0) ? 0.5 * atan2(2 * mu11, mu20 - mu02) : 0
            let elong = (sqrt(pow(mu20 - mu02, 2) + 4 * mu11 * mu11)) / (mu20 + mu02 + 1e-9)
            let er = max(sqrt(er2), 1)
            out.append(Blob(
                src: src, area: area,
                circ: area / (Double.pi * er * er + 1e-6),
                r: sqrt(area / Double.pi), cx: cx, cy: cy,
                w: maxX - minX + 1, h: maxY - minY + 1,
                theta: theta, elong: elong,
                border: minX <= 1 || minY <= 1 || maxX >= W - 2 || maxY >= H - 2,
                mot: motSum / area, dhMean: dhSum / area, vMean: vSum / area,
                hMean: hSum / area, sMean: sSum / area))
        }
        return out
    }

    private static func maskFrom(_ planes: Planes, motion: [Float]?, prevLuma: [Float]?,
                                 yelBase: [Float]? = nil) -> (bright: [Blob], dark: [Blob], diff: [Blob]) {
        let W = planes.W, H = planes.H
        var bm = (0..<(W * H)).map { planes.dh[$0] >= 160 }
        // Yellow-ball boost (July 17): the dh mask missed 30/49 debug-covered flight
        // frames on yellow range balls — the ball IS visible in baseline-subtracted
        // yellowness (the same signal the offline oracle labeled with). Only active when
        // the locked ball measured yellow (yelBase non-nil).
        if let yb = yelBase, yb.count == W * H {
            for p in 0..<(W * H) where !bm[p] {
                bm[p] = planes.yel[p] - yb[p] >= 90 && planes.v[p] >= 80
            }
        }
        openClose(&bm, W: W, H: H, openK: 3, closeK: 5)
        let bright = blobs(mask: bm, planes: planes, motion: motion, src: "bright", minArea: 8)

        var dm = (0..<(W * H)).map { planes.v[$0] <= 78 && planes.s[$0] <= 130 }
        if let mot = motion {
            for p in 0..<(W * H) where mot[p] < 12 { dm[p] = false }
        }
        openClose(&dm, W: W, H: H, openK: 3, closeK: 5)
        let dark = blobs(mask: dm, planes: planes, motion: motion, src: "dark", minArea: 50)

        var diff: [Blob] = []
        if let prev = prevLuma {
            var fd = [Float](repeating: 0, count: W * H)
            for p in 0..<(W * H) { fd[p] = abs(planes.luma[p] - prev[p]) }
            let sorted = fd.sorted()
            let thr = max(15.0, Double(sorted[sorted.count / 2]) * 4 + 8)
            var fm = (0..<(W * H)).map { Double(fd[$0]) >= thr }
            openClose(&fm, W: W, H: H, openK: 2, closeK: 9)
            diff = blobs(mask: fm, planes: planes, motion: motion, src: "diff", minArea: 30)
        }
        return (bright, dark, diff)
    }

    // MARK: Feature vectors (must match training exactly — see tools/experimental)

    private static func ballFeatures(_ b: Blob, lock: CGPoint, r0: Double, pred: CGPoint?,
                                     dir: (Double, Double)?, progress: Double, impacted: Bool,
                                     lockHS: (Double, Double)? = nil) -> [Double] {
        var distPred = 0.5
        if let p = pred {
            distPred = min(hypot(b.cx - p.x, b.cy - p.y) / max(r0, 1), 8.0) / 8.0
        }
        let vx = b.cx - lock.x, vy = b.cy - lock.y
        let dist = hypot(vx, vy)
        var dev = 0.5, aligned = 0.5
        if let d = dir, dist > 1e-6 {
            let du = (vx / dist, vy / dist)
            dev = acos(max(-1, min(1, du.0 * d.0 + du.1 * d.1))) * 180 / .pi / 180.0
            let ax = cos(b.theta), ay = sin(b.theta)
            aligned = abs(ax * d.0 + ay * d.1)
        }
        let step = (dist - progress) / max(r0, 1)
        return [b.circ, b.elong, min(b.r / max(r0, 1), 3.0) / 3.0,
                b.dhMean / 255.0, b.border ? 1 : 0,
                distPred, dev, max(-2, min(step / 10.0, 2.0)), aligned,
                impacted ? 1 : 0, b.src == "rescue" ? 1 : 0,
                // mot_norm (July 16): motion vs pre-impact baseline — separates the flying
                // ball (56-98) from the static balls littering a real range field (2-15).
                // Trained as the 12th feature; older 11-weight models simply ignore it
                // (the scorer loop zips min(w.count, feats.count)).
                min(b.mot, 80.0) / 80.0,
                // hue_sim/sat_sim (features 13-14): identity match to the LOCKED ball's
                // color — a yellow ball can't be confused with the gray clubhead or white
                // clutter, and white balls get a free consistency check. 0.5 = unknown.
                hueSim(b, lockHS), satSim(b, lockHS)]
    }

    private static func hueSim(_ b: Blob, _ lockHS: (Double, Double)?) -> Double {
        guard let l = lockHS else { return 0.5 }
        var d = abs(b.hMean - l.0)
        d = min(d, 180 - d)
        return 1.0 - min(d, 45.0) / 45.0
    }

    private static func satSim(_ b: Blob, _ lockHS: (Double, Double)?) -> Double {
        guard let l = lockHS else { return 0.5 }
        return 1.0 - min(abs(b.sMean - l.1), 128.0) / 128.0
    }

    private static func clubFeatures(_ b: Blob, lock: CGPoint, r0: Double, prevClub: CGPoint?) -> [Double] {
        let dx = b.cx - lock.x, dy = b.cy - lock.y
        let dist = hypot(dx, dy)
        let backward = dx    // FLIGHT_DIR = -1: backward = +x side
        let coneAng = backward > 0 ? atan2(abs(dy), backward) * 180 / .pi : 180.0
        var base: [Double] = [
            log(max(b.area, 1)),
            Double(max(b.w, b.h)) / Double(max(1, min(b.w, b.h))),
            b.elong, min(b.mot, 80) / 80.0, b.dhMean / 255.0, b.vMean / 255.0,
            min(dist / max(r0, 1) / 20.0, 1.5), min(coneAng, 180) / 180.0,
            b.src == "bright" ? 1 : 0, b.src == "dark" ? 1 : 0, b.src == "diff" ? 1 : 0,
            b.border ? 1 : 0, b.circ]
        if let pc = prevClub {
            base.append(min(hypot(b.cx - pc.x, b.cy - pc.y) / max(r0, 1) / 12.0, 1.5))
            base.append(1.0)
        } else {
            base.append(1.0); base.append(0.0)
        }
        let n = max(dist, 1e-6)
        let radial = (dx / n, dy / n)
        let coneCos = abs(cos(b.theta) * radial.0 + sin(b.theta) * radial.1)
        base.append(Double(b.w) / max(r0, 1) / 10.0)
        base.append(Double(b.h) / max(r0, 1) / 10.0)
        base.append(coneCos)
        return base
    }

    // MARK: Public entry

    /// Runs the V2 pipeline over the captured shot. `impactHint` is the capture's fallback
    /// impact index; the engine re-derives the true impact from ball motion.
    static func run(frames: [AnalyzedShotFrame], lockedBallRect: CGRect?, impactHint: Int) -> V2Output? {
        guard let models else { return nil }
        var notes: [String] = []

        // planes per frame (original color images)
        var planeByIdx: [Int: Planes] = [:]
        for f in frames {
            if let p = planes(from: f.originalFrame.image) { planeByIdx[f.frameIndex] = p }
        }
        guard let first = planeByIdx.values.first else { return nil }
        let W = first.W, H = first.H

        // pre-impact median luma baseline (motion channel)
        let preIdx = frames.map(\.frameIndex).sorted().prefix(while: { $0 < max(3, impactHint - 2) })
        var basePlanes: [[Float]] = []
        for i in stride(from: 0, to: min(14, preIdx.count), by: 3) {
            if let p = planeByIdx[preIdx[i]] { basePlanes.append(p.luma) }
        }
        var baseLuma: [Float]? = nil
        if basePlanes.count >= 3 {
            var b = [Float](repeating: 0, count: W * H)
            for p in 0..<(W * H) {
                var vals = basePlanes.map { $0[p] }
                vals.sort()
                b[p] = vals[vals.count / 2]
            }
            baseLuma = b
        }

        func motion(for pl: Planes) -> [Float]? {
            guard let base = baseLuma else { return nil }
            var m = [Float](repeating: 0, count: W * H)
            for p in 0..<(W * H) { m[p] = abs(pl.luma[p] - base[p]) }
            return m
        }

        // ── lock: observed rest ball (metadata lock as fallback)
        var lock = CGPoint(x: Double(lockedBallRect?.midX ?? 0.64) * Double(W),
                           y: Double(lockedBallRect?.midY ?? 0.55) * Double(H))
        var r0 = max(4.0, Double(lockedBallRect?.width ?? 0.05) * Double(W) / 2)
        var restCands: [[Blob]] = []
        for fi in [0, 2, 4, 6, 8] {
            guard let pl = planeByIdx[fi] else { continue }
            let (bright, _, _) = maskFrom(pl, motion: nil, prevLuma: nil)
            restCands.append(bright.filter { $0.r >= 2.5 && $0.r <= 22 && $0.circ >= 0.55 && $0.area >= 15 && !$0.border })
        }
        var bestRest: Blob? = nil; var bestN = 0
        for fr in restCands {
            for b in fr {
                let n = restCands.reduce(0) { acc, other in
                    acc + (other.contains { hypot($0.cx - b.cx, $0.cy - b.cy) <= max(4, b.r) } ? 1 : 0)
                }
                if n > bestN { bestN = n; bestRest = b }
            }
        }
        // The observed candidate may REFINE the metadata lock, never RELOCATE it: on
        // 082406_945 the consensus blob was a r=19.7 white object far from the (correct)
        // metadata lock — the shot classified white, the yellow path shut off, and the
        // whole track fell to legacy junk. Same on 084900_726.
        let hasMetaLock = lockedBallRect != nil
        if let rest = bestRest, bestN >= 3,
           !hasMetaLock || (hypot(rest.cx - lock.x, rest.cy - lock.y) <= max(10.0, r0 * 2.5)
                            && rest.r <= r0 * 2.0 && rest.r >= r0 * 0.4) {
            lock = CGPoint(x: rest.cx, y: rest.cy)
            r0 = max(4.0, rest.r)
            notes.append("lock=observed-rest-ball")
        } else {
            notes.append(bestRest != nil && bestN >= 3
                         ? "lock=capture-metadata (observed candidate rejected: too far/size)"
                         : "lock=capture-metadata")
        }

        // ── V3 step 1: classify the ball at the lock, once, up front.
        var sig: BallSignature? = nil
        if let fi0 = frames.map(\.frameIndex).min(), let pl0 = planeByIdx[fi0] {
            let s0 = classifyBall(pl0, lock: lock, r0: r0)
            sig = s0
            notes.append(String(format: "ball=%@ hue=%.0f sat=%.0f yel=%.0f rest_r=%.2f",
                                s0.color.rawValue, s0.hue, s0.sat, s0.yellowness, s0.restRadius))
        }

        // ── yellow range ball? sample absolute yellowness at the lock; when yellow,
        // build a per-pixel yellowness baseline (median of early frames) so the flight
        // mask can see the ball the dh channel misses (measured: 30/49 debug-covered
        // yellow flight misses had NO dh blob at the labeled position).
        var yelBase: [Float]? = nil
        if let fi0 = frames.map(\.frameIndex).min(), let pl0 = planeByIdx[fi0] {
            var acc = 0.0
            var n = 0
            let W0 = pl0.W
            for yy in max(0, Int(lock.y - r0))...min(pl0.H - 1, Int(lock.y + r0)) {
                for xx in max(0, Int(lock.x - r0))...min(W0 - 1, Int(lock.x + r0))
                where hypot(Double(xx) - lock.x, Double(yy) - lock.y) <= r0 {
                    acc += Double(pl0.yel[yy * W0 + xx])
                    n += 1
                }
            }
            if n > 0, acc / Double(n) >= 150 {
                var early: [[Float]] = []
                for fi in [0, 2, 4, 6, 8] { if let pl = planeByIdx[fi] { early.append(pl.yel) } }
                if early.count >= 3 {
                    var base = [Float](repeating: 0, count: early[0].count)
                    for p in 0..<base.count {
                        var vals = early.map { $0[p] }
                        vals.sort()
                        base[p] = vals[vals.count / 2]
                    }
                    yelBase = base
                    notes.append("yellow-mask-boost")
                }
            }
        }

        // ── V3 step 2 (Noah's spec): the rest tracker runs until it FAILS — impact is
        // the frame before the ball moved. Presence = color-pixel count inside the lock
        // disk vs frame 0. Validated offline: 98.8% within ±1 frame of hand labels
        // (287/320 exact), replacing the cone-scan/departure machinery as primary.
        var v3Impact: Int? = nil
        do {
            func diskCount(_ pl: Planes) -> Int {
                let W = pl.W, H = pl.H
                let R = max(2.0, r0 * 1.1)
                var n = 0
                for yy in max(0, Int(lock.y - R))...min(H - 1, Int(lock.y + R)) {
                    for xx in max(0, Int(lock.x - R))...min(W - 1, Int(lock.x + R))
                    where hypot(Double(xx) - lock.x, Double(yy) - lock.y) <= R {
                        let p = yy * W + xx
                        let isBall: Bool
                        if let s0 = sig, s0.color != .white {
                            isBall = pl.yel[p] >= 120
                        } else {
                            isBall = pl.luma[p] >= 150 && pl.s[p] < 70
                        }
                        if isBall { n += 1 }
                    }
                }
                return n
            }
            let ordered = frames.map(\.frameIndex).sorted()
            if let f0 = ordered.first, let pl0 = planeByIdx[f0] {
                let baseCount = diskCount(pl0)
                if baseCount >= 8 {
                    var lastPresent = f0
                    var absent = 0
                    for fi in ordered.dropFirst() {
                        guard let pl = planeByIdx[fi] else { continue }
                        if Double(diskCount(pl)) >= Double(baseCount) * 0.45 {
                            lastPresent = fi
                            absent = 0
                        } else {
                            absent += 1
                            if absent >= 2 { v3Impact = lastPresent; break }
                        }
                    }
                    if v3Impact == nil, absent >= 1 { v3Impact = lastPresent }
                }
            }
        }

        // ── impact: first frame a NEW round blob sits >=1.5 r0 forward of the lock, minus
        // one. "New" is load-bearing: round bright glare that already exists in the earliest
        // frames is scenery — without the exclusion it fired impact 6 frames early on the
        // Simulate Shot sample, a junk pre-launch pick became "flight", and the monotone
        // gate then walled out the real airborne ball.
        var impact = impactHint
        var impactSrc = "hint"
        let idxSorted = frames.map(\.frameIndex).sorted()
        var staticForward: [(x: Double, y: Double, r: Double)] = []
        for fi in idxSorted.prefix(3) {
            guard let pl = planeByIdx[fi] else { continue }
            let (bright, _, _) = maskFrom(pl, motion: motion(for: pl), prevLuma: nil)
            for b in bright where b.r >= 2.5 && b.r <= 22 && b.circ >= 0.55 && b.area >= 15 {
                staticForward.append((b.cx, b.cy, b.r))
            }
        }
        // ── presence timeline: per-frame "ball still at the lock", from the APPEARANCE
        // mask (motion: nil — the same mask the rest-lock stage uses). The motion-gated
        // mask reads a STATIC ball as absent (no inter-frame diff), which silently
        // disabled the at-lock veto below and let the cone scan fire on pre-launch junk
        // (measured: impact f11 vs labeled launch f20 on 2026-07-17 shot 082406).
        // Two tiers. STRICT is a clean resting ball — it bounds where the cone scan may
        // fire. OCCUPIED is any bright footprint still covering the lock: the mid-strike
        // ball blurs (fails circ), and the arriving clubhead MERGES with the ball into one
        // big irregular blob — both must read "ball not confirmed gone" or departure fires
        // 1-2 frames early and drops the labeled impact frame (24/211 white-suite shots).
        var atLock: [Int: Bool] = [:]
        var atLockOccupied: [Int: Bool] = [:]
        for fi in idxSorted where fi >= max(0, impactHint - 10) && fi <= impactHint + 9 {
            guard let pl = planeByIdx[fi] else { continue }
            let (bright, _, _) = maskFrom(pl, motion: nil, prevLuma: nil)
            atLock[fi] = bright.contains {
                $0.circ >= 0.65 && $0.r >= r0 * 0.6 && $0.r <= r0 * 1.7
                    && hypot($0.cx - lock.x, $0.cy - lock.y) <= r0 * 1.5
            }
            // Distance from the lock to the blob's (centroid-anchored) bbox: a merged
            // ball+club blob has its centroid dragged toward the club, but its footprint
            // still reaches the ball — bbox proximity is what says "something is there".
            atLockOccupied[fi] = bright.contains { b in
                let dx = max(abs(lock.x - b.cx) - Double(b.w) / 2, 0)
                let dy = max(abs(lock.y - b.cy) - Double(b.h) / 2, 0)
                return hypot(dx, dy) <= r0
            }
        }
        // Last frame the clean resting ball was SEEN at the lock: the cone scan may only
        // fire after it. This kills cone fires inside a presence flicker (the ball is
        // provably back at the lock afterwards, so any forward blob in the gap was junk).
        let lastStrictPresent = atLock.filter { $0.value }.keys.max() ?? -1
        outer: for fi in idxSorted where fi >= max(0, impactHint - 8) && fi <= impactHint + 9 && fi > lastStrictPresent {
            guard let pl = planeByIdx[fi] else { continue }
            let (bright, _, _) = maskFrom(pl, motion: motion(for: pl), prevLuma: nil)
            // Ball-sized relative to the LOCKED radius, not just absolute: the cone fired
            // impact 9 frames early on r≈3px junk specks (r0 5.7) at frames where the
            // appearance mask happened to miss the resting ball (2026-07-17 shots 082406,
            // 083656, 084259) — a just-launched ball is still lock-sized.
            for b in bright where b.r >= max(2.5, r0 * 0.5) && b.r <= min(22, r0 * 2.2)
                && b.circ >= 0.55 && b.area >= 15 && !b.border {
                let vx = b.cx - lock.x
                if vx * -1 <= 0 { continue }        // forward is -x
                // Launch cone: a just-struck ball leaves from LOCK HEIGHT. Vertical headroom
                // must cover a high wedge flying nearly straight up-frame (measured Δy=63px
                // at Δx=3 on a labeled lob) while still rejecting the treeline glint at the
                // top edge (Δy=95 at Δx=45).
                if abs(b.cy - lock.y) > max(r0 * 12, 1.75 * abs(vx)) { continue }
                if hypot(vx, b.cy - lock.y) >= r0 * 1.5,
                   !staticForward.contains(where: {
                       hypot($0.x - b.cx, $0.y - b.cy) <= max(4, max($0.r, b.r))
                   }) {
                    impact = fi - 1
                    impactSrc = String(format: "ball-motion@f%d(%.0f,%.0f r%.1f circ%.2f)", fi, b.cx, b.cy, b.r, b.circ)
                    break outer
                }
            }
        }
        // ── Ball-departure detector (July 17): the capture trigger routinely fires 1-4
        // frames AFTER the real launch, and when the forward-blob scan couldn't confirm
        // (fast exits, glare), impact stayed at the HINT — the flight frames between real
        // launch and hint+1 were silently discarded on nearly every fast shot (Noah's
        // labels: launches at f16-19 vs hint f20, on every session). The ball LEAVING its
        // lock IS the launch: after >=3 frames of a ball-like blob at the lock, the last
        // present frame before 2 consecutive absent frames is the impact frame.
        // Scans the WHOLE window (no early exit): a 1-2 frame appearance flicker with the
        // ball back at the lock afterwards voids the candidate — only the final sustained
        // absence counts as the departure.
        // Presence here is the OCCUPIED tier: the blurred mid-strike ball and the merged
        // ball+club blob both count as "not yet departed", so departure lands ON the
        // impact frame, not 1-2 before it.
        var depPresentRun = 0
        var depAbsentRun = 0
        var depCandidate: Int? = nil
        var depLastPresent: Int? = nil
        for fi in idxSorted where fi >= max(0, impactHint - 10) && fi <= impactHint + 9 {
            guard let present = atLockOccupied[fi] else { continue }
            if present {
                depPresentRun += 1
                depLastPresent = fi
                depCandidate = nil
                depAbsentRun = 0
            } else if depPresentRun >= 3 {
                if depCandidate == nil { depCandidate = depLastPresent }
                depAbsentRun += 1
            }
        }
        // min-combine with the cone scan: the loose tier can read lingering glare residue
        // (or the arriving clubhead) as "still present" and drag departure late — when the
        // cone saw genuine forward flight EARLIER, the cone wins. Junk cone fires are
        // already excluded by the lastStrictPresent bound above.
        // Only ever moves impact EARLIER: the capture hint fires late when it's wrong
        // (labeled launches f16-19 vs hint f20, every session), so a departure LATER than
        // cone/hint means the loose tier latched onto residue, not that impact is late.
        if let dep = depCandidate, depAbsentRun >= 2, dep < impact {
            impact = dep
            impactSrc = String(format: "ball-departure@f%d", dep)
        }
        if let v3 = v3Impact {
            impact = v3
            impactSrc = String(format: "v3-rest-failure@f%d", v3)
        }
        notes.append("impact=f\(impact)(\(impactSrc))")

        // ── ball track (sequential v2.2 state machine)
        var progress = 0.0
        var direction: (Double, Double)? = nil
        var lastT: Double? = nil
        var lastPos: CGPoint? = nil
        var vel: (Double, Double)? = nil
        var exited = false
        var flightPoints = 0
        var missesInFlight = 0
        var rescuesLeft = 2
        var prevLuma: [Float]? = nil
        var prevClub: CGPoint? = nil
        var v3Prev: CGPoint? = nil   // V3 yellow-flight chain anchor

        struct FlightPt { let t: Double; var x: Double; var y: Double; var r: Double; let fi: Int }
        var flight: [FlightPt] = []
        var clubPts: [(t: Double, x: Double, y: Double)] = []
        var restRadii: [Double] = []
        var lockHS: (Double, Double)? = nil    // rest-ball color identity (hue 0-180, sat 0-255)
        var frameObs: [V2FrameObservation] = []
        var clubObs: [V2ClubObservation] = []

        for f in frames.sorted(by: { $0.frameIndex < $1.frameIndex }) {
            let fi = f.frameIndex
            guard let pl = planeByIdx[fi] else { continue }
            let mot = motion(for: pl)
            let (bright, dark, diff) = maskFrom(pl, motion: mot, prevLuma: prevLuma, yelBase: yelBase)
            prevLuma = pl.luma
            let t = f.timestamp
            let impacted = fi > impact

            // club (approach window only; used for club speed + follow-through has no value)
            if fi <= impact + 1 {
                var pool: [(Double, Blob)] = []
                for b in (bright + dark + diff) where b.area >= 12 && b.area <= 6000 {
                    let p = models.club_gbt.prob(clubFeatures(b, lock: lock, r0: r0, prevClub: prevClub))
                    pool.append((p, b))
                }
                // (A sub-threshold geometric rescue was tried here July 16 and REMOVED:
                // window coverage stayed flat (34.1% vs 34.3%) while off-target picks rose
                // 17->29 — below-threshold bests are imprecise, and precision is this
                // tracker's one virtue. The coverage ceiling is mask findability, not the
                // threshold.)
                var accepted: (Double, Blob)? = nil
                if let bestC = pool.max(by: { $0.0 < $1.0 }), bestC.0 >= models.club_gbt.threshold {
                    accepted = bestC
                }
                if let bestC = accepted {
                    prevClub = CGPoint(x: bestC.1.cx, y: bestC.1.cy)
                    if fi <= impact, fi >= impact - 6 {
                        clubPts.append((t, bestC.1.cx, bestC.1.cy))
                    }
                    if fi >= impact - 6 {
                        clubObs.append(V2ClubObservation(
                            frameIndex: fi, cxNorm: bestC.1.cx / Double(W),
                            cyNorm: bestC.1.cy / Double(H), confidence: bestC.0))
                    }
                }
            }

            if !impacted {
                // rest ball: roundest bright blob at the lock (+ merged-strike rescue)
                let cands = bright.filter {
                    $0.r >= 2.0 && $0.r <= 24 && $0.area >= 12 && !$0.border && $0.circ >= 0.5
                        && hypot($0.cx - lock.x, $0.cy - lock.y) <= r0 * 2.2
                }
                if let rest = cands.max(by: { $0.circ < $1.circ }) {
                    var (rx, ry, rr) = subpixelCenter(pl, cx: rest.cx, cy: rest.cy, rHint: rest.r)
                    if let refined = refineOnHiRes(f, sx: rx, sy: ry, sr: rr, turfHue: pl.turfHue) {
                        (rx, ry, rr) = refined
                    }
                    restRadii.append(rr)
                    lockHS = (rest.hMean, rest.sMean)
                    frameObs.append(V2FrameObservation(
                        frameIndex: fi, cxNorm: rx / Double(W), cyNorm: ry / Double(H),
                        diaNorm: 2 * rr / Double(W), confidence: 0.9, isFlight: false))
                }
                continue
            }
            if exited { continue }

            // exit projection (dt-exact)
            if let v = vel, let lt = lastT, let lp = lastPos {
                let dt = t - lt
                let px = lp.x + v.0 * dt, py = lp.y + v.1 * dt
                // Margin widened 1.5r→6r: linear prediction OVERSHOOTS a decelerating or
                // arcing ball, and the old margin declared exit while the ball was still
                // 20-40px inside the frame (measured: 21 mid-frame tail losses on July 16).
                let m = r0 * 6
                if !(-m...(Double(W) + m)).contains(px) || !(-m...(Double(H) + m)).contains(py) {
                    exited = true
                    continue
                }
            }

            // ── V3 step 4: yellow shots bypass the scorer entirely — the color-specific
            // disk-fit search matched 98.9% of labeled flight points offline (V2 state
            // machine: 66%). White shots keep the validated V2 path.
            if let s0 = sig, s0.color != .white, let yb = yelBase, impacted {
                if let v3 = v3YellowPick(pl, baseYel: yb, lock: lock, r0: r0, prev: v3Prev) {
                    flightPoints += 1
                    v3Prev = CGPoint(x: v3.0, y: v3.1)
                    flight.append(FlightPt(t: t, x: v3.0, y: v3.1, r: v3.2, fi: fi))
                    frameObs.append(V2FrameObservation(
                        frameIndex: fi, cxNorm: v3.0 / Double(W), cyNorm: v3.1 / Double(H),
                        diaNorm: 2 * v3.2 / Double(W), confidence: 0.9, isFlight: true))
                    missesInFlight = 0
                    if let lt = lastT, t > lt, let lp = lastPos {
                        vel = ((v3.0 - Double(lp.x)) / (t - lt), (v3.1 - Double(lp.y)) / (t - lt))
                    }
                    lastT = t
                    lastPos = CGPoint(x: v3.0, y: v3.1)
                } else if flightPoints >= 1 {
                    missesInFlight += 1
                    if missesInFlight >= 8 { exited = true }
                }
                continue
            }

            var cands: [(Double, Blob)] = []
            var subCands: [(Double, Blob)] = []
            let pred: CGPoint? = {
                guard let v = vel, let lt = lastT, let lp = lastPos else { return nil }
                let dt = t - lt
                return CGPoint(x: lp.x + v.0 * dt, y: lp.y + v.1 * dt)
            }()
            let v2dbg = ProcessInfo.processInfo.environment["TC_V2_DEBUG"] == "1"
            for b in bright {
                guard b.r >= 2.0, b.r <= 24, b.area >= 12 else {
                    if v2dbg, b.area >= 8 {
                        print(String(format: "[V2dbg] f%02d blob(%.0f,%.0f) r=%.1f a=%.0f REJ size", fi, b.cx, b.cy, b.r, b.area))
                    }
                    continue
                }
                let vx = b.cx - lock.x, vy = b.cy - lock.y
                let dist = hypot(vx, vy)
                if dist >= r0 && vx > 0 {
                    if v2dbg { print(String(format: "[V2dbg] f%02d blob(%.0f,%.0f) REJ backwards", fi, b.cx, b.cy)) }
                    continue
                }
                if dist < progress - r0 * 1.5 {
                    if v2dbg { print(String(format: "[V2dbg] f%02d blob(%.0f,%.0f) REJ monotone (d=%.0f prog=%.0f)", fi, b.cx, b.cy, dist, progress)) }
                    continue
                }
                if let lp = lastPos, let p = pred {
                    let dLast = hypot(b.cx - lp.x, b.cy - lp.y)
                    let dPred = hypot(p.x - lp.x, p.y - lp.y)
                    if dLast < r0 && dPred > r0 * 2.5 {
                        if v2dbg { print(String(format: "[V2dbg] f%02d blob(%.0f,%.0f) REJ static-junk", fi, b.cx, b.cy)) }
                        continue
                    }
                }
                // (A per-frame launch-physics distance cap was tried here and REMOVED: impact
                // detection lags on fast shots — the real ball was measured 199px out one
                // frame after detected impact and the cap rejected it, handing the track to
                // the moving clubhead. The static gate below is what actually kills clutter.)
                // Static-scenery gate: a flight candidate must DIFFER from the pre-impact
                // baseline where it stands. Balls littering a range field read mot 2-15
                // (pure shimmer) and score 0.95+ on shape alone — they beat the real ball
                // and their bogus distance poisons `progress`, monotone-locking the true
                // track out. A genuinely flying ball drags bright over new background every
                // frame (measured mot 56-98 vs clutter 2-15), so 20 splits them cleanly.
                if b.mot < 20 {
                    if v2dbg { print(String(format: "[V2dbg] f%02d blob(%.0f,%.0f) REJ static (mot=%.0f)", fi, b.cx, b.cy, b.mot)) }
                    continue
                }
                let feats = ballFeatures(b, lock: lock, r0: r0, pred: pred,
                                         dir: direction, progress: progress, impacted: true,
                                         lockHS: lockHS)
                var z = models.ball_scorer.b
                for i in 0..<min(models.ball_scorer.w.count, feats.count) { z += models.ball_scorer.w[i] * feats[i] }
                let p = 1.0 / (1.0 + exp(-max(-30, min(30, z))))
                if v2dbg {
                    print(String(format: "[V2dbg] f%02d blob(%.0f,%.0f) r=%.1f circ=%.2f elong=%.2f dh=%.0f mot=%.0f p=%.3f %@",
                                 fi, b.cx, b.cy, b.r, b.circ, b.elong, b.dhMean, b.mot, p,
                                 p >= models.ball_scorer.threshold ? "PASS" : "rej-score"))
                }
                if p >= models.ball_scorer.threshold { cands.append((p, b)) }
                else if p >= 0.32 { subCands.append((p, b)) }
            }
            let chosenScored = cands.max(by: { $0.0 < $1.0 })
            var chosen = chosenScored?.1
            var chosenProb = chosenScored?.0 ?? 0.6   // rescue picks carry moderate confidence
            // Sub-threshold acceptance (July 17): the scorer killed 15/49 debug-covered
            // real flight balls in cascade-broken states (its state features assume an
            // intact track). A below-threshold candidate is still taken when geometry
            // vouches for it — on the ballistic prediction, or (before any track exists)
            // inside the launch cone. conf carries the low score so the fit downweights.
            // Prediction-vouched ONLY (July 17 night): a launch-cone variant that fired
            // before any track existed was tried and REVERSED same-session — +10 false
            // picks and TT speed 15.6→17.9% on July-17. No track, no forcing: exactly
            // the skip-over-guess policy.
            if chosen == nil, let best = subCands.max(by: { $0.0 < $1.0 }),
               let p = pred, hypot(best.1.cx - p.x, best.1.cy - p.y) <= r0 * 2.5 {
                chosen = best.1
                chosenProb = best.0
            }
            if chosen == nil, !exited, rescuesLeft > 0, let p = pred {
                if let rb = rescueAt(pl, x: p.x, y: p.y, rHint: r0) {
                    rescuesLeft -= 1
                    chosen = rb
                    chosenProb = 0.6
                }
            }
            // Strict re-acquisition: after 2+ consecutive misses the track used to DIE
            // (exited=true), losing the whole tail — 39 of 68 labeled flight misses on the
            // July 16 session were "after last tracked frame". Now misses only tighten the
            // gate: a candidate must sit close to the ballistic prediction to resume, so a
            // genuinely-gone ball can't be replaced by scenery, but a 1-2 frame dropout
            // (grain, glare crossing) no longer amputates the track.
            if missesInFlight >= 2, let c = chosen, let p = pred {
                if hypot(c.cx - p.x, c.cy - p.y) > r0 * 3 { chosen = nil }
            }
            if let c = chosen {
                let vx = c.cx - lock.x, vy = c.cy - lock.y
                let dist = hypot(vx, vy)
                progress = max(progress, dist)
                if dist >= r0 * 2 { direction = (vx / dist, vy / dist) }
                if dist >= r0 {
                    flightPoints += 1
                    var (sx, sy, sr) = subpixelCenter(pl, cx: c.cx, cy: c.cy, rHint: c.r)
                    if let refined = refineOnHiRes(f, sx: sx, sy: sy, sr: sr, turfHue: pl.turfHue) {
                        (sx, sy, sr) = refined
                    }
                    flight.append(FlightPt(t: t, x: sx, y: sy, r: sr, fi: fi))
                    frameObs.append(V2FrameObservation(
                        frameIndex: fi, cxNorm: sx / Double(W), cyNorm: sy / Double(H),
                        diaNorm: 2 * sr / Double(W), confidence: chosenProb, isFlight: true))
                } else {
                    // Post-impact but still within a lock radius: a slow roll-away or the
                    // impact-merge frame — a real sighting either way, marked non-flight.
                    frameObs.append(V2FrameObservation(
                        frameIndex: fi, cxNorm: c.cx / Double(W), cyNorm: c.cy / Double(H),
                        diaNorm: 2 * c.r / Double(W), confidence: min(chosenProb, 0.7), isFlight: false))
                }
                missesInFlight = 0
                if let lt = lastT, t > lt, let lp = lastPos {
                    vel = ((c.cx - lp.x) / (t - lt), (c.cy - lp.y) / (t - lt))
                }
                lastT = t
                lastPos = CGPoint(x: c.cx, y: c.cy)
            } else if flightPoints >= 1 {
                missesInFlight += 1
                if missesInFlight >= 8 { exited = true }
            }
        }

        // ── V3 track-line clean (Noah's #2): a bucket/waiting-area ball tens of px off
        // the arc breaks the whole fit. Quadratic fit over the flight points; only WILD
        // deviations (> max(6 r0, 30px)) are junk — perspective curvature must survive.
        // Validated offline: removes 0 labeled-real points.
        if let s0 = sig, s0.color != .white, flight.count >= 3 {
            let t = (0..<flight.count).map(Double.init)
            func polyfit2(_ ys: [Double]) -> (Double, Double, Double) {
                let n = Double(t.count)
                var s1 = 0.0, s2 = 0.0, s3 = 0.0, s4 = 0.0
                var sy = 0.0, sty = 0.0, st2y = 0.0
                for i in 0..<t.count {
                    let x = t[i], y = ys[i]
                    s1 += x; s2 += x*x; s3 += x*x*x; s4 += x*x*x*x
                    sy += y; sty += x*y; st2y += x*x*y
                }
                let A = [[n, s1, s2], [s1, s2, s3], [s2, s3, s4]]
                var b = [sy, sty, st2y]
                var M = A.map { $0 }
                for c in 0..<3 {
                    let piv = M[c][c]
                    guard abs(piv) > 1e-9 else { return (ys.reduce(0,+)/n, 0, 0) }
                    for rr in (c+1)..<3 {
                        let f = M[rr][c] / piv
                        for cc in c..<3 { M[rr][cc] -= f * M[c][cc] }
                        b[rr] -= f * b[c]
                    }
                }
                var c2 = b[2] / M[2][2]
                var c1 = (b[1] - M[1][2]*c2) / M[1][1]
                var c0 = (b[0] - M[0][1]*c1 - M[0][2]*c2) / M[0][0]
                if flight.count < 4 { c2 = 0; c1 = (ys.last! - ys.first!) / max(n-1, 1); c0 = ys.first! }
                return (c0, c1, c2)
            }
            let (ax0, ax1, ax2) = polyfit2(flight.map(\.x))
            let (ay0, ay1, ay2) = polyfit2(flight.map(\.y))
            let gate = max(6 * r0, 30.0)
            var junk: [Int] = []
            for i in 0..<flight.count {
                let px = ax0 + ax1 * t[i] + ax2 * t[i] * t[i]
                let py = ay0 + ay1 * t[i] + ay2 * t[i] * t[i]
                if hypot(flight[i].x - px, flight[i].y - py) > gate { junk.append(flight[i].fi) }
            }
            if !junk.isEmpty {
                flight.removeAll { junk.contains($0.fi) }
                frameObs.removeAll { junk.contains($0.frameIndex) && $0.isFlight }
                notes.append("line-clean removed f\(junk)")
            }
        }

        // Ballistic gap fill: flight is linear over 1-2 frames at 240fps, so a hole between
        // two REAL sightings is interpolable within the label tolerance (1.5r). Confidence
        // 0.65 clears V2Primary's rescue filter (>0.61) but stays below real picks.
        do {
            let fl = frameObs.filter(\.isFlight).sorted { $0.frameIndex < $1.frameIndex }
            var gapFills: [V2FrameObservation] = []
            // ≤6-frame holes: 25ms of unobserved arc curves sub-centimeter at ball speeds —
            // linear interpolation stays inside the 1.5r label tolerance. Endpoints are
            // color+motion-vetted real sightings, which is what makes this honest.
            for (a, b) in zip(fl, fl.dropFirst()) where b.frameIndex - a.frameIndex > 1 && b.frameIndex - a.frameIndex <= 7 {
                for fi in (a.frameIndex + 1)..<b.frameIndex where !frameObs.contains(where: { $0.frameIndex == fi }) {
                    let u = Double(fi - a.frameIndex) / Double(b.frameIndex - a.frameIndex)
                    gapFills.append(V2FrameObservation(
                        frameIndex: fi,
                        cxNorm: a.cxNorm + (b.cxNorm - a.cxNorm) * u,
                        cyNorm: a.cyNorm + (b.cyNorm - a.cyNorm) * u,
                        diaNorm: a.diaNorm + (b.diaNorm - a.diaNorm) * u,
                        confidence: 0.65, isFlight: true))
                }
            }
            if !gapFills.isEmpty {
                frameObs.append(contentsOf: gapFills)
                frameObs.sort { $0.frameIndex < $1.frameIndex }
                notes.append("gap-filled \(gapFills.count) flight frame(s)")
            }
        }

        // ── metric features (port of metrics_kfold.features_from_track)
        let rLockSub = restRadii.isEmpty ? r0 : restRadii.sorted()[restRadii.count / 2]
        var pts = Array(flight.prefix(5))
        // club-sized points can't enter the fit (far-field radius filter). The near-lock
        // exemption is for motion-smeared radius reads, NOT for the ball+club merged blob
        // at impact+1 — a merged read is fat (≥1.8 rLock) and anchors the whole fit at a
        // half-club position, so it's skipped: two clean later points beat three with a
        // poisoned first point.
        let radiusFiltered = pts.filter {
            $0.r <= rLockSub * 1.35
                // 1.8 admitted a 1.68-rLock merged ball+club read at impact+1 (measured:
                // 146.6 vs TT 91.1 mph on 082923 — the yellow boost surfaces the merge
                // frame, its dh area is club-fat). Heavy-drop 2-sighting shots keep the
                // pair via the fallback below.
                || (hypot($0.x - lock.x, $0.y - lock.y) <= rLockSub * 6 && $0.r <= rLockSub * 1.5)
        }
        // Heavy-drop captures leave exactly TWO airborne sightings, and the far one is
        // motion-smeared so its radius reads club-fat — the far-field filter then starved
        // the fit down to one point on shots the tracker followed perfectly (the Simulate
        // Shot sample: ball label-perfect at f18+f19, V2 withheld). With only two sightings
        // total, keep the pair; the 2-point confidence gate below (lock/p1/p2 speed
        // agreement ≤ 25%) plus the physics clamp decide trust instead of the radius.
        pts = (pts.count == 2 && radiusFiltered.count < 2) ? pts : radiusFiltered
        // no steep descent in the first visible frames (follow-through grabs)
        while pts.count >= 2 {
            let dx = pts[1].x - pts[0].x, dy = pts[1].y - pts[0].y
            if dy > abs(dx) * 1.732 { pts.remove(at: 1) } else { break }
        }
        guard pts.count >= 2, pts.last!.t > pts.first!.t else {
            // Name the evidence: which frames the sequential tracker actually caught and
            // what filtering left — "withheld" without this was undebuggable in the field.
            let raw = flight.map { String(format: "f%d(r%.1f)", $0.fi, $0.r) }.joined(separator: " ")
            return V2Output(ballSpeedMph: nil, clubSpeedMph: nil, vlaDegrees: nil,
                            confident: false, flightPointCount: pts.count,
                            notes: notes + ["withheld: <2 usable flight points [flight: \(raw.isEmpty ? "none" : raw) → usable \(pts.count), rLock \(String(format: "%.1f", rLockSub))]"],
                            impactFrameIndex: impact, frameObservations: frameObs,
                            clubObservations: clubObs)
        }

        func lineFit(_ P: [FlightPt]) -> (vx: Double, vy: Double, x0: Double, y0: Double, t0: Double, chiMax: Double) {
            let t0 = P[0].t
            let n = Double(P.count)
            var st = 0.0, sx = 0.0, sy = 0.0, stt = 0.0, stx = 0.0, sty = 0.0
            for p in P {
                let dt = p.t - t0
                st += dt; sx += p.x; sy += p.y
                stt += dt * dt; stx += dt * p.x; sty += dt * p.y
            }
            let denom = max(n * stt - st * st, 1e-9)
            let vx = (n * stx - st * sx) / denom
            let vy = (n * sty - st * sy) / denom
            let x0 = (sx - vx * st) / n
            let y0 = (sy - vy * st) / n
            var chiMax = 0.0
            for p in P {
                let dt = p.t - t0
                chiMax = max(chiMax, hypot(p.x - (x0 + vx * dt), p.y - (y0 + vy * dt)) / 0.6)
            }
            return (vx, vy, x0, y0, t0, chiMax)
        }
        var fit = lineFit(pts)
        if pts.count >= 4 && fit.chiMax > 4 / 0.6 {
            // drop the worst residual point once (robust trim)
            var worstI = 0; var worstR = -1.0
            for (i, p) in pts.enumerated() {
                let dt = p.t - fit.t0
                let r = hypot(p.x - (fit.x0 + fit.vx * dt), p.y - (fit.y0 + fit.vy * dt))
                if r > worstR { worstR = r; worstI = i }
            }
            pts.remove(at: worstI)
            fit = lineFit(pts)
        }
        let vPx = hypot(fit.vx, fit.vy)
        let ang = atan2(-fit.vy, -fit.vx) * 180 / .pi
        let mPerPx = 0.04267 / 2 / max(rLockSub, 2)
        let vPhysMps = vPx * mPerPx
        guard vPhysMps >= 3.0 && vPhysMps <= 105.0 else {
            return V2Output(ballSpeedMph: nil, clubSpeedMph: nil, vlaDegrees: nil,
                            confident: false, flightPointCount: pts.count,
                            notes: notes + [String(format: "withheld: implausible physics %.1f m/s", vPhysMps)],
                            impactFrameIndex: impact, frameObservations: frameObs,
                            clubObservations: clubObs)
        }

        // contact instant: closest approach of the flight line to the lock
        let v2 = fit.vx * fit.vx + fit.vy * fit.vy
        var tContact: Double? = nil
        if v2 > 1e-9 {
            tContact = fit.t0 + ((lock.x - fit.x0) * fit.vx + (lock.y - fit.y0) * fit.vy) / v2
        }
        var firstStep = vPx
        if let tc = tContact, pts[0].t - tc > 2e-3 {
            firstStep = hypot(pts[0].x - lock.x, pts[0].y - lock.y) / (pts[0].t - tc)
        }
        var v2pt = vPx
        if pts.count >= 2, pts[1].t > pts[0].t {
            v2pt = hypot(pts[1].x - pts[0].x, pts[1].y - pts[0].y) / (pts[1].t - pts[0].t)
        }
        let rPxMed = pts.map(\.r).sorted()[pts.count / 2]
        var shrink = 0.0
        if pts.count >= 2, pts.last!.t > pts.first!.t {
            shrink = (pts.first!.r - pts.last!.r) / (pts.last!.t - pts.first!.t)
        }

        // club speed: arc fit at contact (smash-gated only when the ball is trustworthy)
        var clubVpx = 0.0
        if clubPts.count >= 2 {
            clubVpx = arcSpeed(clubPts, tContact: tContact) ?? 0
            let trustworthy = pts.count >= 2 && fit.chiMax <= 2.5
            if clubVpx > 0 && trustworthy && !(0.95...1.62).contains(vPx / clubVpx) {
                notes.append("club_v zeroed (smash gate)")
                clubVpx = 0
            }
        }

        // features (order = metrics_kfold.FEATS)
        let x: [Double] = [vPx, ang, rPxMed, Double(pts.count), firstStep, clubVpx,
                           vPhysMps, v2pt, shrink, rLockSub,
                           v2pt * mPerPx, sin(ang * .pi / 180), cos(ang * .pi / 180)]
        var ballMph = models.ball_head.predict(x)
        let physMph = v2pt * mPerPx * 2.23694
        if let clamp = models.ball_head.clamp, clamp.count == 2 {
            ballMph = max(clamp[0] * physMph, min(clamp[1] * physMph, ballMph))
        }
        let vla = models.vla_head.predict(x + [ballMph])
        var clubMph: Double? = nil
        if clubVpx > 0 {
            if let head = models.club_head {
                clubMph = head.predict(x + [ballMph])
            } else {
                clubMph = clubVpx * mPerPx * 2.23694
            }
        }

        // confidence: fit residuals within noise, or 2-point speed agreement
        let agree2pt = abs(v2pt - firstStep) / max(v2pt, 1e-6)
        let confident = (pts.count >= 3 && fit.chiMax <= 2.5) || (pts.count == 2 && agree2pt <= 0.25)
        notes.append(String(format: "v=%.0fpx/s phys=%.1fmph pts=%d chi=%.1f agree=%.2f",
                            vPx, physMph, pts.count, fit.chiMax, agree2pt))

        // ── V3 heads (July 18): speed+VLA ridge trained on CORRECTED TT pairs over V3
        // tracks. Fixes both _614 failure modes at once: the old ball_head lifting a
        // 62mph physics read to 87 (TT: 70.6), and growth-only VLA doubling on pulled
        // shots because HLA-approach growth reads as height (Noah's FOV-coupling
        // insight — the head carries r_excess/hla_proxy features for exactly that).
        var ballMphFinal = ballMph
        var vlaFinal = vla
        if let s0 = sig, s0.color != .white, flight.count >= 3,
           let heads = v3Heads {
            let use = Array(flight.prefix(6))
            let t0 = use[0].t
            let T = use.map { $0.t - t0 }
            let vxs = polyfit1(T, use.map(\.x))
            let vys = polyfit1(T, use.map(\.y))
            let rsl = polyfit1(T, use.map(\.r))
            // rLockSub is dh-based and half-blind to yellow (read ~2px on a 5.4px ball →
            // v_mps inflated 2.7x → the head extrapolated 194mph on _614). The V3
            // signature radius is measured on the yellowness channel — the right scale.
            let r0m = s0.restRadius
            V2Engine.sessionR0s.append(r0m)
            if V2Engine.sessionR0s.count > 40 { V2Engine.sessionR0s.removeFirst() }
            let sorted0 = V2Engine.sessionR0s.sorted()
            let r0sess = sorted0[sorted0.count / 2]
            let vpx = (vxs * vxs + vys * vys).squareRoot()
            var curve = 0.0
            if use.count >= 4 {
                curve = polyfit2a(T, use.map(\.y))
            }
            let feat: [String: Double] = [
                "v_px": vpx, "vx": vxs, "vy": vys,
                "pxang": atan2(-vys, -vxs) * 180 / .pi,
                "r_slope": rsl,
                "r_excess": rsl - (-abs(vxs) * r0m / 360.0),
                "r_norm": rsl / max(abs(vxs), 1.0) * 100.0,
                "hla_proxy": abs(rsl) / max(vpx, 1.0) * 100.0,
                "v_mps": vpx * 0.04267 / (2 * r0m),
                "r0": r0m, "r1": use[0].r, "y0": use[0].y,
                "npts": Double(use.count), "curve": curve,
                "r0_sess": r0sess, "r0_rel": r0m / max(r0sess, 1e-6)
            ]
            func apply(_ h: V3Head) -> Double {
                var z = h.intercept
                for i in 0..<h.features.count {
                    let x = feat[h.features[i]] ?? 0
                    z += (x - h.mu[i]) / h.sd[i] * h.w[i]
                }
                return z
            }
            notes.append("v3feat: " + heads.speed.features.map {
                String(format: "%@=%.2f", $0, feat[$0] ?? -999) }.joined(separator: " "))
            let spd = min(max(apply(heads.speed), heads.speedClamp.0), heads.speedClamp.1)
            let vl = min(max(apply(heads.vla), heads.vlaClamp.0), heads.vlaClamp.1)
            // BLEND (July 18, on corrected + realigned pairs, n=113): the physics path
            // and the head fail differently — physics under-reads blurred fast shots,
            // the head over-smooths clean ones. Their MEAN kills the tail without
            // giving up the median: jul17 3.5% median, 3/53 over 10%, max 16% (was
            // max 50%+ for either alone). VLA takes the head outright (2.2 vs 3.4 deg,
            // pull-side bias eliminated).
            ballMphFinal = (ballMph + spd) / 2
            vlaFinal = vl
            notes.append(String(format: "v3heads: speed %.1f blend %.1f vla %.1f",
                                spd, ballMphFinal ?? 0, vl))
        }

        return V2Output(ballSpeedMph: ballMphFinal, clubSpeedMph: clubMph,
                        vlaDegrees: vlaFinal, confident: confident,
                        flightPointCount: pts.count, notes: notes,
                        impactFrameIndex: impact, frameObservations: frameObs,
                        clubObservations: clubObs)
    }

    // MARK: V3 heads (speed/VLA ridge over V3-track features)

    struct V3Head {
        let features: [String]
        let mu: [Double], sd: [Double], w: [Double]
        let intercept: Double
    }
    struct V3Heads {
        let speed: V3Head, vla: V3Head
        let speedClamp: (Double, Double), vlaClamp: (Double, Double)
    }
    static var sessionR0s: [Double] = []
    static let v3Heads: V3Heads? = {
        guard let url = Bundle.main.url(forResource: "v3_heads", withExtension: "json", subdirectory: "Models")
                    ?? Bundle.main.url(forResource: "v3_heads", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func head(_ d: [String: Any]?) -> V3Head? {
            guard let d, let f = d["features"] as? [String],
                  let mu = d["mu"] as? [Double], let sd = d["sd"] as? [Double],
                  let w = d["w"] as? [Double], let b = d["intercept"] as? Double else { return nil }
            return V3Head(features: f, mu: mu, sd: sd, w: w, intercept: b)
        }
        guard let sp = head(j["speed"] as? [String: Any]),
              let vl = head(j["vla"] as? [String: Any]) else { return nil }
        let sc = j["speed_clamp"] as? [Double] ?? [10, 210]
        let vc = j["vla_clamp"] as? [Double] ?? [0.5, 55]
        return V3Heads(speed: sp, vla: vl, speedClamp: (sc[0], sc[1]), vlaClamp: (vc[0], vc[1]))
    }()

    private static func polyfit1(_ t: [Double], _ y: [Double]) -> Double {
        let n = Double(t.count)
        let st = t.reduce(0, +), sy = y.reduce(0, +)
        var stt = 0.0, sty = 0.0
        for i in 0..<t.count { stt += t[i] * t[i]; sty += t[i] * y[i] }
        let d = n * stt - st * st
        return abs(d) < 1e-12 ? 0 : (n * sty - st * sy) / d
    }

    private static func polyfit2a(_ t: [Double], _ y: [Double]) -> Double {
        // quadratic coefficient via least squares (small n)
        let n = Double(t.count)
        var s1 = 0.0, s2 = 0.0, s3 = 0.0, s4 = 0.0, sy = 0.0, sty = 0.0, st2y = 0.0
        for i in 0..<t.count {
            let x = t[i], v = y[i]
            s1 += x; s2 += x*x; s3 += x*x*x; s4 += x*x*x*x
            sy += v; sty += x*v; st2y += x*x*v
        }
        var M = [[n, s1, s2, sy], [s1, s2, s3, sty], [s2, s3, s4, st2y]]
        for c in 0..<3 {
            let piv = M[c][c]
            guard abs(piv) > 1e-12 else { return 0 }
            for r in (c+1)..<3 {
                let f = M[r][c] / piv
                for k in c..<4 { M[r][k] -= f * M[c][k] }
            }
        }
        return abs(M[2][2]) < 1e-12 ? 0 : M[2][3] / M[2][2]
    }

    // MARK: Subpixel + rescue helpers
    // (see V2PrimaryTrack at end of file for the integration that makes this engine the
    // app's primary per-frame ball track)

    private static func subpixelCenter(_ pl: Planes, cx: Double, cy: Double, rHint: Double) -> (Double, Double, Double) {
        let W = pl.W, H = pl.H
        let R = Int(max(6, rHint * 2.2))
        let x0 = max(0, Int(cx) - R), x1 = min(W, Int(cx) + R)
        let y0 = max(0, Int(cy) - R), y1 = min(H, Int(cy) + R)
        var tot = 0.0, sx = 0.0, sy = 0.0, area = 0.0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let w = max(0.0, Double(pl.dh[y * W + x]) - 120)
                tot += w; sx += w * Double(x); sy += w * Double(y)
                if w > 30 { area += 1 }
            }
        }
        guard tot >= 1 else { return (cx, cy, rHint) }
        let sr = area >= 6 ? sqrt(area / Double.pi) : rHint
        return (sx / tot, sy / tot, sr)
    }

    /// V3 step 4 (Noah's spec): find the yellow ball with a baseline-subtracted
    /// yellowness mask and DISK-FIT its diameter. Validated offline: 98.9% of labeled
    /// flight points matched, diameter median |err| 0.79px. Returns 360-space (cx, cy, r).
    private static func v3YellowPick(_ pl: Planes, baseYel: [Float], lock: CGPoint,
                                     r0: Double, prev: CGPoint?) -> (Double, Double, Double)? {
        let W = pl.W, H = pl.H
        var mask = [Bool](repeating: false, count: W * H)
        for p in 0..<(W * H) { mask[p] = pl.yel[p] - baseYel[p] >= 70 }
        // the departed ball's residue at the lock reads positive — exclude the disk
        let ex = 1.6 * r0
        for yy in max(0, Int(lock.y - ex))...min(H - 1, Int(lock.y + ex)) {
            for xx in max(0, Int(lock.x - ex))...min(W - 1, Int(lock.x + ex))
            where hypot(Double(xx) - lock.x, Double(yy) - lock.y) <= ex {
                mask[yy * W + xx] = false
            }
        }
        let comps = blobs(mask: mask, planes: pl, motion: nil, src: "v3yel", minArea: 6,
                          connectivity8: true)
        var cands = comps.filter { b in
            b.area <= 2500 && b.cx >= 4 && b.cx <= Double(W) - 4
                && b.cy >= 4 && b.cy <= Double(H) - 4
                && (b.cx - lock.x) <= r0        // forward of the lock (play is -x)
        }
        guard !cands.isEmpty else { return nil }
        let pick: Blob
        if let pv = prev {
            cands.sort { hypot($0.cx - pv.x, $0.cy - pv.y) < hypot($1.cx - pv.x, $1.cy - pv.y) }
            let c = cands[0]
            guard hypot(c.cx - pv.x, c.cy - pv.y) <= max(90.0, r0 * 16) else { return nil }
            pick = c
        } else {
            pick = cands.max(by: { $0.area < $1.area })!
        }
        // disk fit on the diff patch: threshold at half the local peak
        let R = 14
        let x0 = max(0, Int(pick.cx) - R), x1 = min(W, Int(pick.cx) + R)
        let y0 = max(0, Int(pick.cy) - R), y1 = min(H, Int(pick.cy) + R)
        var peak: Float = 0
        for yy in y0..<y1 { for xx in x0..<x1 {
            peak = max(peak, pl.yel[yy * W + xx] - baseYel[yy * W + xx]) } }
        let thr = max(60.0, 0.5 * Double(peak))
        var n = 0.0, sx = 0.0, sy = 0.0
        var pts: [(Double, Double)] = []
        for yy in y0..<y1 { for xx in x0..<x1 {
            if Double(pl.yel[yy * W + xx] - baseYel[yy * W + xx]) >= thr {
                n += 1; sx += Double(xx); sy += Double(yy)
                pts.append((Double(xx), Double(yy)))
            } } }
        guard n >= 4 else { return nil }
        let mx = sx / n, my = sy / n
        // blur-immune radius: MINOR axis of the pixel cloud — a fast ball streaks along
        // its motion during exposure and the area-disk radius inflates, poisoning the
        // depth scale (measured: 139 mph driver read as 78). Perpendicular extent holds.
        var cxx = 0.0, cyy = 0.0, cxy = 0.0
        for (px, py) in pts {
            cxx += (px - mx) * (px - mx); cyy += (py - my) * (py - my)
            cxy += (px - mx) * (py - my)
        }
        cxx /= n; cyy /= n; cxy /= n
        let tr_ = cxx + cyy
        let det = cxx * cyy - cxy * cxy
        let lamMin = tr_ / 2 - (max(tr_ * tr_ / 4 - det, 0)).squareRoot()
        let rMinor = 2.0 * (max(lamMin, 0.25)).squareRoot()
        let rArea = (n / Double.pi).squareRoot()
        return (mx, my, min(rArea, rMinor))
    }

    /// July 17: re-measure a 360-space pick on the frame's 720px copy. Detection stays
    /// in the validated 360 space; only the MEASUREMENT (centroid + radius, the inputs
    /// to speed and VLA) gets the 2x precision. Returns 360-space coordinates.
    private static func refineOnHiRes(_ frame: AnalyzedShotFrame, sx: Double, sy: Double,
                                      sr: Double, turfHue: Int) -> (Double, Double, Double)? {
        guard let hi = frame.originalFrame.hiRes, let cg = hi.cgImage else { return nil }
        let scale = Double(cg.width) / 360.0
        guard scale > 1.2 else { return nil }
        let R = max(14.0, sr * scale * 3)
        let cx = sx * scale, cy = sy * scale
        let crop = CGRect(x: cx - R, y: cy - R, width: 2 * R, height: 2 * R)
            .intersection(CGRect(x: 0, y: 0, width: Double(cg.width), height: Double(cg.height)))
        guard crop.width > 8, crop.height > 8, let sub = cg.cropping(to: crop),
              let pl = planes(from: UIImage(cgImage: sub), turfOverride: turfHue) else { return nil }
        let (rx, ry, rr) = subpixelCenter(pl, cx: cx - crop.minX, cy: cy - crop.minY,
                                          rHint: sr * scale)
        return ((rx + Double(crop.minX)) / scale, (ry + Double(crop.minY)) / scale, rr / scale)
    }

    private static func subpixelRadius(_ pl: Planes, cx: Double, cy: Double, rHint: Double) -> Double {
        subpixelCenter(pl, cx: cx, cy: cy, rHint: rHint).2
    }

    private static func rescueAt(_ pl: Planes, x px: Double, y py: Double, rHint: Double) -> Blob? {
        let W = pl.W, H = pl.H
        let R = Int(max(18, rHint * 4))
        let x0 = max(0, Int(px) - R), x1 = min(W, Int(px) + R)
        let y0 = max(0, Int(py) - R), y1 = min(H, Int(py) + R)
        guard x1 - x0 > 6, y1 - y0 > 6 else { return nil }
        let w = x1 - x0, h = y1 - y0
        var mask = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                mask[y * w + x] = pl.dh[(y + y0) * W + (x + x0)] >= 140
            }
        }
        morph(&mask, W: w, H: h, k: 5, dilate: true)
        morph(&mask, W: w, H: h, k: 5, dilate: false)
        var visited = [Bool](repeating: false, count: w * h)
        var best: (Double, Blob)? = nil
        for start in 0..<(w * h) where mask[start] && !visited[start] {
            visited[start] = true
            var queue = [start]; var head = 0
            var sx = 0.0, sy = 0.0, n = 0.0
            while head < queue.count {
                let p = queue[head]; head += 1
                let xx = p % w, yy = p / w
                sx += Double(xx); sy += Double(yy); n += 1
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nx = xx + dx, ny = yy + dy
                    guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                    let np = ny * w + nx
                    if mask[np] && !visited[np] { visited[np] = true; queue.append(np) }
                }
            }
            guard n >= 10 else { continue }
            let r = sqrt(n / Double.pi)
            guard r >= 2.0, r <= 24 else { continue }
            let cx = sx / n + Double(x0), cy = sy / n + Double(y0)
            let d = hypot(cx - px, cy - py)
            if d <= rHint * 2.5, best == nil || d < best!.0 {
                best = (d, Blob(src: "rescue", area: n, circ: 0.5, r: r, cx: cx, cy: cy,
                                w: Int(r * 2), h: Int(r * 2), theta: 0, elong: 0.5,
                                border: false, mot: 0, dhMean: 200, vMean: 200))
            }
        }
        return best?.1
    }

    private static func arcSpeed(_ pts: [(t: Double, x: Double, y: Double)], tContact: Double?) -> Double? {
        let P = pts.sorted { $0.t < $1.t }
        guard P.count >= 2 else { return nil }
        if P.count >= 3 {
            // Kasa circle fit
            var a11 = 0.0, a12 = 0.0, a13 = 0.0, a22 = 0.0, a23 = 0.0, a33 = Double(P.count)
            var b1 = 0.0, b2 = 0.0, b3 = 0.0
            for p in P {
                let z = p.x * p.x + p.y * p.y
                a11 += 4 * p.x * p.x; a12 += 4 * p.x * p.y; a13 += 2 * p.x
                a22 += 4 * p.y * p.y; a23 += 2 * p.y
                b1 += 2 * p.x * z; b2 += 2 * p.y * z; b3 += z
            }
            // solve 3x3 (a, c, d)
            let m = [[a11, a12, a13], [a12, a22, a23], [a13, a23, a33]]
            let bb = [b1, b2, b3]
            if let sol = solve3(m, bb) {
                let (ax, cy2, d) = (sol[0], sol[1], sol[2])
                let R = sqrt(max(d + ax * ax + cy2 * cy2, 1e-6))
                if R >= 20 && R <= 5000 {
                    var th = P.map { atan2($0.y - cy2, $0.x - ax) }
                    for i in 1..<th.count {                          // unwrap
                        while th[i] - th[i - 1] > .pi { th[i] -= 2 * .pi }
                        while th[i] - th[i - 1] < -.pi { th[i] += 2 * .pi }
                    }
                    let t0 = P[0].t
                    var st = 0.0, sth = 0.0, stt = 0.0, stth = 0.0
                    let n = Double(P.count)
                    for (i, p) in P.enumerated() {
                        let dt = p.t - t0
                        st += dt; sth += th[i]; stt += dt * dt; stth += dt * th[i]
                    }
                    let denom = max(n * stt - st * st, 1e-12)
                    let om = (n * stth - st * sth) / denom
                    return abs(om) * R
                }
            }
        }
        let (p1, p2) = (P.first!, P.last!)
        guard p2.t > p1.t else { return nil }
        return hypot(p2.x - p1.x, p2.y - p1.y) / (p2.t - p1.t)
    }

    private static func solve3(_ m: [[Double]], _ b: [Double]) -> [Double]? {
        var a = m.map { $0 }
        var v = b
        for i in 0..<3 {
            var piv = i
            for r in (i + 1)..<3 where abs(a[r][i]) > abs(a[piv][i]) { piv = r }
            if abs(a[piv][i]) < 1e-12 { return nil }
            a.swapAt(i, piv); v.swapAt(i, piv)
            for r in 0..<3 where r != i {
                let f = a[r][i] / a[i][i]
                for c in i..<3 { a[r][c] -= f * a[i][c] }
                v[r] -= f * v[i]
            }
        }
        return [v[0] / a[0][0], v[1] / a[1][1], v[2] / a[2][2]]
    }
}

// MARK: - V2-primary track integration
//
// Promotes V2's label-trained per-frame track (97.4% ball detection on the 2126-label
// archive vs 86% for the legacy rule scanner) to be THE ball track the app displays and
// measures from. The legacy scanner remains the putter path and the fallback when V2 is
// unavailable or finds no flight. ONE shared entry point for the live pipeline and the
// replay harness — they must never diverge again.
enum V2PrimaryTrack {

    /// Universal ballistic gap fill for the FINAL track (V2 or legacy): 1-2 frame holes
    /// between real post-impact sightings are linear at 240fps. Marked wasInterpolated
    /// with damped confidence so quality gates can tell.
    static func gapFill(_ map: [Int: ShotBallObservation],
                        impactIndex: Int,
                        frames: [AnalyzedShotFrame]) -> [Int: ShotBallObservation] {
        var out = map
        let flight = map.values
            .filter { $0.frameIndex > impactIndex && $0.centerX != nil && $0.centerY != nil }
            .sorted { $0.frameIndex < $1.frameIndex }
        let frameByIdx = Dictionary(uniqueKeysWithValues: frames.map { ($0.frameIndex, $0) })
        var filled = 0
        for (a, b) in zip(flight, flight.dropFirst()) where b.frameIndex - a.frameIndex > 1 && b.frameIndex - a.frameIndex <= 3 {
            for fi in (a.frameIndex + 1)..<b.frameIndex where out[fi]?.centerX == nil {
                guard let f = frameByIdx[fi],
                      let ax = a.centerX, let ay = a.centerY,
                      let bx = b.centerX, let by = b.centerY else { continue }
                let u = CGFloat(fi - a.frameIndex) / CGFloat(b.frameIndex - a.frameIndex)
                let dia: CGFloat? = (a.finalDiameter ?? a.diameter).flatMap { da in
                    (b.finalDiameter ?? b.diameter).map { db in da + (db - da) * u }
                }
                out[fi] = ShotBallObservation(
                    frameIndex: fi, timestamp: f.timestamp, relativeTime: f.relativeTime,
                    centerX: ax + (bx - ax) * u, centerY: ay + (by - ay) * u,
                    diameter: dia, candidateDiameter: dia, refinedDiameter: nil,
                    smoothedDiameter: nil, finalDiameter: dia,
                    confidence: min(a.confidence, b.confidence) * 0.85,
                    wasInterpolated: true, debugReason: "ballistic_gap_fill",
                    diameterDebugReason: nil, maskWhitePixelCount: 0,
                    bboxHeightNorm: nil)
                filled += 1
            }
        }
        if filled > 0 { print("[ShotValidation] ballistic gap fill: +\(filled) flight frame(s)") }
        return out
    }

    struct Result {
        let observations: [Int: ShotBallObservation]
        let impactFrameIndex: Int
        let v2: V2Output?
        let active: Bool
    }

    static func run(prelimFrames: [AnalyzedShotFrame],
                    legacyObservations: [Int: ShotBallObservation],
                    lockedBallRect: CGRect?,
                    legacyImpactIndex: Int,
                    impactHint: Int,
                    isPutterMode: Bool) -> Result {
        // Putter shots keep the legacy tracker: V2's scorer and heads were trained on full
        // swings and its physics gates start at 3 m/s. tc_v2_metrics is the shared kill
        // switch for the whole V2 engine.
        guard !isPutterMode,
              UserDefaults.standard.object(forKey: "tc_v2_metrics") as? Bool ?? true,
              V2Engine.isAvailable else {
            return Result(observations: legacyObservations,
                          impactFrameIndex: legacyImpactIndex, v2: nil, active: false)
        }
        let v2Try = V2Engine.run(frames: prelimFrames,
                                 lockedBallRect: lockedBallRect,
                                 impactHint: impactHint)
        guard let v2 = v2Try, v2.frameObservations.contains(where: { $0.isFlight }) else {
            // Keep the engine output even when inactive: its notes say WHY zero flight
            // points came back (was undebuggable — shots 945/726 fell to legacy junk
            // with no trace).
            return Result(observations: legacyObservations,
                          impactFrameIndex: legacyImpactIndex, v2: v2Try, active: false)
        }

        let byIdx = Dictionary(uniqueKeysWithValues: prelimFrames.map { ($0.frameIndex, $0) })
        // diaNorm is width-normalized (legacy convention); bbox height wants height-normalized.
        let aspect: CGFloat = {
            guard let img = prelimFrames.first?.originalFrame.image.size, img.height > 0 else { return 16.0 / 9.0 }
            return img.width / img.height
        }()

        var merged: [Int: ShotBallObservation] = [:]
        for o in v2.frameObservations {
            guard let f = byIdx[o.frameIndex] else { continue }
            // Rescue-sourced picks measured 1 match vs 13 wrong on the labeled archive —
            // they stay internal to V2's own fit but never enter the displayed track.
            if o.isFlight, o.confidence <= 0.61 { continue }
            merged[o.frameIndex] = ShotBallObservation(
                frameIndex: o.frameIndex,
                timestamp: f.timestamp,
                relativeTime: f.relativeTime,
                centerX: CGFloat(o.cxNorm),
                centerY: CGFloat(o.cyNorm),
                diameter: CGFloat(o.diaNorm),
                candidateDiameter: CGFloat(o.diaNorm),
                finalDiameter: CGFloat(o.diaNorm),
                confidence: o.confidence,
                wasInterpolated: false,
                debugReason: o.isFlight ? "v2_flight" : "v2_rest",
                diameterDebugReason: "v2_subpixel",
                bboxHeightNorm: CGFloat(o.diaNorm) * aspect
            )
        }

        // Legacy fills only frames V2 has no opinion on, and only where it AGREES with V2's
        // geometry: pre-impact picks must sit at V2's rest position. Post-impact legacy hits
        // are NOT adopted — the sweep showed their failure mode (glare junk) is concentrated
        // exactly on the frames V2 skips, and a wrong point is worse than a miss.
        let rests = v2.frameObservations.filter { !$0.isFlight && $0.frameIndex <= v2.impactFrameIndex }
        if !rests.isEmpty {
            let mx = median(rests.map(\.cxNorm))
            let my = median(rests.map(\.cyNorm))
            let md = median(rests.map(\.diaNorm))
            // Includes the impact frame itself: V2 defines impact as the frame BEFORE the
            // first moved blob, so the ball is still at rest there — excluding it cost ~64
            // labeled matches across the archive (one boundary frame per shot) while saving
            // far fewer boundary errors.
            for (idx, obs) in legacyObservations where merged[idx] == nil && idx <= v2.impactFrameIndex {
                guard let x = obs.centerX, let y = obs.centerY else { continue }
                if hypot(Double(x) - mx, Double(y) - my) <= md * 1.5 {
                    merged[idx] = obs
                }
            }
        }

        // Late-flight continuation: V2's sequential tracker exits after 2 misses, but on
        // slow shots the legacy tracker keeps following the visible ball for many more
        // frames (measured: whole slow-roll tails lost). Adopt legacy POST hits after V2's
        // last flight frame — but only when they continue V2's own geometry: monotone
        // progress along the lock→last-flight direction, inside the same perpendicular
        // cone the legacy path gate uses, and ball-plausible in size.
        let flights = v2.frameObservations.filter(\.isFlight).sorted { $0.frameIndex < $1.frameIndex }
        if let lastFlight = flights.last, !rests.isEmpty {
            let lx = median(rests.map(\.cxNorm)), ly = median(rests.map(\.cyNorm))
            let md = median(rests.map(\.diaNorm))
            let dx0 = lastFlight.cxNorm - lx, dy0 = lastFlight.cyNorm - ly
            let len = max(hypot(dx0, dy0), 1e-6)
            let ux = dx0 / len, uy = dy0 / len
            var lastProgress = len
            for idx in legacyObservations.keys.sorted() where idx > lastFlight.frameIndex {
                guard merged[idx] == nil, let obs = legacyObservations[idx],
                      let x = obs.centerX, let y = obs.centerY,
                      let d = obs.finalDiameter ?? obs.diameter else { continue }
                let px = Double(x) - lx, py = Double(y) - ly
                let progress = px * ux + py * uy
                let perp = abs(px * uy - py * ux)
                guard progress > lastProgress - 0.012,
                      perp <= max(0.06, 0.35 * progress),
                      (0.4...2.5).contains(Double(d) / md) else { continue }
                lastProgress = max(lastProgress, progress)
                merged[idx] = obs
            }
        }

        // Keep legacy MISS records (nil center) for frames with no sighting at all — they
        // carry the per-frame failure reason into the review overlay and replay JSON.
        for (idx, obs) in legacyObservations where merged[idx] == nil && obs.centerX == nil {
            merged[idx] = obs
        }

        return Result(observations: merged, impactFrameIndex: v2.impactFrameIndex,
                      v2: v2, active: true)
    }

    private static func median(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return 0 }
        let s = v.sorted()
        return s[s.count / 2]
    }
}

// MARK: - Club union tracker (July 17 port of tools/experimental/club_union_scorer.py)
//
// 5-mask union candidates + 19-feature GBT + kinematic DP chain with Noah's priors
// (comes from behind the ball, monotonically closes, plausible step, terminates at
// the ball). Validated offline at 83.4% window coverage vs the 34.3% shipped path.
// Runs on 360px-wide downscales — that's the resolution the model was trained at,
// and it caps the per-frame cost of the extra masks.
extension V2Engine {

    struct ClubUnionModel: Decodable {
        let stumps: [[Double]]
        let base: Double
    }

    private static let clubUnionModel: ClubUnionModel? = {
        guard let url = Bundle.main.url(forResource: "club_union_gbt", withExtension: "json",
                                        subdirectory: "Models")
                ?? Bundle.main.url(forResource: "club_union_gbt", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let m = try? JSONDecoder().decode(ClubUnionModel.self, from: data) else {
            print("[ClubUnion] model json missing — union tracker disabled")
            return nil
        }
        return m
    }()

    private static func downscaled(_ image: UIImage, toWidth w: Int) -> UIImage {
        // Archive replays are ALREADY 360px — resampling them blurs gradients (the Sobel
        // mask starves) and rounds the height, shifting every pixel the model sees. Only
        // touch genuinely larger (live 1920px) frames.
        if Int(image.size.width) <= w { return image }
        let h = max(1, Int(CGFloat(w) * image.size.height / max(image.size.width, 1)))
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        }
    }

    /// 3x3 Sobel magnitude over luma.
    private static func sobelMag(_ luma: [Float], W: Int, H: Int) -> [Float] {
        var out = [Float](repeating: 0, count: W * H)
        for y in 1..<(H - 1) {
            for x in 1..<(W - 1) {
                let p = y * W + x
                let gx = -luma[p-W-1] - 2*luma[p-1] - luma[p+W-1]
                       + luma[p-W+1] + 2*luma[p+1] + luma[p+W+1]
                let gy = -luma[p-W-1] - 2*luma[p-W] - luma[p-W+1]
                       + luma[p+W-1] + 2*luma[p+W] + luma[p+W+1]
                out[p] = (gx*gx + gy*gy).squareRoot()
            }
        }
        return out
    }

    /// Grayscale top-hat: luma − open9(luma), separable min/max.
    private static func tophat(_ luma: [Float], W: Int, H: Int) -> [Float] {
        func runMin(_ src: [Float], horizontal: Bool) -> [Float] {
            var dst = [Float](repeating: 0, count: W * H)
            let r = 4
            for y in 0..<H {
                for x in 0..<W {
                    var m: Float = .greatestFiniteMagnitude
                    for d in -r...r {
                        let xx = horizontal ? x + d : x
                        let yy = horizontal ? y : y + d
                        if xx >= 0, xx < W, yy >= 0, yy < H { m = min(m, src[yy*W+xx]) }
                    }
                    dst[y*W+x] = m
                }
            }
            return dst
        }
        func runMax(_ src: [Float], horizontal: Bool) -> [Float] {
            var dst = [Float](repeating: 0, count: W * H)
            let r = 4
            for y in 0..<H {
                for x in 0..<W {
                    var m: Float = -.greatestFiniteMagnitude
                    for d in -r...r {
                        let xx = horizontal ? x + d : x
                        let yy = horizontal ? y : y + d
                        if xx >= 0, xx < W, yy >= 0, yy < H { m = max(m, src[yy*W+xx]) }
                    }
                    dst[y*W+x] = m
                }
            }
            return dst
        }
        let opened = runMax(runMax(runMin(runMin(luma, horizontal: true), horizontal: false),
                                   horizontal: true), horizontal: false)
        var out = [Float](repeating: 0, count: W * H)
        for p in 0..<(W * H) { out[p] = luma[p] - opened[p] }
        return out
    }

    struct UnionCand {
        var cx: Double, cy: Double, a: Double, w: Int, h: Int
        var elong: Double, mot: Double, dh: Double, v: Double
        var hue: Double, sat: Double, grad: Double, dline: Double
        var border: Bool, agree: Int, srcIdx: Int   // O,G,T,M,B = 0..4
        var p: Double = 0
    }

    /// Candidates for one frame (mirrors python union_cands, incl. shaft-line proxy).
    private static func unionCands(planes pl: Planes, gained: Planes, base: [Float]) -> [UnionCand] {
        let W = pl.W, H = pl.H
        var mot = [Float](repeating: 0, count: W * H)
        for p in 0..<(W * H) { mot[p] = abs(pl.luma[p] - base[p]) }
        let grad = sobelMag(pl.luma, W: W, H: H)
        let th = tophat(pl.luma, W: W, H: H)

        var masks: [(Int, [Bool])] = []
        var mO = [Bool](repeating: false, count: W * H)
        var mG = mO, mT = mO, mM = mO, mB = mO
        for p in 0..<(W * H) {
            mO[p] = grad[p] >= 60 && mot[p] >= 10
            mG[p] = mot[p] >= 35
            mT[p] = th[p] >= 25 && mot[p] >= 10
            mM[p] = gained.dh[p] >= 160
            mB[p] = pl.dh[p] >= 120
        }
        for (i, var m) in [mO, mG, mT, mM, mB].enumerated() {
            openClose(&m, W: W, H: H, openK: 3, closeK: 5)
            masks.append((i, m))
        }

        // shaft-line proxy: long thin blobs in edges*mot mask → principal-axis endpoints
        var edgeMask = [Bool](repeating: false, count: W * H)
        for p in 0..<(W * H) { edgeMask[p] = grad[p] >= 60 && mot[p] >= 8 }
        openClose(&edgeMask, W: W, H: H, openK: 3, closeK: 5)
        var lineEnds: [(Double, Double)] = []
        for b in blobs(mask: edgeMask, planes: pl, motion: mot, src: "line", minArea: 40, connectivity8: true)
        where max(b.w, b.h) >= 30 && b.elong >= 0.75 {
            let L = Double(max(b.w, b.h)) / 2
            lineEnds.append((b.cx + L * cos(b.theta), b.cy + L * sin(b.theta)))
            lineEnds.append((b.cx - L * cos(b.theta), b.cy - L * sin(b.theta)))
        }

        var cands: [UnionCand] = []
        for (srcIdx, m) in masks {
            for b in blobs(mask: m, planes: pl, motion: mot, src: "u", minArea: 30, connectivity8: true) where b.area <= 4000 {
                var dline = 200.0
                for (ex, ey) in lineEnds { dline = min(dline, hypot(b.cx - ex, b.cy - ey)) }
                // grad mean over bbox
                let x0 = max(0, Int(b.cx - Double(b.w)/2)), x1 = min(W - 1, Int(b.cx + Double(b.w)/2))
                let y0 = max(0, Int(b.cy - Double(b.h)/2)), y1 = min(H - 1, Int(b.cy + Double(b.h)/2))
                var gs = 0.0; var n = 0
                var yy = y0
                while yy <= y1 { var xx = x0; while xx <= x1 { gs += Double(grad[yy*W+xx]); n += 1; xx += 1 }; yy += 1 }
                cands.append(UnionCand(
                    cx: b.cx, cy: b.cy, a: b.area, w: b.w, h: b.h,
                    elong: b.elong, mot: b.mot, dh: b.dhMean, v: b.vMean,
                    hue: b.hMean, sat: b.sMean, grad: n > 0 ? gs / Double(n) : 0,
                    dline: dline, border: b.border, agree: 1, srcIdx: srcIdx))
            }
        }
        cands.sort { $0.a > $1.a }
        var kept: [UnionCand] = []
        for c in cands {
            var dup = false
            for i in kept.indices where hypot(c.cx - kept[i].cx, c.cy - kept[i].cy) <= 6 {
                kept[i].agree += 1
                dup = true
                break
            }
            if !dup { kept.append(c) }
        }
        return Array(kept.prefix(40))
    }

    /// EXACT feature order of club_union_scorer.py feats().
    private static func unionFeats(_ c: UnionCand, lock: CGPoint) -> [Double] {
        let dball = hypot(c.cx - lock.x, c.cy - lock.y)
        var f: [Double] = [
            log(max(c.a, 1)),
            Double(max(c.w, c.h)) / Double(max(1, min(c.w, c.h))),
            min(c.mot, 80) / 80.0, c.dh / 255.0, c.v / 255.0,
            min(dball / 120.0, 2.0),
            c.cx >= lock.x - 10 ? 1.0 : 0.0,
            c.border ? 1.0 : 0.0,
            c.elong, c.hue / 180.0, c.sat / 255.0,
            min(c.grad, 150) / 150.0, min(c.dline, 200) / 200.0,
            Double(min(c.agree, 5)) / 5.0,
        ]
        for i in 0..<5 { f.append(c.srcIdx == i ? 1.0 : 0.0) }
        return f
    }

    /// Full pipeline: downscale → candidates → GBT → DP chain. Returns per-frame picks in
    /// NORMALIZED coordinates for frames [impact-6, impact+1], or [:] when no chain forms.
    static func clubUnionTrack(frames: [AnalyzedShotFrame], impactIndex: Int,
                               lockNorm: CGPoint, r0Norm: Double) -> [Int: (cx: Double, cy: Double, conf: Double)] {
        guard let model = clubUnionModel else { return [:] }
        let t0 = CFAbsoluteTimeGetCurrent()
        let byIdx = Dictionary(uniqueKeysWithValues: frames.map { ($0.frameIndex, $0) })
        // ±2 frames of slack vs the prototype window: the scorer/labels anchor on impact
        // estimates that can differ by 1-2 frames from ours — a wider chain still covers
        // the labeled frames when the anchors disagree.
        let fis = Array(max(0, impactIndex - 8)...(impactIndex + 3)).filter { byIdx[$0] != nil }
        guard fis.count >= 4 else { return [:] }

        // pre-impact luma baseline from downscaled early frames
        var preLumas: [[Float]] = []
        var W = 0, H = 0
        for fi in stride(from: 0, to: min(14, impactIndex), by: 3) {
            guard let f = byIdx[fi] ?? frames.first(where: { $0.frameIndex == fi }),
                  let pl = planes(from: downscaled(f.originalFrame.image, toWidth: 360)) else { continue }
            preLumas.append(pl.luma); W = pl.W; H = pl.H
        }
        guard preLumas.count >= 3, W > 0 else { return [:] }
        var base = [Float](repeating: 0, count: W * H)
        for p in 0..<(W * H) {
            var vals = preLumas.map { $0[p] }
            vals.sort()
            base[p] = vals[vals.count / 2]
        }
        let lock = CGPoint(x: lockNorm.x * CGFloat(W), y: lockNorm.y * CGFloat(H))

        func gbtP(_ x: [Double]) -> Double {
            var z = model.base
            for s in model.stumps where s.count == 4 {
                z += x[Int(s[0])] <= s[1] ? s[2] : s[3]
            }
            return 1.0 / (1.0 + exp(-max(-30, min(30, z))))
        }

        let cuDbg = ProcessInfo.processInfo.environment["TC_CU_DEBUG"] == "1"
        var per: [[UnionCand]] = []
        for fi in fis {
            guard let f = byIdx[fi],
                  let pl = planes(from: downscaled(f.originalFrame.image, toWidth: 360)),
                  let gained = planes(from: downscaled(f.originalFrame.image, toWidth: 360), gain: 2.2) else {
                per.append([]); continue
            }
            var cands = unionCands(planes: pl, gained: gained, base: base)
            for i in cands.indices { cands[i].p = gbtP(unionFeats(cands[i], lock: lock)) }
            if cuDbg {
                for c in cands.sorted(by: { $0.p > $1.p }).prefix(5) {
                    print(String(format: "[CUdbg] f%02d (%.0f,%.0f) a=%.0f src=%d el=%.2f mot=%.0f dh=%.0f v=%.0f hue=%.0f sat=%.0f gr=%.0f dl=%.0f ag=%d p=%.3f",
                                 fi, c.cx, c.cy, c.a, c.srcIdx, c.elong, c.mot, c.dh, c.v, c.hue, c.sat, c.grad, c.dline, c.agree, c.p))
                }
            }
            per.append(cands)
        }

        // DP chain (mirrors python: SKIP -1.2, node 2p-1, step<=75, closing +12 slack)
        struct Key: Hashable { let i: Int; let j: Int }
        var best: [Key: (Double, Key?)] = [:]
        // Weak nodes must lose to SKIP, never anchor a chain: a p=0.01 bag pick at the
        // window start poisoned monotonicity and collapsed the whole track (measured).
        for (j, c) in per[0].enumerated() where c.p >= 0.30 { best[Key(i: 0, j: j)] = (2 * c.p - 1, nil) }
        best[Key(i: 0, j: -1)] = (-1.2, nil)
        for i in 1..<fis.count {
            var row: [Key: (Double, Key?)] = [:]
            for j in -1..<per[i].count {
                let c: UnionCand? = j >= 0 ? per[i][j] : nil
                if let cc = c, cc.p < 0.30 { continue }
                let ns = c.map { 2 * $0.p - 1 } ?? -1.2
                var top: (Double, Key?)? = nil
                for (pk, pv) in best where pk.i == i - 1 {
                    var cs: Double
                    if let c, pk.j >= 0 {
                        let pc = per[i-1][pk.j]
                        let step = hypot(c.cx - pc.cx, c.cy - pc.cy)
                        if step > 75 { continue }
                        let d1 = hypot(pc.cx - lock.x, pc.cy - lock.y)
                        let d2 = hypot(c.cx - lock.x, c.cy - lock.y)
                        if d2 > d1 + 12 { continue }
                        cs = pv.0 + ns + 0.6 * (1 - step / 75.0) + (d2 < d1 - 3 ? 0.4 : 0)
                    } else {
                        cs = pv.0 + ns
                    }
                    if top == nil || cs > top!.0 { top = (cs, pk) }
                }
                if let top { row[Key(i: i, j: j)] = top }
            }
            best.merge(row) { a, _ in a }
        }
        let finals = best.keys.filter { $0.i == fis.count - 1 }
        func finalScore(_ k: Key) -> Double {
            var s = best[k]!.0
            if k.j >= 0 {
                let c = per[k.i][k.j]
                let db = hypot(c.cx - lock.x, c.cy - lock.y)
                s += db < 35 ? 1.5 : (db > 90 ? -1.0 : 0)
            }
            return s
        }
        guard var cur: Key? = finals.max(by: { finalScore($0) < finalScore($1) }) else { return [:] }
        var picks: [Int: (Double, Double, Double)] = [:]
        while let k = cur {
            if k.j >= 0 {
                let c = per[k.i][k.j]
                picks[fis[k.i]] = (c.cx / Double(W), c.cy / Double(H), c.p)
            }
            cur = best[k]?.1
        }
        print(String(format: "[ClubUnion] %d/%d frames picked in %.2fs", picks.count, fis.count,
                     CFAbsoluteTimeGetCurrent() - t0))
        return picks.mapValues { (cx: $0.0, cy: $0.1, conf: $0.2) }
    }
}
