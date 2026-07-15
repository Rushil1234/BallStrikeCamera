#if DEBUG
import SwiftUI
import UIKit

// MARK: - Root

struct BallTrackingTestView: View {
    let onDismiss: () -> Void

    enum TesterPage: String, CaseIterable {
        case ball    = "Ball"
        case club    = "Club"
        case metrics = "Metrics"
    }

    @State private var exports:           [URL]                      = []
    @State private var sequence:          BallTrackingTestSequence?  = nil
    @State private var result:            BallTrackingTestResult?    = nil
    @State private var isRunning:         Bool                       = false
    @State private var currentIndex:      Int                        = 0
    @State private var clubCurrentIndex:  Int                        = 0
    @State private var loadError:         String?                    = nil
    @State private var displayMode:       FrameNormalizationMode     = .darkenedHighContrast
    @State private var settings:          BallTrackingTuningSettings = BallTrackingTuningSettings()
    @State private var exportStatus:      String?                    = nil
    @State private var activePage:        TesterPage                 = .ball

    private let loader     = TestFrameLoader()
    private let normalizer = FrameNormalizer()

    // Effective impact index: detected (after Run) or metadata fallback
    private var effectiveImpactIndex: Int {
        result?.detectedImpactFrameIndex ?? sequence?.impactFrameIndex ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let seq = sequence {
                mainContent(seq)
            } else {
                exportList
            }
        }
        .background(Color.black.ignoresSafeArea())
        .tcAppearance()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            exports = loader.listAvailableExports()
            // Headed dev demo (TC_OPEN_TESTER=1): auto-load the first export and run it so
            // the overlays are on screen without any tapping.
            if ProcessInfo.processInfo.environment["TC_OPEN_TESTER"] == "1",
               sequence == nil, let first = exports.first {
                loadExport(first)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { runTracker() }
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            if sequence != nil {
                Button(action: { sequence = nil; result = nil }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            Text(sequence.map { "Tester · \($0.sourceName)" } ?? "Tracking Tester")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white).lineLimit(1).truncationMode(.middle)
            Spacer()
            if sequence != nil {
                pagePicker
                if activePage == .ball { displayModePicker }
                Button(action: runTracker) {
                    Label(isRunning ? "Running…" : "Run", systemImage: "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(isRunning ? Color.gray.opacity(0.5) : Color.purple.opacity(0.75))
                        .clipShape(Capsule())
                }
                .disabled(isRunning)
                Button(action: exportExperimentalMetrics) {
                    Label("Export Metrics", systemImage: "square.and.arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(result?.metrics == nil ? Color.gray.opacity(0.45) : Color.orange.opacity(0.75))
                        .clipShape(Capsule())
                }
                .disabled(result?.metrics == nil)
            }
            Button("Done") { onDismiss() }
                .font(.system(size: 14, weight: .semibold)).foregroundColor(.blue)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(white: 0.10))
    }

    private var pagePicker: some View {
        HStack(spacing: 0) {
            ForEach(TesterPage.allCases, id: \.self) { page in
                Button(action: { activePage = page }) {
                    Text(page.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(activePage == page ? .black : .white.opacity(0.65))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(activePage == page ? Color.white : Color.clear)
                }
            }
        }
        .background(Color.white.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var displayModePicker: some View {
        HStack(spacing: 0) {
            ForEach(FrameNormalizationMode.allCases, id: \.self) { mode in
                Button(action: { displayMode = mode }) {
                    Text(mode.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(displayMode == mode ? .black : .white.opacity(0.65))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(displayMode == mode ? Color.white : Color.clear)
                }
            }
        }
        .background(Color.white.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // MARK: - Export list

    private var exportList: some View {
        Group {
            if exports.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray").font(.system(size: 36)).foregroundColor(.white.opacity(0.3))
                    Text("No shot exports found").font(.system(size: 14)).foregroundColor(.white.opacity(0.5))
                    Text("Export a shot from the Review screen first.")
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.35))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(exports, id: \.self) { url in
                            Button(action: { loadExport(url) }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(url.lastPathComponent)
                                            .font(.system(size: 13, weight: .medium)).foregroundColor(.white)
                                        if let count = frameCount(in: url) {
                                            Text("\(count) frames")
                                                .font(.system(size: 11)).foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12)).foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .background(Color(white: 0.10))
                            }
                        }
                    }
                }
                .padding(.top, 1)
            }
        }
    }

    // MARK: - Main content

    private func mainContent(_ seq: BallTrackingTestSequence) -> some View {
        Group {
            switch activePage {
            case .ball:    ballPage(seq)
            case .club:    clubPage(seq)
            case .metrics: metricsPage
            }
        }
    }

    private func ballPage(_ seq: BallTrackingTestSequence) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                imagePane(seq).frame(maxWidth: .infinity)
                controlsSidebar.frame(width: 270)
            }
            .layoutPriority(1)
            impactInfoRow
            metricsInfoRow
            frameStrip(seq)
            navigationBar(seq)
        }
        .background(
            KeyboardNavigatorView(
                onLeft:  { if currentIndex > 0 { currentIndex -= 1 } },
                onRight: { if currentIndex < (sequence?.frames.count ?? 1) - 1 { currentIndex += 1 } }
            ).frame(width: 0, height: 0)
        )
    }

    // MARK: - Club page

    private func clubPage(_ seq: BallTrackingTestSequence) -> some View {
        let impact = effectiveImpactIndex
        let clubFrames = seq.frames.filter { $0.frameIndex >= impact - 10 && $0.frameIndex <= impact + 1 }
        let clubCount = clubFrames.count
        let safeIdx = min(clubCurrentIndex, max(0, clubCount - 1))

        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                // Club image pane
                GeometryReader { geo in
                    ZStack {
                        Color.black
                        if safeIdx < clubFrames.count,
                           let img = displayedImage(clubFrames[safeIdx]) {
                            Image(uiImage: img).resizable().scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            let fi = clubFrames[safeIdx].frameIndex
                            let clubObs = result?.metrics?.clubObservations.first { $0.frameIndex == fi }
                            Canvas { ctx, size in
                                let dr = aspectFitRect(imageSize: img.size, in: size)
                                guard dr.width > 0 else { return }
                                drawClubPageOverlay(ctx: ctx, dr: dr, metrics: result?.metrics,
                                                    clubObs: clubObs, frameIndex: fi)
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                            .allowsHitTesting(false)
                            clubInfoOverlay(frame: clubFrames[safeIdx], clubObs: clubObs, impact: impact)
                            clubOverlayLegend
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                .padding(.top, 8).padding(.trailing, 8)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                clubControlsSidebar.frame(width: 270)
            }
            .layoutPriority(1)
            clubFrameStrip(clubFrames, impact: impact)
            clubNavigationBar(clubCount)
        }
        .background(
            KeyboardNavigatorView(
                onLeft:  { if clubCurrentIndex > 0 { clubCurrentIndex -= 1 } },
                onRight: { if clubCurrentIndex < clubCount - 1 { clubCurrentIndex += 1 } }
            ).frame(width: 0, height: 0)
        )
    }

    private func drawClubPageOverlay(
        ctx: GraphicsContext,
        dr: CGRect,
        metrics: ExperimentalShotMetricsResult?,
        clubObs: ExperimentalClubObservation?,
        frameIndex: Int
    ) {
        // Orange solid club center path, built up to the current frame
        if settings.club.showClubPath,
           let allObs = metrics?.clubObservations.filter({ $0.isDetected && $0.frameIndex <= frameIndex }),
           allObs.count >= 2 {
            var path = Path()
            var started = false
            for obs in allObs {
                guard let x = obs.centerX, let y = obs.centerY else { continue }
                let pt = normPointToView(CGPoint(x: x, y: y), dr: dr)
                if started { path.addLine(to: pt) } else { path.move(to: pt); started = true }
            }
            // Orange solid line through clubhead centers (smooth, no zig-zag)
            ctx.stroke(path, with: .color(.orange.opacity(0.9)), style: StrokeStyle(lineWidth: 2))

            // Dot at each detected center; emphasize current frame
            for obs in allObs {
                guard let x = obs.centerX, let y = obs.centerY else { continue }
                let pt = normPointToView(CGPoint(x: x, y: y), dr: dr)
                let isCurrent = obs.frameIndex == frameIndex
                let r: CGFloat = isCurrent ? 5.5 : 3
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                         with: .color(.orange.opacity(isCurrent ? 1.0 : 0.65)))
            }
        }

        // 0° HLA reference line from impact ball position
        if settings.show0DegRef {
            let origin: CGPoint?
            if let impactObs = metrics?.clubObservations.first(where: {
                $0.ballExclusionCenterX != nil && $0.frameDifferenceWasUsed == false || true
            }), let bx = impactObs.ballExclusionCenterX, let by = impactObs.ballExclusionCenterY {
                origin = normPointToView(CGPoint(x: bx, y: by), dr: dr)
            } else if let firstBall = metrics?.ball3DObservations.first {
                origin = normPointToView(CGPoint(x: firstBall.imageX, y: firstBall.imageY), dr: dr)
            } else {
                origin = nil
            }
            if let origin {
                draw0DegRef(ctx: ctx, dr: dr, origin: origin, zeroDeg: settings.zeroDegreeAngleDeg)
            }
        }

        guard let clubObs else { return }

        if settings.club.showClubSearchROI, let roi = clubObs.searchROI {
            ctx.stroke(Path(normToView(roi, dr: dr)), with: .color(.orange.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }

        if settings.club.showBallExclusionZone,
           let x = clubObs.ballExclusionCenterX, let y = clubObs.ballExclusionCenterY,
           let d = clubObs.ballExclusionDiameter {
            strokeCircle(ctx: ctx, dr: dr, cx: x, cy: y, d: d, color: .orange.opacity(0.32), lineWidth: 1)
        }

        // Orange bounding box around clubhead
        if let bbox = clubObs.clubBoundingBox {
            ctx.stroke(Path(normToView(bbox, dr: dr)), with: .color(.orange.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 2))
        }

        if let cx = clubObs.centerX, let cy = clubObs.centerY {
            let pt = normPointToView(CGPoint(x: cx, y: cy), dr: dr)
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)),
                     with: .color(.orange))
        }

        if let lx = clubObs.leadingEdgeX, let ly = clubObs.leadingEdgeY {
            let pt = normPointToView(CGPoint(x: lx, y: ly), dr: dr)
            ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)),
                       with: .color(.purple), lineWidth: 2.5)
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4)),
                     with: .color(.purple))
        }
    }

    private func clubInfoOverlay(frame: BallTrackingTestFrame,
                                  clubObs: ExperimentalClubObservation?,
                                  impact: Int) -> some View {
        let fi = frame.frameIndex
        let rel = fi - impact
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text("Frame \(fi)").fontWeight(.semibold)
                Text(rel == 0 ? "IMPACT" : rel < 0 ? "pre \(rel)" : "post +\(rel)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(rel == 0 ? .red : rel < 0 ? .secondary : .orange)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background((rel == 0 ? Color.red : rel < 0 ? Color.secondary : Color.orange).opacity(0.2))
                    .clipShape(Capsule())
                Text(String(format: "%+.1f ms", frame.relativeTime * 1000)).foregroundColor(.secondary)
            }
            if let c = clubObs, c.isDetected {
                if let lx = c.leadingEdgeX, let ly = c.leadingEdgeY {
                    Text(String(format: "lead=(%.4f, %.4f) conf=%.2f", lx, ly, c.confidence))
                        .foregroundColor(.orange)
                }
                if let bbox = c.clubBoundingBox {
                    Text(String(format: "bbox=(%.3f,%.3f,%.3f,%.3f)", bbox.minX, bbox.minY, bbox.width, bbox.height))
                        .foregroundColor(.white.opacity(0.6))
                }
                Text("mode=\(c.detectionMode)  diff=\(c.frameDifferenceWasUsed ? "yes" : "no")")
                    .foregroundColor(.white.opacity(0.45))
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                    Text(clubObs?.debugReason ?? (result == nil ? "Run tracker first" : "no club obs")).foregroundColor(.orange)
                }
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.white)
        .padding(8).background(Color.black.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private var clubOverlayLegend: some View {
        let items: [(String, Color)] = [
            ("── Club center path", .orange),
            ("- - Club search ROI", .orange),
            ("□  Clubhead bounding box", .orange),
            ("◉  Leading edge point", .purple),
            ("- - 0° HLA reference", .white),
            ("○  Ball exclusion zone", .orange.opacity(0.5))
        ]
        return VStack(alignment: .leading, spacing: 2) {
            Text("LEGEND")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.white.opacity(0.55))
            ForEach(items, id: \.0) { label, color in
                Text(label)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(color)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.80))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private func clubFrameStrip(_ frames: [BallTrackingTestFrame], impact: Int) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(frames.enumerated()), id: \.offset) { i, frame in
                        let fi = frame.frameIndex
                        let isImpact = fi == impact
                        let detected = result?.metrics?.clubObservations.first {
                            $0.frameIndex == fi && $0.isDetected
                        } != nil
                        let color: Color = isImpact ? .yellow : detected ? .orange : result != nil ? .red.opacity(0.6) : Color(white: 0.25)
                        Button(action: { clubCurrentIndex = i }) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color.opacity(0.85))
                                .frame(width: 18, height: 32)
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.white, lineWidth: clubCurrentIndex == i ? 2 : 0))
                                .overlay(alignment: .top) {
                                    Text("\(fi)").font(.system(size: 7)).foregroundColor(.white.opacity(0.7)).padding(.top, 2)
                                }
                        }
                        .id(i)
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 44)
            .background(Color(white: 0.08))
            .onChange(of: clubCurrentIndex) { idx in
                withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(idx, anchor: .center) }
            }
        }
    }

    private func clubNavigationBar(_ count: Int) -> some View {
        let last = max(0, count - 1)
        return HStack(spacing: 12) {
            Button(action: { if clubCurrentIndex > 0 { clubCurrentIndex -= 1 } }) {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                    .foregroundColor(clubCurrentIndex > 0 ? .white : .white.opacity(0.25))
            }.frame(width: 44, height: 44)
            Slider(value: Binding(
                get: { Double(clubCurrentIndex) },
                set: { clubCurrentIndex = Int($0.rounded()) }
            ), in: 0...Double(max(1, last)), step: 1).tint(.orange)
            Button(action: { if clubCurrentIndex < last { clubCurrentIndex += 1 } }) {
                Image(systemName: "chevron.right").font(.system(size: 18, weight: .semibold))
                    .foregroundColor(clubCurrentIndex < last ? .white : .white.opacity(0.25))
            }.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(white: 0.10))
    }

    private var clubControlsSidebar: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                TunerSection(title: "Club Detection") {
                    TunerToggle(label: "enabled", value: $settings.club.enabled)
                    TunerToggle(label: "search behind ball", value: $settings.club.searchBehindBallEnabled)
                    TunerSlider(label: "ball excl scale", value: $settings.club.ballExclusionRadiusScale,
                                range: 0.5...5.0, format: "%.2f")
                    TunerSlider(label: "ROI scale X", value: $settings.club.clubSearchROIScaleX,
                                range: 1...16, format: "%.2f")
                    TunerSlider(label: "ROI scale Y", value: $settings.club.clubSearchROIScaleY,
                                range: 1...12, format: "%.2f")
                }
                TunerSection(title: "Frame Difference") {
                    TunerToggle(label: "use frame diff", value: $settings.club.useFrameDifference)
                    TunerSlider(label: "diff threshold", value: $settings.club.frameDifferenceThreshold,
                                range: 1...120, format: "%.0f", isInt: true)
                }
                TunerSection(title: "Dark Blob") {
                    TunerSlider(label: "darkness threshold", value: $settings.club.minClubDarknessOrEdgeThreshold,
                                range: 10...180, format: "%.0f", isInt: true)
                    TunerSlider(label: "min blob area", value: $settings.club.minClubBlobArea,
                                range: 1...300, format: "%.0f", isInt: true)
                    TunerSlider(label: "max blob area", value: $settings.club.maxClubBlobArea,
                                range: 100...20000, format: "%.0f", isInt: true)
                    TunerSlider(label: "min confidence", value: $settings.club.minClubConfidence,
                                range: 0...1, format: "%.2f")
                }
                TunerSection(title: "Overlays") {
                    TunerToggle(label: "show club path",     value: $settings.club.showClubPath)
                    TunerToggle(label: "show club ROI",      value: $settings.club.showClubSearchROI)
                    TunerToggle(label: "show exclusion zone",value: $settings.club.showBallExclusionZone)
                    TunerToggle(label: "show 0° ref line",   value: $settings.show0DegRef)
                    TunerToggle(label: "debug logging",      value: $settings.club.debugLoggingEnabled)
                }
                if let metrics = result?.metrics {
                    TunerSection(title: "Club Results") {
                        clubMetricReadout("Club speed", value: mph(metrics.club.clubSpeedMph))
                        clubMetricReadout("Points used", value: "\(metrics.club.pointsUsed)")
                        clubMetricReadout("Quality", value: String(format: "%.2f", metrics.club.quality))
                        clubMetricReadout("Method", value: metrics.club.method)
                        ForEach(metrics.club.warnings, id: \.self) { w in
                            Text("⚠ \(w)").font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.yellow).padding(.horizontal, 12).padding(.vertical, 2)
                        }
                    }
                }
                Button(action: { settings.club.resetDefaults() }) {
                    Text("Reset club defaults").font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                }
            }
            .padding(.bottom, 20)
        }
        .background(Color(white: 0.07))
    }

    private func clubMetricReadout(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(value).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(.white)
        }
        .padding(.horizontal, 12).padding(.vertical, 3)
    }

    // MARK: - Metrics page

    private var metricsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let metrics = result?.metrics {
                    metricsResults(metrics)
                } else if result != nil {
                    Text("Run tracker to populate metrics.\n(Metrics run automatically with tracking.)")
                        .font(.system(size: 13)).foregroundColor(.white.opacity(0.6))
                        .padding(24)
                } else {
                    Text("Press Run to calculate metrics.")
                        .font(.system(size: 13)).foregroundColor(.white.opacity(0.6))
                        .padding(24)
                }
                Divider().background(Color.white.opacity(0.1)).padding(.vertical, 12)
                metricsFormulas
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
        }
        .background(Color.black)
    }

    private func metricsResults(_ metrics: ExperimentalShotMetricsResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("RESULTS").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)

            metricsGroup("Ball Launch") {
                metricsRow("Ball Speed", value: mph(metrics.ballLaunch.ballSpeedMph),
                           formula: "|v_ball| × 2.23694",
                           note: "\(metrics.ballLaunch.pointsUsed) pts · \(metrics.ballLaunch.method)")
                metricsRow("HLA",
                           value: metrics.ballLaunch.hlaDisplay,
                           formula: "atan2(lateral, forward) — image-space ref \(String(format: "%.0f°", metrics.zeroDegreeReferenceAngleDegrees))",
                           note: "3D raw: \(degrees(metrics.ballLaunch.hla3DRawDegrees))")
                metricsRow("VLA", value: degrees(metrics.ballLaunch.vlaDegrees),
                           formula: "atan2(vy, √(vx²+vz²)) · clamped ≥ 0",
                           note: metrics.ballLaunch.vlaRawDegrees.map { String(format: "raw %.1f° (clamped)", $0) } ?? "vertical launch angle")
                if let dx = metrics.ballLaunch.ballMovementDx, let dy = metrics.ballLaunch.ballMovementDy {
                    metricsRow("2D movement",
                               value: String(format: "(%.4f, %.4f)", dx, dy),
                               formula: "image-space dx/dt, dy/dt (x→, y↓)", note: nil)
                }
                if let fwd = metrics.ballLaunch.hlaForwardComponent,
                   let lat = metrics.ballLaunch.hlaLateralComponent {
                    metricsRow("Fwd / Lateral",
                               value: String(format: "%.4f / %.4f", fwd, lat),
                               formula: "projected onto ref / perp axes", note: nil)
                }
            }

            metricsGroup("Club") {
                metricsRow("Club Speed", value: mph(metrics.club.clubSpeedMph),
                           formula: "|v_club| × 2.23694",
                           note: "\(metrics.club.pointsUsed) pts · assumed ball depth · frameDifference mode")
                metricsRow("Smash Factor", value: plain(metrics.smashFactor, digits: 2),
                           formula: "ball_speed / club_speed", note: nil)
                metricsRow("Club Path (Estimated)",
                           value: metrics.clubPath.clubPathDisplay,
                           formula: "image-space 2D movement → atan2 vs 0° ref",
                           note: String(format: "conf %.2f · %@", metrics.clubPath.confidence, metrics.clubPath.method))
                metricsRow("Face Angle (Estimated)",
                           value: metrics.faceAngle.faceAngleDisplay,
                           formula: "edge gradient PCA in clubhead bbox",
                           note: "confidence: \(metrics.faceAngle.confidence)")
                metricsRow("Face-to-Path (Estimated)",
                           value: metrics.faceAngle.faceToPathDisplay,
                           formula: "face − club path  (+R = open, −L = closed)",
                           note: nil)
            }

            metricsGroup("Estimated Spin (Model-Based)") {
                metricsRow("Backspin (Estimated)",
                           value: metrics.spin.estimatedBackspinRpm.map { String(format: "%.0f rpm", $0) } ?? "—",
                           formula: "(800 + 90×speed + 120×VLA) × VLA_multiplier",
                           note: "ESTIMATED — not measured")
                metricsRow("Sidespin (Estimated)",
                           value: metrics.spin.estimatedSidespinDisplay,
                           formula: "(HLA − path) × 200 × (speed/100)",
                           note: "ESTIMATED · \(metrics.spin.spinEstimateMethod)")
                metricsRow("Spin Axis (Estimated)",
                           value: metrics.spin.estimatedSpinAxisDisplay,
                           formula: "atan2(sidespin, backspin)",
                           note: "ESTIMATED — positive = tilted right")
            }

            metricsGroup("Distance") {
                if let ideal = metrics.distance.idealCarryYards {
                    metricsRow("Ideal Carry",
                               value: yards(ideal),
                               formula: "v²·sin(2θ)/g  (no drag, no lift)",
                               note: "correction factor: \(String(format: "%.2f", metrics.distance.carryCorrectionFactor))")
                }
                metricsRow("Carry", value: yards(metrics.distance.carryYards),
                           formula: "idealCarry × correctionFactor",
                           note: "tune correction factor slider for accuracy")
                if let rf = metrics.distance.rolloutFraction {
                    metricsRow("Rollout",
                               value: String(format: "%.0f%% of carry", rf * 100),
                               formula: "VLA bucket: \(metrics.distance.vlaBucket)", note: nil)
                }
                metricsRow("Rollout yards", value: yards(metrics.distance.rolloutYards),
                           formula: "carry × rolloutFraction", note: nil)
                metricsRow("Total", value: yards(metrics.distance.totalYards),
                           formula: "carry + rollout yards", note: "capped at 400 yd")
            }

            metricsGroup("Calibration") {
                let cal = metrics.calibration
                metricsRow("Image", value: "\(Int(cal.imageWidthPixels))×\(Int(cal.imageHeightPixels))", formula: nil, note: nil)
                metricsRow("H FOV", value: String(format: "%.1f°", cal.horizontalFOVDegrees), formula: nil, note: nil)
                metricsRow("V FOV", value: String(format: "%.1f°", cal.verticalFOVDegrees), formula: nil, note: nil)
                metricsRow("fx", value: String(format: "%.1f px", cal.focalLengthPixelsX), formula: "W / (2·tan(hFOV/2))", note: nil)
                metricsRow("fy", value: String(format: "%.1f px", cal.focalLengthPixelsY), formula: "H / (2·tan(vFOV/2))", note: nil)
                metricsRow("Ball Ø", value: String(format: "%.1f mm", cal.realBallDiameterMeters * 1000), formula: nil, note: nil)
                if let h = cal.cameraHeightMeters {
                    metricsRow("Cam height", value: String(format: "%.2f m", h), formula: nil, note: nil)
                }
                if let t = cal.cameraTiltDegrees {
                    metricsRow("Cam tilt", value: String(format: "%.1f°", t), formula: nil, note: nil)
                }
            }

            if !metrics.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WARNINGS").font(.system(size: 10, weight: .semibold)).foregroundColor(.yellow)
                    ForEach(metrics.warnings, id: \.self) { w in
                        HStack(alignment: .top, spacing: 6) {
                            Text("⚠").foregroundColor(.yellow)
                            Text(w).font(.system(size: 11)).foregroundColor(.yellow.opacity(0.85))
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func metricsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
            content()
        }
    }

    private func metricsRow(_ label: String, value: String, formula: String?, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(value).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(.white)
            }
            if let formula {
                Text(formula).font(.system(size: 10, design: .monospaced)).foregroundColor(.cyan.opacity(0.75))
            }
            if let note {
                Text(note).font(.system(size: 10)).foregroundColor(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var metricsFormulas: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("HOW METRICS ARE CALCULATED")
                .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)

            formulaBlock("3D Position (pinhole model)",
                "Z = realBallDiameter × focalLength / apparentDiameterPixels\n" +
                "X = (px - cx) × Z / fx\n" +
                "Y = (py - cy) × Z / fy")

            formulaBlock("Ball Velocity",
                "Linear regression over ≥3 post-impact 3D positions vs time\n" +
                "2-point delta fallback if only 2 points available\n" +
                "speed = |velocity vector| in m/s → mph × 2.23694")

            formulaBlock("HLA (image-space reference-line)",
                "ref  = (cos θ, -sin θ)  in image coords (y-down)\n" +
                "perp = (sin θ, cos θ)\n" +
                "forward = v2d · ref\n" +
                "lateral = v2d · perp\n" +
                "HLA = atan2(lateral, forward)\n" +
                "0° when ball travels along reference line\n" +
                "θ = zeroDegreeAngleDeg (set in sidebar)")

            formulaBlock("HLA 3D raw (debug only)",
                "HLA_3D = atan2(vx, vz)  — may show ~90° if\n" +
                "depth estimate is off; use image-space HLA instead")

            formulaBlock("VLA",
                "VLA = atan2(vy, √(vx²+vz²))  — up/down angle")

            formulaBlock("Club Speed (frameDifference mode default)",
                "Club 3D position assumed at ball depth near impact\n" +
                "useFrameDifference=true detects motion between frames\n" +
                "Same linear fit / 2-point method as ball velocity")

            formulaBlock("Smash Factor",
                "smash = ball_speed_mph / club_speed_mph")

            formulaBlock("Distance — carry (physics model)",
                "idealCarry = v²·sin(2θ)/g  (pure ballistic, m)\n" +
                "carry = idealCarry × correctionFactor × 1.09361 yd/m\n" +
                "correctionFactor default 0.75 (tune with slider)\n" +
                "Accounts for drag; Magnus lift not modeled directly")

            formulaBlock("Distance — rollout/total",
                "rolloutFraction = f(VLA bucket) × speedAdjust\n" +
                "<1°:85%  1–3°:65%  3–6°:45%  6–10°:30%\n" +
                "10–15°:20%  15–22°:12%  22–30°:7%  ≥30°:3%\n" +
                "speedAdjust: <40mph×0.45  40–80×0.75  ≥130×1.1\n" +
                "rolloutYards = carry × rolloutFraction\n" +
                "total = carry + rolloutYards  (capped 400 yd)")

            formulaBlock("Estimated Spin (Model-Based)",
                "backspin = (800 + 90×speed + 120×VLA) × VLA_mult\n" +
                "VLA multiplier: <5°×0.60  5–10°×0.80  10–20°×1.00\n" +
                "  20–30°×1.20  ≥30°×1.35  clamp 300–9000 rpm\n" +
                "sidespin = (HLA − path) × 200 × (speed/100)\n" +
                "spinAxis = atan2(sidespin, backspin)\n" +
                "ESTIMATED — not measured")

            formulaBlock("Club Path & Face Angle (Estimated)",
                "Club path: image-space 2D linear fit of centroid\n" +
                "positions → projected onto 0° ref → atan2\n" +
                "Face angle: dominant edge direction via Sobel\n" +
                "gradient PCA on clubhead bounding box at impact\n" +
                "Face-to-path = face − club path\n" +
                "ESTIMATED — confidence varies with image quality")
        }
    }

    private func formulaBlock(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.85))
            Text(body).font(.system(size: 10, design: .monospaced)).foregroundColor(.cyan.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Impact info row

    private var impactInfoRow: some View {
        Group {
            if let r = result {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.yellow)
                    Text("Impact detected: frame \(r.detectedImpactFrameIndex)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white)
                    if r.detectedImpactFrameIndex != r.fallbackImpactFrameIndex {
                        Text("(fallback: \(r.fallbackImpactFrameIndex))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                    Text(r.impactDetectionReason)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary).lineLimit(1)
                    Spacer()
                    if let c = r.initialBallCenter {
                        Text(String(format: "initCenter=(%.3f,%.3f)", c.x, c.y))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    if let lf = r.ballLaunchedAtFrameIndex {
                        Text("launch@\(lf)").font(.system(size: 10, design: .monospaced)).foregroundColor(.mint)
                    }
                    if r.ballTrackTerminated {
                        let tf = r.ballTerminatedAtFrameIndex.map { "@\($0)" } ?? ""
                        Text("TERM\(tf)").font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.8, green: 0.2, blue: 0.2))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Color(white: 0.08))
            } else {
                EmptyView()
            }
        }
    }

    private var metricsInfoRow: some View {
        Group {
            if let metrics = result?.metrics {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 12) {
                        metricCell("Ball Speed", value: mph(metrics.ballLaunch.ballSpeedMph))
                        metricCell("HLA (img-ref)", value: metrics.ballLaunch.hlaDisplay)
                        metricCell("VLA", value: degrees(metrics.ballLaunch.vlaDegrees))
                        metricCell("Club Speed", value: mph(metrics.club.clubSpeedMph))
                        metricCell("Smash", value: plain(metrics.smashFactor, digits: 2))
                        metricCell("Carry", value: yards(metrics.distance.carryYards))
                        metricCell("Total", value: yards(metrics.distance.totalYards))
                        metricCell("Backspin (Est)", value: metrics.spin.estimatedBackspinRpm.map { String(format: "%.0f rpm", $0) } ?? "—")
                        metricCell("Club Path (Est)", value: metrics.clubPath.clubPathDisplay)
                    }
                    HStack(spacing: 10) {
                        Text("ball pts \(metrics.ballLaunch.pointsUsed)")
                        Text("club pts \(metrics.club.pointsUsed)")
                        Text(String(format: "ball q %.2f", metrics.ballLaunch.quality))
                        Text(String(format: "club q %.2f", metrics.club.quality))
                        Text("impact \(metrics.detectedImpactFrameIndex)")
                        if let exportStatus {
                            Text(exportStatus)
                                .foregroundColor(.green)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        if let warning = metrics.warnings.first {
                            Text(warning)
                                .foregroundColor(.yellow)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.65))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(white: 0.065))
            } else if result != nil {
                Text("Metrics: Not enough data")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.yellow)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(white: 0.065))
            } else {
                EmptyView()
            }
        }
    }

    private func metricCell(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Image pane

    private func imagePane(_ seq: BallTrackingTestSequence) -> some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if currentIndex < seq.frames.count,
                   let img = displayedImage(seq.frames[currentIndex]) {
                    Image(uiImage: img).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    let obs = result?.observations.first {
                        $0.frameIndex == seq.frames[currentIndex].frameIndex
                    }
                    let clubObs = result?.metrics?.clubObservations.first {
                        $0.frameIndex == seq.frames[currentIndex].frameIndex
                    }
                    let showCandBounds = settings.showOriginalCandidateBounds
                    let showCandIDs    = settings.showCandidateIDs
                    Canvas { ctx, size in
                        drawOverlay(ctx: ctx, containerSize: size, image: img,
                                    obs: obs, metrics: result?.metrics,
                                    clubObs: clubObs,
                                    showCandidateBounds: showCandBounds,
                                    showCandidateIDs: showCandIDs,
                                    exclusionZones: settings.scoring.exclusionZones)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(false)
                    infoOverlay(seq: seq, obs: obs, clubObs: clubObs)
                    if settings.showMaskPreview {
                        maskPreviewInset(obs)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.top, 8).padding(.trailing, 8)
                            .allowsHitTesting(false)
                    }
                } else {
                    Text("No image").foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func displayedImage(_ frame: BallTrackingTestFrame) -> UIImage? {
        displayMode == .original ? frame.image
            : normalizer.normalizedImage(from: frame.image, mode: displayMode)
    }

    // MARK: - Canvas overlay

    private func drawOverlay(ctx: GraphicsContext, containerSize: CGSize,
                              image: UIImage, obs: BallTrackingTestObservation?,
                              metrics: ExperimentalShotMetricsResult?,
                              clubObs: ExperimentalClubObservation?,
                              showCandidateBounds: Bool,
                              showCandidateIDs: Bool = false,
                              exclusionZones: [CGRect] = []) {
        let dr = aspectFitRect(imageSize: image.size, in: containerSize)
        guard dr.width > 0, dr.height > 0 else { return }
        let dbg = obs?.frameDebug

        // Exclusion zones — translucent red fill (Part E)
        for zone in exclusionZones {
            let zr = normToView(zone, dr: dr)
            ctx.fill(Path(zr), with: .color(.red.opacity(0.18)))
            ctx.stroke(Path(zr), with: .color(.red.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
        }

        // Cyan dashed ROI
        if let roi = dbg?.searchROI {
            ctx.stroke(Path(normToView(roi, dr: dr)), with: .color(.cyan.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }

        // Predicted position crosshair (Part B)
        if let pred = dbg?.predictedPosition {
            let pt = normPointToView(pred, dr: dr)
            let arm: CGFloat = 6
            var cross = Path()
            cross.move(to: CGPoint(x: pt.x - arm, y: pt.y)); cross.addLine(to: CGPoint(x: pt.x + arm, y: pt.y))
            cross.move(to: CGPoint(x: pt.x, y: pt.y - arm)); cross.addLine(to: CGPoint(x: pt.x, y: pt.y + arm))
            ctx.stroke(cross, with: .color(.cyan.opacity(0.85)), lineWidth: 1.5)
        }

        // Rejected candidates — backward-rejected in dark red, others in red dashed rects
        let allCands = dbg?.candidates ?? []
        for (i, cand) in allCands.enumerated() where !cand.accepted {
            let isBackward = cand.backwardRejected
            let rejectColor: Color = isBackward ? Color(red: 0.7, green: 0, blue: 0) : .red.opacity(0.6)
            ctx.stroke(Path(normToView(cand.rect, dr: dr)), with: .color(rejectColor),
                       style: StrokeStyle(lineWidth: isBackward ? 1.5 : 1, dash: [4, 3]))
            if isBackward {
                let pt = normPointToView(CGPoint(x: cand.centerX, y: cand.centerY), dr: dr)
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6)),
                         with: .color(rejectColor))
            }
            if showCandidateIDs {
                let pt = normPointToView(CGPoint(x: cand.centerX, y: cand.centerY), dr: dr)
                ctx.draw(Text("\(i)").font(.system(size: 8, design: .monospaced)).foregroundColor(rejectColor.opacity(0.85)),
                         at: CGPoint(x: pt.x + 4, y: pt.y - 4), anchor: .leading)
            }
        }

        // Accepted-but-not-selected — yellow circles
        if let selected = dbg?.selectedCandidate {
            for (i, cand) in allCands.enumerated() where cand.accepted && !cand.isSelected {
                let samePos = cand.centerX == selected.centerX && cand.centerY == selected.centerY
                guard !samePos else { continue }
                strokeCircle(ctx: ctx, dr: dr, cx: cand.centerX, cy: cand.centerY,
                             d: cand.diameter, color: .yellow, lineWidth: 1.5)
                if showCandidateIDs {
                    let pt = normPointToView(CGPoint(x: cand.centerX, y: cand.centerY), dr: dr)
                    ctx.draw(Text("\(i)").font(.system(size: 8, design: .monospaced)).foregroundColor(.yellow.opacity(0.9)),
                             at: CGPoint(x: pt.x + 4, y: pt.y - 4), anchor: .leading)
                }
            }
        }

        // Launch direction arrow — drawn even on missed/terminated frames (Part D)
        if settings.showLaunchDirection, let launchDir = dbg?.launchDirectionVector, dbg?.ballHasLaunched == true {
            let originNorm = result?.initialBallCenter ?? CGPoint(x: 0.5, y: 0.5)
            let origin = normPointToView(originNorm, dr: dr)
            let arrowLen: CGFloat = min(dr.width, dr.height) * 0.20
            let tipX = origin.x + launchDir.x * arrowLen
            let tipY = origin.y + launchDir.y * arrowLen
            var arrow = Path()
            arrow.move(to: origin)
            arrow.addLine(to: CGPoint(x: tipX, y: tipY))
            ctx.stroke(arrow, with: .color(.mint.opacity(0.9)), style: StrokeStyle(lineWidth: 2.0))
            let headLen: CGFloat = 8
            let angle: CGFloat = .pi / 6
            let perp = CGPoint(x: -launchDir.y, y: launchDir.x)
            let back = CGPoint(x: -launchDir.x, y: -launchDir.y)
            let h1 = CGPoint(x: tipX + (back.x * cos(angle) + perp.x * sin(angle)) * headLen,
                             y: tipY + (back.y * cos(angle) + perp.y * sin(angle)) * headLen)
            let h2 = CGPoint(x: tipX + (back.x * cos(angle) - perp.x * sin(angle)) * headLen,
                             y: tipY + (back.y * cos(angle) - perp.y * sin(angle)) * headLen)
            var head = Path()
            head.move(to: CGPoint(x: tipX, y: tipY))
            head.addLine(to: h1)
            head.move(to: CGPoint(x: tipX, y: tipY))
            head.addLine(to: h2)
            ctx.stroke(head, with: .color(.mint.opacity(0.9)), lineWidth: 2.0)
        }

        // Termination indicator — dark red dot in top-right corner (Part D)
        if dbg?.ballTrackTerminated == true {
            let r: CGFloat = 6
            ctx.fill(Path(ellipseIn: CGRect(x: dr.maxX - r * 2 - 4, y: dr.minY + 4, width: r * 2, height: r * 2)),
                     with: .color(Color(red: 0.65, green: 0, blue: 0).opacity(0.95)))
        }

        guard let cx = obs?.centerX, let cy = obs?.centerY else { return }

        // Optional faint gray dashed rect — selected candidate blob bbox
        if showCandidateBounds, let blobRect = dbg?.selectedCandidate?.rect {
            ctx.stroke(Path(normToView(blobRect, dr: dr)), with: .color(.white.opacity(0.3)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }

        // Green circle — tight around the white pixels in the B&W mask.
        if let maskRect = obs?.maskBoundsRect,
           let refinedD = obs?.maskRefinedDiameter {
            strokeCircle(ctx: ctx, dr: dr, cx: maskRect.midX, cy: maskRect.midY,
                         d: refinedD, color: .green, lineWidth: 2)
        } else if let finalD = obs?.diameter {
            strokeCircle(ctx: ctx, dr: dr, cx: cx, cy: cy,
                         d: finalD, color: .green, lineWidth: 2)
        }

        // Green center dot follows the refined mask center when available.
        let dotCenter = obs?.maskBoundsRect.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: cx, y: cy)
        let dotPx = CGPoint(x: dr.minX + dotCenter.x * dr.width, y: dr.minY + dotCenter.y * dr.height)
        ctx.fill(Path(ellipseIn: CGRect(x: dotPx.x - 2.5, y: dotPx.y - 2.5, width: 5, height: 5)),
                 with: .color(.green))

        if settings.showBallPath, let allObs = metrics?.ball3DObservations, allObs.count >= 2 {
            drawBallPath(ctx: ctx, dr: dr, observations: allObs,
                         zeroDeg: settings.zeroDegreeAngleDeg,
                         show0DegRef: settings.show0DegRef)
        } else if settings.show0DegRef, let firstObs = metrics?.ball3DObservations.first {
            // Draw 0° ref even without full ball path
            let origin = normPointToView(CGPoint(x: firstObs.imageX, y: firstObs.imageY), dr: dr)
            draw0DegRef(ctx: ctx, dr: dr, origin: origin, zeroDeg: settings.zeroDegreeAngleDeg)
        }

        if settings.club.showClubTracker {
            drawClubOverlay(ctx: ctx, dr: dr, metrics: metrics, clubObs: clubObs)
        }
    }

    private func drawBallPath(ctx: GraphicsContext, dr: CGRect,
                               observations: [ExperimentalBall3DObservation],
                               zeroDeg: Double, show0DegRef: Bool) {
        var path = Path()
        for (i, obs) in observations.enumerated() {
            let pt = normPointToView(CGPoint(x: obs.imageX, y: obs.imageY), dr: dr)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        ctx.stroke(path, with: .color(.cyan.opacity(0.85)), style: StrokeStyle(lineWidth: 2, dash: [6, 3]))

        // Dots at each tracked point
        for obs in observations {
            let pt = normPointToView(CGPoint(x: obs.imageX, y: obs.imageY), dr: dr)
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2.5, y: pt.y - 2.5, width: 5, height: 5)),
                     with: .color(.cyan.opacity(0.65)))
        }

        if show0DegRef, let first = observations.first {
            let origin = normPointToView(CGPoint(x: first.imageX, y: first.imageY), dr: dr)
            draw0DegRef(ctx: ctx, dr: dr, origin: origin, zeroDeg: zeroDeg)
        }
    }

    /// Draws a dashed white 0° HLA reference line from `origin` in the given `zeroDeg` direction.
    private func draw0DegRef(ctx: GraphicsContext, dr: CGRect, origin: CGPoint, zeroDeg: Double) {
        let rad = zeroDeg * .pi / 180.0
        let len: CGFloat = min(dr.width, dr.height) * 0.32
        let end = CGPoint(x: origin.x + len * CGFloat(cos(rad)),
                          y: origin.y - len * CGFloat(sin(rad)))
        var refLine = Path()
        refLine.move(to: origin)
        refLine.addLine(to: end)
        ctx.stroke(refLine, with: .color(.white.opacity(0.85)),
                   style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        // Label at line end
        let labelPt = CGPoint(x: end.x + 5, y: end.y - 7)
        ctx.draw(
            Text("0° HLA ref").font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.8)),
            at: labelPt, anchor: .leading
        )
    }

    private func drawClubOverlay(
        ctx: GraphicsContext,
        dr: CGRect,
        metrics: ExperimentalShotMetricsResult?,
        clubObs: ExperimentalClubObservation?
    ) {
        if settings.club.showClubPath,
           let pathObservations = metrics?.clubObservations.filter({ $0.isDetected }),
           pathObservations.count >= 2 {
            var path = Path()
            var started = false
            for obs in pathObservations {
                guard let x = obs.centerX, let y = obs.centerY else { continue }
                let point = normPointToView(CGPoint(x: x, y: y), dr: dr)
                if started { path.addLine(to: point) } else { path.move(to: point); started = true }
            }
            // Orange solid line through clubhead centers (smooth, no zig-zag)
            ctx.stroke(path, with: .color(.orange.opacity(0.85)), style: StrokeStyle(lineWidth: 2))
            for obs in pathObservations {
                guard let x = obs.centerX, let y = obs.centerY else { continue }
                let pt = normPointToView(CGPoint(x: x, y: y), dr: dr)
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2.5, y: pt.y - 2.5, width: 5, height: 5)),
                         with: .color(.orange.opacity(0.65)))
            }
        }

        guard let clubObs else { return }

        if settings.club.showClubSearchROI, let roi = clubObs.searchROI {
            ctx.stroke(
                Path(normToView(roi, dr: dr)),
                with: .color(.orange.opacity(0.8)),
                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
            )
        }

        if settings.club.showBallExclusionZone,
           let x = clubObs.ballExclusionCenterX,
           let y = clubObs.ballExclusionCenterY,
           let d = clubObs.ballExclusionDiameter {
            strokeCircle(ctx: ctx, dr: dr, cx: x, cy: y, d: d, color: .orange.opacity(0.32), lineWidth: 1)
        }

        if let bbox = clubObs.clubBoundingBox {
            ctx.stroke(Path(normToView(bbox, dr: dr)), with: .color(.orange.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 2))
        }

        if let cx = clubObs.centerX, let cy = clubObs.centerY {
            let point = normPointToView(CGPoint(x: cx, y: cy), dr: dr)
            ctx.fill(
                Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)),
                with: .color(.orange)
            )
        }

        if let lx = clubObs.leadingEdgeX, let ly = clubObs.leadingEdgeY {
            let point = normPointToView(CGPoint(x: lx, y: ly), dr: dr)
            let rect = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
            ctx.stroke(Path(ellipseIn: rect), with: .color(.purple), lineWidth: 2.5)
            ctx.fill(Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)),
                     with: .color(.purple))
        }
    }

    private func strokeCircle(ctx: GraphicsContext, dr: CGRect,
                               cx: CGFloat, cy: CGFloat, d: CGFloat,
                               color: Color, lineWidth: CGFloat) {
        let radius = d * dr.width / 2
        let center = CGPoint(x: dr.minX + cx * dr.width, y: dr.minY + cy * dr.height)
        ctx.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                          width: radius * 2, height: radius * 2)),
                   with: .color(color), lineWidth: lineWidth)
    }

    private func normToView(_ rect: CGRect, dr: CGRect) -> CGRect {
        CGRect(x: dr.minX + rect.minX * dr.width, y: dr.minY + rect.minY * dr.height,
               width: rect.width * dr.width, height: rect.height * dr.height)
    }

    private func normPointToView(_ point: CGPoint, dr: CGRect) -> CGPoint {
        CGPoint(x: dr.minX + point.x * dr.width, y: dr.minY + point.y * dr.height)
    }

    // MARK: - Info overlay

    private func infoOverlay(seq: BallTrackingTestSequence,
                              obs: BallTrackingTestObservation?,
                              clubObs: ExperimentalClubObservation?) -> some View {
        let frame    = currentIndex < seq.frames.count ? seq.frames[currentIndex] : nil
        let detImpact = effectiveImpactIndex
        let isImpact  = frame?.frameIndex == detImpact
        let isPost    = (frame?.frameIndex ?? 0) > detImpact

        return VStack(alignment: .leading, spacing: 3) {
            // Line 1: frame + phase + time
            HStack(spacing: 8) {
                Text("Frame \(frame?.frameIndex ?? 0)").fontWeight(.semibold)
                Text(isImpact ? "IMPACT" : isPost ? "post" : "pre")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isImpact ? .red : isPost ? .orange : .secondary)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background((isImpact ? Color.red : isPost ? Color.orange : Color.secondary).opacity(0.2))
                    .clipShape(Capsule())
                if let t = frame?.relativeTime {
                    Text(String(format: "%+.1f ms", t * 1000)).foregroundColor(.secondary)
                }
            }
            // Line 2: center
            if let obs {
                if let cx = obs.centerX, let cy = obs.centerY {
                    Text(String(format: "x=%.4f  y=%.4f  conf=%.2f", cx, cy, obs.confidence))
                        .foregroundColor(.green)
                    // Line 3: diameter breakdown
                    let cD = obs.candidateDiameter.map   { String(format:"%.4f",$0) } ?? "—"
                    let rD = obs.maskRefinedDiameter.map { String(format:"%.4f",$0) } ?? "—"
                    let sD = obs.smoothedDiameter.map    { String(format:"%.4f",$0) } ?? "—"
                    Text("candidateD=\(cD)  refinedD=\(rD)  smoothedD=\(sD)  maskPx=\(obs.maskWhitePixelCount)")
                        .foregroundColor(.white.opacity(0.75))
                    Text("reason=\(obs.diameterDebugReason)")
                        .foregroundColor(.white.opacity(0.45))
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                        Text(obs.debugReason).foregroundColor(.orange).lineLimit(1)
                    }
                }
                // Line 4: ROI debug + scoring
                if let dbg = obs.frameDebug {
                    let acc = dbg.candidates.filter { $0.accepted }.count
                    Text("roi: \(dbg.searchCenterSource)  scale=\(String(format:"%.2f",dbg.searchScale))  cands=\(dbg.candidates.count)  acc=\(acc)")
                        .foregroundColor(.white.opacity(0.45))
                    if let sel = dbg.selectedCandidate {
                        Text(String(format: "score=%.2f  bright=%.2f  size=%.2f  dist=%.2f  motion=%.2f  dir=%.2f  shape=%.2f  pen=%.2f",
                                    sel.totalScore, sel.brightnessScore, sel.sizeScore,
                                    sel.distanceScore, sel.motionScore, sel.directionScore,
                                    sel.shapeScore, sel.penaltyScore))
                            .foregroundColor(.green.opacity(0.75))
                    }
                    if let pred = dbg.predictedPosition {
                        let j = dbg.jumpDistance.map { String(format:" jump=%.4f", $0) } ?? ""
                        Text(String(format: "pred=(%.4f,%.4f)%@", pred.x, pred.y, j))
                            .foregroundColor(.cyan.opacity(0.65))
                    }
                    // Launch direction / termination state (Parts A–C)
                    if dbg.ballHasLaunched, let ld = dbg.launchDirectionVector {
                        let prog = dbg.selectedCandidate?.progress.map { String(format:" prog=%.4f",$0) } ?? ""
                        let maxP = dbg.maxProgress.map { String(format:" maxP=%.4f",$0) } ?? ""
                        Text(String(format: "launched dir=(%.3f,%.3f)%@%@", ld.x, ld.y, prog, maxP))
                            .foregroundColor(.mint.opacity(0.85))
                    }
                    if dbg.ballTrackTerminated {
                        Text("⛔ BALL TRACK TERMINATED").foregroundColor(Color(red: 0.8, green: 0.2, blue: 0.2))
                    }
                    // Top-3 candidate table (Part G)
                    if settings.showScoreTable {
                        let top3 = dbg.candidates.filter { $0.accepted }
                            .sorted { $0.totalScore > $1.totalScore }.prefix(3)
                        ForEach(Array(top3.enumerated()), id: \.offset) { rank, c in
                            let sel = c.isSelected ? "★" : " "
                            Text(String(format: "%@#%d (%.3f,%.3f) d=%.4f tot=%.2f sz=%.2f dst=%.2f",
                                        sel, rank+1, c.centerX, c.centerY, c.diameter,
                                        c.totalScore, c.sizeScore, c.distanceScore))
                                .foregroundColor(c.isSelected ? .green : .yellow.opacity(0.8))
                        }
                        if let expD = dbg.expectedDiameter {
                            Text(String(format: "expDiam=%.4f", expD)).foregroundColor(.white.opacity(0.4))
                        }
                    }
                }

                if let clubObs {
                    if let lx = clubObs.leadingEdgeX, let ly = clubObs.leadingEdgeY {
                        Text(String(format: "club yes  lead=(%.4f,%.4f) conf=%.2f", lx, ly, clubObs.confidence))
                            .foregroundColor(.orange)
                    } else {
                        Text("club no  \(clubObs.debugReason)")
                            .foregroundColor(.orange.opacity(0.8))
                    }
                    if let roi = clubObs.searchROI {
                        Text(String(format: "clubROI=(%.3f,%.3f,%.3f,%.3f) diff=%@ excl=%@",
                                    roi.minX, roi.minY, roi.width, roi.height,
                                    clubObs.frameDifferenceWasUsed ? "yes" : "no",
                                    clubObs.ballExclusionWasApplied ? "yes" : "no"))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
            } else {
                Text(result == nil ? "Run tracker to see results" : "No observation")
                    .foregroundColor(.secondary)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.white)
        .padding(8)
        .background(Color.black.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    // MARK: - Mask preview inset

    private func maskPreviewInset(_ obs: BallTrackingTestObservation?) -> some View {
        let sz: CGFloat = 160
        return VStack(spacing: 0) {
            // Header row with legend
            HStack(spacing: 4) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text("old").font(.system(size: 8, design: .monospaced)).foregroundColor(.red.opacity(0.85))
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("new").font(.system(size: 8, design: .monospaced)).foregroundColor(.green.opacity(0.85))
                Spacer()
                Text("Mask Preview")
                    .font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.black.opacity(0.85))

            ZStack {
                Color.black
                if let img = obs?.maskPreviewImage {
                    Image(uiImage: img)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: sz, height: sz)

                    Canvas { ctx, size in
                        let half = size.width / 2
                        // Red circle — original candidate diameter
                        if let candD = obs?.maskCandidateDiamInCrop {
                            let r = candD * size.width / 2
                            let c = CGPoint(x: half, y: size.height / 2)
                            ctx.stroke(
                                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r,
                                                       width: r * 2, height: r * 2)),
                                with: .color(.red.opacity(0.9)), lineWidth: 1.5)
                        }
                        // Green circle — mask-refined diameter
                        if let refD = obs?.maskRefinedDiamInCrop {
                            let r = refD * size.width / 2
                            let c = refinedMaskCenterInCrop(obs, size: size) ?? CGPoint(x: half, y: size.height / 2)
                            ctx.stroke(
                                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r,
                                                       width: r * 2, height: r * 2)),
                                with: .color(.green.opacity(0.9)), lineWidth: 1.5)
                        }
                        // Center dot
                        let c = refinedMaskCenterInCrop(obs, size: size) ?? CGPoint(x: half, y: size.height / 2)
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)),
                                 with: .color(.yellow))
                    }
                    .frame(width: sz, height: sz)
                    .allowsHitTesting(false)
                } else {
                    let msg: String = {
                        if obs == nil            { return "no obs" }
                        if obs?.centerX == nil   { return "no ball" }
                        return "no mask"
                    }()
                    Text(msg)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: sz, height: sz)
                }
            }
            .frame(width: sz, height: sz)
        }
        .background(Color.black.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Frame strip

    private func frameStrip(_ seq: BallTrackingTestSequence) -> some View {
        let detImpact = effectiveImpactIndex
        let fallback  = result?.fallbackImpactFrameIndex ?? seq.impactFrameIndex
        let hasDiff   = result != nil && detImpact != fallback

        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(seq.frames.enumerated()), id: \.offset) { i, frame in
                        let fi        = frame.frameIndex
                        let isCurrent = i == currentIndex
                        let isDetImp  = fi == detImpact
                        let isFallImp = hasDiff && fi == fallback
                        let obs = result?.observations.first { $0.frameIndex == fi }
                        let clubDetected = result?.metrics?.clubObservations.first {
                            $0.frameIndex == fi && $0.isDetected
                        } != nil

                        let isTerminated = obs?.debugReason == "ball_track_terminated"
                        let blockColor: Color = isDetImp  ? .yellow
                            : isFallImp ? .yellow.opacity(0.35)
                            : obs?.centerX != nil ? .green
                            : isTerminated ? Color(red: 0.45, green: 0, blue: 0)
                            : result != nil ? .red
                            : Color(white: 0.25)

                        Button(action: { currentIndex = i }) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(blockColor.opacity(0.85))
                                .frame(width: 14, height: 28)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .stroke(Color.white, lineWidth: isCurrent ? 2 : 0)
                                )
                                .overlay(alignment: .bottom) {
                                    if clubDetected {
                                        Circle()
                                            .fill(Color.orange)
                                            .frame(width: 5, height: 5)
                                            .padding(.bottom, 2)
                                    }
                                }
                        }
                        .id(i)
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 40)
            .background(Color(white: 0.08))
            .onChange(of: currentIndex) { idx in
                withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(idx, anchor: .center) }
            }
        }
    }

    // MARK: - Navigation bar

    private func navigationBar(_ seq: BallTrackingTestSequence) -> some View {
        let last = max(0, seq.frames.count - 1)
        return HStack(spacing: 12) {
            Button(action: { if currentIndex > 0 { currentIndex -= 1 } }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(currentIndex > 0 ? .white : .white.opacity(0.25))
            }.frame(width: 44, height: 44)
            Slider(value: Binding(
                get: { Double(currentIndex) },
                set: { currentIndex = Int($0.rounded()) }
            ), in: 0...Double(last), step: 1).tint(.white)
            Button(action: { if currentIndex < last { currentIndex += 1 } }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(currentIndex < last ? .white : .white.opacity(0.25))
            }.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(white: 0.10))
    }

    // MARK: - Controls sidebar

    private var controlsSidebar: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                trackerModePicker

                TunerSection(title: "Global") {
                    TunerSlider(label: "sampleStride", value: $settings.sampleStride,
                                range: 1...8, format: "%.0f", isInt: true)
                }

                TunerSection(title: "Pre-impact") {
                    TunerSlider(label: "brightness ≥", value: $settings.preBrightnessThreshold,
                                range: 40...240, format: "%.0f", isInt: true)
                    TunerSlider(label: "spread ≤",     value: $settings.preMaxChannelSpread,
                                range: 10...180, format: "%.0f", isInt: true)
                    TunerSlider(label: "minSamples",   value: $settings.preMinBrightSamples,
                                range: 1...100, format: "%.0f", isInt: true)
                    TunerSlider(label: "minW",    value: $settings.preMinNormWidth,  range: 0.001...0.25, format: "%.3f")
                    TunerSlider(label: "maxW",    value: $settings.preMaxNormWidth,  range: 0.001...0.25, format: "%.3f")
                    TunerSlider(label: "minH",    value: $settings.preMinNormHeight, range: 0.001...0.25, format: "%.3f")
                    TunerSlider(label: "maxH",    value: $settings.preMaxNormHeight, range: 0.001...0.25, format: "%.3f")
                    TunerSlider(label: "minAspect", value: $settings.preMinAspect, range: 0.05...8.0, format: "%.2f")
                    TunerSlider(label: "maxAspect", value: $settings.preMaxAspect, range: 0.05...8.0, format: "%.2f")
                }

                TunerSection(title: "Post-impact") {
                    TunerSlider(label: "brightness ≥", value: $settings.postBrightnessThreshold,
                                range: 40...240, format: "%.0f", isInt: true)
                    TunerSlider(label: "spread ≤",     value: $settings.postMaxChannelSpread,
                                range: 10...180, format: "%.0f", isInt: true)
                    TunerSlider(label: "minSamples",   value: $settings.postMinBrightSamples,
                                range: 1...100, format: "%.0f", isInt: true)
                    TunerSlider(label: "minW",    value: $settings.postMinNormWidth,  range: 0.001...0.25, format: "%.3f")
                    TunerSlider(label: "maxW",    value: $settings.postMaxNormWidth,  range: 0.001...0.25, format: "%.3f")
                    TunerSlider(label: "minH",    value: $settings.postMinNormHeight, range: 0.001...0.25, format: "%.3f")
                    TunerSlider(label: "maxH",    value: $settings.postMaxNormHeight, range: 0.001...0.25, format: "%.3f")
                    TunerSlider(label: "minAspect", value: $settings.postMinAspect, range: 0.05...8.0, format: "%.2f")
                    TunerSlider(label: "maxAspect", value: $settings.postMaxAspect, range: 0.05...8.0, format: "%.2f")
                }

                TunerSection(title: "Search ROI") {
                    TunerSlider(label: "preScale",    value: $settings.preImpactSearchScale, range: 1...40, format: "%.2f")
                    TunerSlider(label: "impactScale", value: $settings.impactSearchScale,    range: 1...40, format: "%.2f")
                    TunerSlider(label: "postBase",    value: $settings.postImpactBaseScale,  range: 1...40, format: "%.2f")
                    TunerSlider(label: "postGrowth",  value: $settings.postImpactScaleGrowth,range: 0...5,  format: "%.2f")
                    TunerSlider(label: "postMax",     value: $settings.postImpactMaxScale,   range: 1...40, format: "%.1f")
                }

                TunerSection(title: "Calibration / 3D") {
                    TunerSlider(label: "horizontal FOV", value: $settings.calibration.horizontalFOVDegrees,
                                range: 35...110, format: "%.1f")
                    TunerSlider(label: "vertical FOV", value: $settings.calibration.verticalFOVDegrees,
                                range: 25...90, format: "%.1f")
                    TunerSlider(label: "ball diameter mm", value: Binding(
                        get: { settings.calibration.realBallDiameterMeters * 1000 },
                        set: { settings.calibration.realBallDiameterMeters = $0 / 1000 }
                    ), range: 35...50, format: "%.2f")
                    TunerToggle(label: "camera height", value: $settings.calibration.useCameraHeight)
                    TunerSlider(label: "height m", value: $settings.calibration.cameraHeightMeters,
                                range: 0...2.5, format: "%.2f")
                    TunerToggle(label: "camera tilt", value: $settings.calibration.useCameraTilt)
                    TunerSlider(label: "tilt deg", value: $settings.calibration.cameraTiltDegrees,
                                range: -45...45, format: "%.1f")
                    calibrationDerivedReadout
                    Button(action: { settings.calibration.resetDefaults() }) {
                        Text("Reset calibration defaults")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                }

                TunerSection(title: "Distance Model") {
                    TunerSlider(label: "carry correction",
                                value: $settings.carryCorrectionFactor,
                                range: 0.40...1.20, format: "%.2f")
                }

                TunerSection(title: "Impact Detection") {
                    TunerSlider(label: "moveThreshold",  value: $settings.impact.movementThresholdNorm,
                                range: 0.001...0.030, format: "%.3f")
                    TunerSlider(label: "confirmFrames",  value: $settings.impact.confirmFrames,
                                range: 1...5, format: "%.0f", isInt: true)
                    TunerSlider(label: "stableWindow",   value: $settings.impact.stableWindowCount,
                                range: 3...20, format: "%.0f", isInt: true)
                }

                TunerSection(title: "Diameter / Mask Refinement") {
                    TunerToggle(label: "enabled",          value: $settings.diameter.enabled)
                    TunerSlider(label: "maskWindowScale",  value: $settings.diameter.localMaskWindowScale,
                                range: 0.5...4.0, format: "%.2f")
                    TunerSlider(label: "absBrightThresh",  value: $settings.diameter.maskBrightness,
                                range: 5...200, format: "%.0f", isInt: true)
                    TunerSlider(label: "minDiameter",      value: $settings.diameter.minDiameterNorm,
                                range: 0.001...0.10, format: "%.3f")
                    TunerSlider(label: "maxDiameter",      value: $settings.diameter.maxDiameterNorm,
                                range: 0.01...0.30, format: "%.3f")
                    TunerToggle(label: "combineMode=max",  value: $settings.diameter.combineModeIsMax)
                    TunerToggle(label: "smoothing",        value: $settings.diameter.smoothingEnabled)
                    TunerSlider(label: "medianWindow",     value: $settings.diameter.smoothingWindowSize,
                                range: 2...15, format: "%.0f", isInt: true)
                    // Part A — percentile mask threshold
                    TunerToggle(label: "percentile threshold", value: $settings.diameter.usePercentileMaskThreshold)
                    TunerSlider(label: "whiteness %ile",   value: $settings.diameter.maskWhitenessPercentile,
                                range: 50...99, format: "%.0f")
                    TunerSlider(label: "pct minBright",    value: $settings.diameter.maskPercentileMinBrightness,
                                range: 20...150, format: "%.0f", isInt: true)
                    TunerSlider(label: "pct maxBright",    value: $settings.diameter.maskPercentileMaxBrightness,
                                range: 150...255, format: "%.0f", isInt: true)
                    TunerSlider(label: "bg suppress Δ",   value: $settings.diameter.maskBackgroundSuppressionDelta,
                                range: 0...50, format: "%.0f", isInt: true)
                    // Part B — diameter growth gates
                    TunerToggle(label: "hard clamp diameter", value: $settings.diameter.hardClampDiameter)
                    TunerSlider(label: "maxGrowth/frame",  value: $settings.diameter.maxDiameterGrowthRatioPerFrame,
                                range: 1.0...3.0, format: "%.2f")
                    TunerSlider(label: "maxRatio/preImpact", value: $settings.diameter.maxDiameterRatioToPreImpactMedian,
                                range: 1.0...5.0, format: "%.2f")
                    TunerToggle(label: "show candidate rect", value: $settings.showOriginalCandidateBounds)
                    TunerToggle(label: "show mask preview",  value: $settings.showMaskPreview)
                    TunerToggle(label: "show ball path",     value: $settings.showBallPath)
                    TunerToggle(label: "show 0° ref line",   value: $settings.show0DegRef)
                    TunerSlider(label: "0° ref angle",       value: $settings.zeroDegreeAngleDeg,
                                range: -45...45, format: "%.1f")
                }

                TunerSection(title: "Ball Candidate Scoring") {
                    TunerToggle(label: "show candidate IDs",  value: $settings.showCandidateIDs)
                    TunerToggle(label: "show score table",    value: $settings.showScoreTable)
                    TunerSlider(label: "brightness wt",  value: $settings.scoring.brightnessScoreWeight,
                                range: 0...5, format: "%.2f")
                    TunerSlider(label: "size wt",        value: $settings.scoring.sizeScoreWeight,
                                range: 0...5, format: "%.2f")
                    TunerSlider(label: "distance wt",    value: $settings.scoring.distanceScoreWeight,
                                range: 0...5, format: "%.2f")
                    TunerSlider(label: "motion wt",      value: $settings.scoring.motionScoreWeight,
                                range: 0...5, format: "%.2f")
                    TunerSlider(label: "direction wt",   value: $settings.scoring.directionScoreWeight,
                                range: 0...5, format: "%.2f")
                    TunerSlider(label: "shape wt",       value: $settings.scoring.shapeScoreWeight,
                                range: 0...5, format: "%.2f")
                    TunerSlider(label: "jump penalty wt", value: $settings.scoring.jumpPenaltyWeight,
                                range: 0...10, format: "%.2f")
                    TunerSlider(label: "maxJump norm",   value: $settings.scoring.maxJumpDistanceNorm,
                                range: 0.01...0.50, format: "%.3f")
                    TunerToggle(label: "motion prediction",       value: $settings.scoring.useMotionPrediction)
                    TunerSlider(label: "lookback frames",  value: $settings.scoring.predictionLookbackFrames,
                                range: 2...6, format: "%.0f", isInt: true)
                    TunerToggle(label: "direction constraint",     value: $settings.scoring.useDirectionConstraint)
                    TunerSlider(label: "direction penalty wt", value: $settings.scoring.directionPenaltyWeight,
                                range: 0...5, format: "%.2f")
                    TunerToggle(label: "diameter constraint",      value: $settings.scoring.useExpectedDiameterConstraint)
                    TunerSlider(label: "min diam ratio",  value: $settings.scoring.minDiameterRatioToExpected,
                                range: 0.1...1.0, format: "%.2f")
                    TunerSlider(label: "max diam ratio",  value: $settings.scoring.maxDiameterRatioToExpected,
                                range: 1.0...5.0, format: "%.2f")
                    TunerToggle(label: "hard reject extreme diam", value: $settings.scoring.hardRejectExtremeDiameter)
                    TunerSlider(label: "extreme diam ratio", value: $settings.scoring.extremeMaxDiameterRatio,
                                range: 1.5...8.0, format: "%.2f")
                    TunerToggle(label: "reject club-like",         value: $settings.scoring.rejectClubLikeCandidates)
                    TunerSlider(label: "club max aspect",  value: $settings.scoring.clubLikeMaxAspect,
                                range: 1.5...10.0, format: "%.1f")
                    TunerToggle(label: "exclusion zones",          value: $settings.scoring.useExclusionZones)
                    TunerToggle(label: "zone 1 enabled",           value: $settings.scoring.exclusionZone1Enabled)
                    TunerSlider(label: "zone1 y",  value: $settings.scoring.exclusionZone1Y,  range: 0...1, format: "%.2f")
                    TunerSlider(label: "zone1 h",  value: $settings.scoring.exclusionZone1H,  range: 0...1, format: "%.2f")
                    TunerSlider(label: "zone1 x",  value: $settings.scoring.exclusionZone1X,  range: 0...1, format: "%.2f")
                    TunerSlider(label: "zone1 w",  value: $settings.scoring.exclusionZone1W,  range: 0...1, format: "%.2f")
                    TunerToggle(label: "zone 2 enabled",           value: $settings.scoring.exclusionZone2Enabled)
                    TunerSlider(label: "zone2 x",  value: $settings.scoring.exclusionZone2X,  range: 0...1, format: "%.2f")
                    TunerSlider(label: "zone2 y",  value: $settings.scoring.exclusionZone2Y,  range: 0...1, format: "%.2f")
                    TunerSlider(label: "zone2 w",  value: $settings.scoring.exclusionZone2W,  range: 0...1, format: "%.2f")
                    TunerSlider(label: "zone2 h",  value: $settings.scoring.exclusionZone2H,  range: 0...1, format: "%.2f")
                    TunerToggle(label: "hard reject in zone",      value: $settings.scoring.hardRejectInsideExclusion)
                    Button(action: { settings.scoring.resetDefaults() }) {
                        Text("Reset scoring defaults")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                    }
                }

                TunerSection(title: "Launch & Termination") {
                    TunerToggle(label: "monotonic progress",   value: $settings.scoring.useMonotonicProgressConstraint)
                    TunerSlider(label: "lock distance",  value: $settings.scoring.minLaunchProgressToLockDirection,
                                range: 0.005...0.10, format: "%.3f")
                    TunerSlider(label: "allowed backward", value: $settings.scoring.allowedBackwardProgressNorm,
                                range: 0...0.05, format: "%.4f")
                    TunerSlider(label: "backward penalty", value: $settings.scoring.backwardPenaltyWeight,
                                range: 0...10, format: "%.2f")
                    TunerToggle(label: "hard reject backward", value: $settings.scoring.hardRejectBackwardAfterLaunch)
                    TunerToggle(label: "lost-ball termination", value: $settings.scoring.enableLostBallTermination)
                    TunerSlider(label: "miss frame limit",  value: $settings.scoring.lostBallMissFrameLimit,
                                range: 1...10, format: "%.0f", isInt: true)
                    TunerSlider(label: "min progress req",  value: $settings.scoring.lostBallMinProgressBeforeTermination,
                                range: 0...0.30, format: "%.3f")
                    TunerToggle(label: "reacquire after term", value: $settings.scoring.allowReacquireAfterTermination)
                    TunerToggle(label: "show launch arrow",   value: $settings.showLaunchDirection)
                }

                TunerSection(title: "Pre-Launch Rejection (Part A)") {
                    TunerToggle(label: "hard reject behind start", value: $settings.scoring.hardRejectBehindStart)
                    TunerToggle(label: "use ref progress", value: $settings.scoring.useReferenceProgressBeforeLaunch)
                    TunerSlider(label: "min progress norm", value: $settings.scoring.minAllowedProgressBeforeLaunch,
                                range: -0.05...0.0, format: "%.4f")
                }

                TunerSection(title: "Pre-Impact ROI (Part F)") {
                    TunerToggle(label: "asymmetric ROI", value: $settings.useAsymmetricPreImpactROI)
                    TunerSlider(label: "fwd scale", value: $settings.preImpactForwardExpansionScale,
                                range: 1...20, format: "%.1f")
                    TunerSlider(label: "bwd scale", value: $settings.preImpactBackwardExpansionScale,
                                range: 0.5...8, format: "%.1f")
                    TunerSlider(label: "vert scale", value: $settings.preImpactVerticalExpansionScale,
                                range: 0.5...8, format: "%.1f")
                    TunerSlider(label: "near fwd scale", value: $settings.nearImpactForwardExpansionScale,
                                range: 1...25, format: "%.1f")
                    TunerSlider(label: "near bwd scale", value: $settings.nearImpactBackwardExpansionScale,
                                range: 0.5...8, format: "%.1f")
                    TunerSlider(label: "near vert scale", value: $settings.nearImpactVerticalExpansionScale,
                                range: 0.5...8, format: "%.1f")
                    TunerSlider(label: "near window frames", value: $settings.nearImpactWindowFrames,
                                range: 1...10, format: "%.0f", isInt: true)
                }

                TunerSection(title: "Post-Impact ROI (Part A)") {
                    TunerSlider(label: "fwd scale", value: $settings.postImpactForwardExpansionScale,
                                range: 1...20, format: "%.1f")
                    TunerSlider(label: "bwd scale", value: $settings.postImpactBackwardExpansionScale,
                                range: 0.5...5, format: "%.1f")
                    TunerSlider(label: "vert (untracked)", value: $settings.postImpactVerticalScaleUntracked,
                                range: 0.5...5, format: "%.1f")
                    TunerSlider(label: "vert (tracked)", value: $settings.postImpactVerticalScaleTracked,
                                range: 0.5...8, format: "%.1f")
                    TunerSlider(label: "reliable track min pts", value: $settings.reliableTrackMinPostImpactPoints,
                                range: 1...6, format: "%.0f", isInt: true)
                }

                TunerSection(title: "Near-Impact Diam Guard (Part C)") {
                    TunerToggle(label: "enable guard", value: $settings.enableNearImpactDiameterJumpGuard)
                    TunerSlider(label: "guard window frames", value: $settings.nearImpactDiameterGuardWindow,
                                range: 1...5, format: "%.0f", isInt: true)
                    TunerSlider(label: "max growth ratio", value: $settings.maxNearImpactDiameterGrowth,
                                range: 1.0...3.0, format: "%.2f")
                    TunerSlider(label: "min shrink ratio", value: $settings.minNearImpactDiameterShrink,
                                range: 0.3...1.0, format: "%.2f")
                }

                TunerSection(title: "Prelim Mask Scoring (Part D)") {
                    TunerToggle(label: "enable prelim mask", value: $settings.enablePrelimMaskScoring)
                    TunerSlider(label: "roundness weight", value: $settings.prelimRoundnessWeight,
                                range: 0...10, format: "%.1f")
                    TunerToggle(label: "reject line-like", value: $settings.prelimRejectLineLike)
                }

                TunerSection(title: "Clean First Point (Part E)") {
                    TunerToggle(label: "require clean first pt for prediction",
                                value: $settings.requireCleanFirstPointForPrediction)
                }

                TunerSection(title: "HLA Closeness (Part H)") {
                    TunerSlider(label: "closeness weight", value: $settings.scoring.hlaClosenessWeight,
                                range: 0...8, format: "%.1f")
                    TunerSlider(label: "max cand HLA °", value: $settings.scoring.maxCandidateHLADegrees,
                                range: 5...90, format: "%.0f", isInt: true)
                }

                TunerSection(title: "Prediction Boost (new session C)") {
                    TunerToggle(label: "enable pred boost", value: $settings.scoring.enablePredictionBoost)
                    TunerSlider(label: "inside bonus", value: $settings.scoring.predictionInsideBonus,
                                range: 0...8, format: "%.1f")
                    TunerSlider(label: "near bonus", value: $settings.scoring.predictionNearBonus,
                                range: 0...6, format: "%.1f")
                    TunerSlider(label: "boost radius", value: $settings.scoring.predictionBoostRadiusNorm,
                                range: 0.005...0.15, format: "%.3f")
                    TunerSlider(label: "dist penalty w", value: $settings.scoring.predictionDistPenaltyWeight,
                                range: 0...8, format: "%.1f")
                }

                TunerSection(title: "Merged Club-Ball (new session B)") {
                    TunerToggle(label: "enable merged reject", value: $settings.scoring.enableMergedClubBallReject)
                    TunerSlider(label: "max diam ratio", value: $settings.scoring.maxFirstPostImpactDiameterRatio,
                                range: 1.0...4.0, format: "%.2f")
                    TunerSlider(label: "window frames", value: $settings.scoring.mergedCandidateFrameWindow,
                                range: 1...8, format: "%.0f", isInt: true)
                }

                TunerSection(title: "Off-Path Reject (new session E)") {
                    TunerToggle(label: "hard reject far off-path", value: $settings.scoring.hardRejectFarOffPath)
                    TunerSlider(label: "max off-path dist", value: $settings.scoring.maxOffPathDistNorm,
                                range: 0...0.2, format: "%.3f")
                }

                TunerSection(title: "Prediction Termination (new session F)") {
                    TunerToggle(label: "disable pred after miss", value: $settings.scoring.disablePredictionAfterMiss)
                    TunerSlider(label: "miss limit", value: $settings.scoring.predictionMissLimit,
                                range: 1...8, format: "%.0f", isInt: true)
                }

                TunerSection(title: "VLA from Diameter (Part A/D)") {
                    TunerToggle(label: "use diam growth VLA", value: $settings.useDiameterGrowthForVLA)
                    TunerSlider(label: "growth→VLA scale", value: $settings.diameterGrowthToVLAScale,
                                range: 10...300, format: "%.0f")
                    TunerSlider(label: "diam growth weight", value: $settings.diameterGrowthVLAWeight,
                                range: 0...1, format: "%.2f")
                    TunerSlider(label: "image-Y VLA weight", value: $settings.imageYVLAWeight,
                                range: 0...1, format: "%.2f")
                }

                TunerSection(title: "VLA Model (new session)") {
                    Picker("VLA Mode", selection: $settings.vlaEstimationMode) {
                        Text("Legacy").tag(VLAEstimationMode.legacy)
                        Text("Pinhole2D").tag(VLAEstimationMode.pinhole2DSize)
                        Text("Blended").tag(VLAEstimationMode.blended)
                        Text("Ground").tag(VLAEstimationMode.groundCalibrated)
                        Text("Trained").tag(VLAEstimationMode.trainedModel)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)
                    TunerSlider(label: "img-Y weight", value: $settings.vlaImageYWeight,
                                range: 0...1, format: "%.2f")
                    TunerSlider(label: "depth weight", value: $settings.vlaDiameterDepthWeight,
                                range: 0...1, format: "%.2f")
                    TunerSlider(label: "depth sign", value: $settings.vlaDepthSign,
                                range: -1...1, format: "%.1f")
                    TunerSlider(label: "persp. strength", value: $settings.rightwardSizeCorrectionStrength,
                                range: 0...1, format: "%.2f")
                    TunerSlider(label: "max VLA pinhole", value: $settings.maxVLAPinholeDegrees,
                                range: 0...70, format: "%.0f")
                }

                TunerSection(title: "Diameter Shrink (Part C)") {
                    TunerToggle(label: "hard clamp shrink", value: $settings.diameter.hardClampDiameterShrink)
                    TunerSlider(label: "min shrink ratio", value: $settings.diameter.minDiameterShrinkRatioPerFrame,
                                range: 0.30...1.0, format: "%.2f")
                }

                TunerSection(title: "Face Prior (Part A)") {
                    TunerToggle(label: "use ball HLA face prior", value: $settings.scoring.useBallHLAFacePrior)
                    TunerSlider(label: "ball HLA weight", value: $settings.scoring.facePriorBallHLAWeight,
                                range: 0...1, format: "%.2f")
                    TunerSlider(label: "club path weight", value: $settings.scoring.facePriorClubPathWeight,
                                range: 0...1, format: "%.2f")
                    TunerSlider(label: "max prior dev °", value: $settings.scoring.maxFacePriorDeviationDegrees,
                                range: 5...90, format: "%.0f")
                    TunerSlider(label: "prior score weight", value: $settings.scoring.facePriorScoreWeight,
                                range: 0...10, format: "%.1f")
                    TunerToggle(label: "suppress if far from HLA", value: $settings.scoring.suppressFaceIfFarFromBallHLA)
                    TunerSlider(label: "max face-HLA diff °", value: $settings.scoring.maxFaceBallHLADifferenceDegrees,
                                range: 5...60, format: "%.0f")
                }

                TunerSection(title: "Early Merged Shape (Part B)") {
                    TunerToggle(label: "enable early merged stopper", value: $settings.scoring.enableEarlyMergedShapeStopper)
                    TunerSlider(label: "frame window", value: Binding(
                        get: { Double(settings.scoring.mergedShapeFrameWindowAfterImpact) },
                        set: { settings.scoring.mergedShapeFrameWindowAfterImpact = Int($0.rounded()) }
                    ), range: 1...8, format: "%.0f", isInt: true)
                    TunerSlider(label: "max diam spike ratio", value: $settings.scoring.maxEarlyDiameterSpikeRatio,
                                range: 1.0...3.0, format: "%.2f")
                    TunerSlider(label: "max impact spike ratio", value: $settings.scoring.maxImpactDiameterSpikeRatio,
                                range: 1.0...3.0, format: "%.2f")
                    TunerSlider(label: "max area spike ratio", value: $settings.scoring.maxEarlyAreaSpikeRatio,
                                range: 1.0...5.0, format: "%.2f")
                    TunerToggle(label: "require spike then drop", value: $settings.scoring.requireSpikeThenDropCheck)
                    TunerSlider(label: "spike-drop ratio thr", value: $settings.scoring.spikeDropRatioThreshold,
                                range: 0...1, format: "%.2f")
                    TunerSlider(label: "max gradual growth/fr", value: $settings.scoring.maxGradualGrowthRatioPerFrame,
                                range: 1.0...2.0, format: "%.2f")
                }

                TunerSection(title: "Cone Search (Part C)") {
                    TunerToggle(label: "use cone search region", value: $settings.scoring.useConeSearchRegion)
                    TunerSlider(label: "half angle °", value: $settings.scoring.coneHalfAngleDegrees,
                                range: 5...60, format: "%.0f")
                    TunerSlider(label: "initial length norm", value: $settings.scoring.coneInitialLengthNorm,
                                range: 0.01...0.5, format: "%.3f")
                    TunerSlider(label: "length growth/frame", value: $settings.scoring.coneLengthGrowthPerFrameNorm,
                                range: 0.005...0.1, format: "%.3f")
                    TunerSlider(label: "max length norm", value: $settings.scoring.coneMaxLengthNorm,
                                range: 0.2...1.0, format: "%.2f")
                    TunerSlider(label: "backward allowance", value: $settings.scoring.coneBackwardAllowanceNorm,
                                range: 0...0.05, format: "%.3f")
                    TunerToggle(label: "use launch direction", value: $settings.scoring.coneUseLaunchDirectionWhenAvailable)
                }

                TunerSection(title: "Full Frame Recovery (Part D)") {
                    TunerToggle(label: "enable after cone miss", value: $settings.scoring.enableFullFrameRecoveryAfterConeMiss)
                    TunerSlider(label: "min mask pixels", value: Binding(
                        get: { Double(settings.scoring.recoveryMinMaskWhitePixels) },
                        set: { settings.scoring.recoveryMinMaskWhitePixels = Int($0.rounded()) }
                    ), range: 5...50, format: "%.0f", isInt: true)
                    TunerSlider(label: "min fill ratio", value: $settings.scoring.recoveryMinMaskFillRatio,
                                range: 0...0.5, format: "%.2f")
                    TunerSlider(label: "max line residual", value: $settings.scoring.recoveryMaxLineResidualNorm,
                                range: 0...0.1, format: "%.3f")
                }

                TunerSection(title: "Vertical Jump Gate (Part F)") {
                    TunerToggle(label: "hard reject large down jump", value: $settings.scoring.hardRejectLargeDownwardJumpAfterLaunch)
                    TunerSlider(label: "max down jump/frame", value: $settings.scoring.maxDownwardJumpPerFrameNorm,
                                range: 0.01...0.15, format: "%.3f")
                    TunerToggle(label: "use fitted path gate", value: $settings.scoring.useFittedPathForVerticalGate)
                    TunerSlider(label: "max vert from path", value: $settings.scoring.maxVerticalJumpFromPathNorm,
                                range: 0.01...0.15, format: "%.3f")
                    TunerSlider(label: "vert jump penalty", value: $settings.scoring.verticalJumpPenaltyWeight,
                                range: 0...10, format: "%.1f")
                }

                TunerSection(title: "Prediction Cross Rescue") {
                    TunerToggle(label: "enable", value: $settings.scoring.enablePredictionCrossRescue)
                    TunerSlider(label: "radius norm", value: $settings.scoring.predictionRescueRadiusNorm,
                                range: 0.01...0.15, format: "%.3f")
                    TunerSlider(label: "window frames", value: $settings.scoring.predictionRescueWindowAfterLaunch,
                                range: 1...20, format: "%.0f", isInt: true)
                    TunerSlider(label: "max consec misses", value: $settings.scoring.predictionRescueMaxConsecMisses,
                                range: 1...5, format: "%.0f", isInt: true)
                    TunerSlider(label: "inside bonus", value: $settings.scoring.predictionRescueInsideBonus,
                                range: 0...15, format: "%.1f")
                    TunerSlider(label: "near bonus", value: $settings.scoring.predictionRescueNearBonus,
                                range: 0...10, format: "%.1f")
                    TunerToggle(label: "allow borderline mask", value: $settings.scoring.predictionRescueAllowBorderlineMask)
                    TunerSlider(label: "min mask pixels", value: $settings.scoring.predictionRescueMinMaskPixels,
                                range: 2...30, format: "%.0f", isInt: true)
                    TunerSlider(label: "min fill ratio", value: $settings.scoring.predictionRescueMinFillRatio,
                                range: 0.01...0.2, format: "%.3f")
                    TunerToggle(label: "require fwd progress", value: $settings.scoring.predictionRescueRequireFwdProgress)
                    TunerToggle(label: "disable after termination", value: $settings.scoring.predictionRescueDisableAfterTerm)
                }

                TunerSection(title: "Offscreen/Edge Rejection (Part C)") {
                    TunerToggle(label: "reject partial offscreen ball", value: $settings.scoring.rejectEdgePartialBall)
                    TunerSlider(label: "min ball margin norm", value: $settings.scoring.minBallMarginNorm,
                                range: 0.002...0.05, format: "%.4f")
                }

                TunerSection(title: "Final Edge Ball Filter (Post-Rescue)") {
                    TunerToggle(label: "enable final edge filter", value: $settings.scoring.enableFinalEdgeBallFilter)
                    TunerSlider(label: "edge margin norm", value: $settings.scoring.finalEdgeMarginNorm,
                                range: 0.002...0.05, format: "%.4f")
                    TunerSlider(label: "radius margin scale", value: $settings.scoring.finalEdgeRadiusMarginScale,
                                range: 0.5...2.0, format: "%.2f")
                    TunerToggle(label: "exclude from metrics", value: $settings.scoring.excludeEdgeBallFromMetrics)
                }

                TunerSection(title: "Line-Like Mask Rejection (Part D)") {
                    TunerToggle(label: "reject line-like mask", value: $settings.diameter.rejectLineLikeMask)
                    TunerSlider(label: "max mask aspect", value: $settings.diameter.maxMaskAspectForBall,
                                range: 1.0...5.0, format: "%.1f")
                    TunerSlider(label: "min mask aspect", value: $settings.diameter.minMaskAspectForBall,
                                range: 0.1...1.0, format: "%.2f")
                    TunerSlider(label: "line-like aspect threshold", value: $settings.diameter.lineLikeAspectThreshold,
                                range: 1.5...8.0, format: "%.1f")
                    TunerSlider(label: "line-like fill max", value: $settings.diameter.lineLikeFillMax,
                                range: 0.01...0.5, format: "%.3f")
                    TunerSlider(label: "min component pixels", value: $settings.diameter.minMaskComponentPixelsForBall,
                                range: 2...30, format: "%.0f", isInt: true)
                }

                TunerSection(title: "Single-Point Prediction (Part E)") {
                    TunerToggle(label: "enable single-point prediction", value: $settings.scoring.enableSinglePointPrediction)
                    TunerSlider(label: "max step", value: $settings.scoring.singlePointPredictionMaxStep,
                                range: 0.005...0.3, format: "%.3f")
                    TunerSlider(label: "min step", value: $settings.scoring.singlePointPredictionMinStep,
                                range: 0.001...0.05, format: "%.4f")
                }

                TunerSection(title: "Impact Detection — Diameter Change (Part A)") {
                    TunerToggle(label: "use diameter change detection", value: $settings.impact.useDiameterChange)
                    TunerSlider(label: "diam change ratio", value: $settings.impact.diameterChangeRatio,
                                range: 1.0...3.0, format: "%.2f")
                    TunerSlider(label: "diam shrink ratio", value: $settings.impact.diameterShrinkRatio,
                                range: 0.3...1.0, format: "%.2f")
                    TunerToggle(label: "return one frame before", value: $settings.impact.returnOneFrameBefore)
                    TunerSlider(label: "min stable frames", value: $settings.impact.minimumStableFrames,
                                range: 2...12, format: "%.0f", isInt: true)
                }

                TunerSection(title: "Club Tracking") {
                    TunerToggle(label: "enabled", value: $settings.club.enabled)
                    TunerToggle(label: "search behind ball", value: $settings.club.searchBehindBallEnabled)
                    TunerSlider(label: "ball exclusion x", value: $settings.club.ballExclusionRadiusScale,
                                range: 0.5...5.0, format: "%.2f")
                    TunerSlider(label: "roi scale X", value: $settings.club.clubSearchROIScaleX,
                                range: 1...20, format: "%.1f")
                    TunerSlider(label: "roi scale Y", value: $settings.club.clubSearchROIScaleY,
                                range: 1...15, format: "%.1f")
                    TunerToggle(label: "frame difference", value: $settings.club.useFrameDifference)
                    TunerSlider(label: "diff threshold", value: $settings.club.frameDifferenceThreshold,
                                range: 1...120, format: "%.0f", isInt: true)
                    TunerSlider(label: "dark/edge threshold", value: $settings.club.minClubDarknessOrEdgeThreshold,
                                range: 10...180, format: "%.0f", isInt: true)
                    TunerSlider(label: "min blob area", value: $settings.club.minClubBlobArea,
                                range: 1...300, format: "%.0f", isInt: true)
                    TunerSlider(label: "max blob area", value: $settings.club.maxClubBlobArea,
                                range: 100...20000, format: "%.0f", isInt: true)
                    TunerSlider(label: "min confidence", value: $settings.club.minClubConfidence,
                                range: 0...1, format: "%.2f")
                    TunerToggle(label: "debug logging", value: $settings.club.debugLoggingEnabled)
                    TunerToggle(label: "show club tracker", value: $settings.club.showClubTracker)
                    TunerToggle(label: "show club ROI", value: $settings.club.showClubSearchROI)
                    TunerToggle(label: "show club path", value: $settings.club.showClubPath)
                    TunerToggle(label: "show exclusion zone", value: $settings.club.showBallExclusionZone)
                    Button(action: { settings.club.resetDefaults() }) {
                        Text("Reset club defaults")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                }

                Button(action: { settings = BallTrackingTuningSettings() }) {
                    Text("Reset Defaults")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.orange)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .padding(.top, 4)
            }
            .padding(.bottom, 20)
        }
        .background(Color(white: 0.07))
    }

    private var trackerModePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TRACKER MODE")
                .font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                .padding(.horizontal, 12).padding(.top, 12)
            VStack(spacing: 1) {
                ForEach(FrameNormalizationMode.allCases, id: \.self) { mode in
                    Button(action: { settings.trackingMode = mode }) {
                        HStack {
                            Text(mode.displayName).font(.system(size: 12)).foregroundColor(.white)
                            Spacer()
                            if settings.trackingMode == mode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.purple)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(settings.trackingMode == mode ? Color.purple.opacity(0.15) : Color.clear)
                    }
                }
            }
            Divider().background(Color.white.opacity(0.1))
        }
    }

    private var calibrationDerivedReadout: some View {
        let width = sequence?.frames.first?.image.cgImage?.width ?? 0
        let height = sequence?.frames.first?.image.cgImage?.height ?? 0
        let calibration = ExperimentalCameraCalibration.from(
            settings: settings.calibration,
            imageWidth: width,
            imageHeight: height
        )
        return VStack(alignment: .leading, spacing: 3) {
            Text("image \(width)x\(height) px")
            Text(String(format: "fx=%.1f  fy=%.1f", calibration.focalLengthPixelsX, calibration.focalLengthPixelsY))
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundColor(.white.opacity(0.55))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func loadExport(_ url: URL) {
        do {
            let seq = try loader.loadSequence(from: url)
            sequence = seq; currentIndex = seq.impactFrameIndex; result = nil; loadError = nil; exportStatus = nil
        } catch { loadError = error.localizedDescription }
    }

    private func runTracker() {
        guard let seq = sequence, !isRunning else { return }
        isRunning = true
        exportStatus = nil
        // LIVE-PARITY REPLAY: runs the exact production pipeline (FrameNormalizer +
        // PostImpactBallTracker + ShotMetricsCalculator + validation gates) on the loaded
        // export. Tuning happens in the live components directly — the tester settings
        // panels for the old ExperimentalBallTracker no longer affect this run.
        print("[Replay] running LIVE pipeline on \(seq.sourceName) (\(seq.frames.count) frames, impact=\(seq.impactFrameIndex))")
        Task.detached(priority: .userInitiated) {
            let output = LiveParityTestRunner().run(sequence: seq)
            await MainActor.run {
                self.result = output.result
                self.isRunning = false
                self.exportStatus = output.lockUsedAutoDerive
                    ? "\(output.verdict) · auto-lock"
                    : output.verdict
            }
        }
    }

    private func exportExperimentalMetrics() {
        guard let sequence, let result else { return }
        do {
            let url = try ExperimentalMetricsExporter().export(
                sequence: sequence,
                result: result,
                settings: settings
            )
            exportStatus = "exported \(url.lastPathComponent)"
        } catch {
            exportStatus = error.localizedDescription
        }
    }

    // MARK: - Geometry helpers

    private func aspectFitRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return .zero }
        let scale = min(containerSize.width / imageSize.width,
                        containerSize.height / imageSize.height)
        let w = imageSize.width * scale, h = imageSize.height * scale
        return CGRect(x: (containerSize.width - w) / 2,
                      y: (containerSize.height - h) / 2, width: w, height: h)
    }

    private func frameCount(in url: URL) -> Int? {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return contents?.filter { $0.pathExtension == "png" }.count
    }

    private func refinedMaskCenterInCrop(_ obs: BallTrackingTestObservation?, size: CGSize) -> CGPoint? {
        guard let bounds = obs?.maskBoundsRect,
              let crop = obs?.maskCropNormRect,
              crop.width > 0,
              crop.height > 0 else {
            return nil
        }

        return CGPoint(
            x: ((bounds.midX - crop.minX) / crop.width) * size.width,
            y: ((bounds.midY - crop.minY) / crop.height) * size.height
        )
    }

    private func mph(_ value: Double?) -> String {
        value.map { String(format: "%.1f mph", $0) } ?? "—"
    }

    private func degrees(_ value: Double?) -> String {
        value.map { String(format: "%.1f°", $0) } ?? "—"
    }

    private func yards(_ value: Double?) -> String {
        value.map { String(format: "%.0f yd", $0) } ?? "—"
    }

    private func plain(_ value: Double?, digits: Int) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(digits)f", value)
    }
}

// MARK: - Reusable controls

private struct TunerSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)
            content()
            Divider().background(Color.white.opacity(0.1)).padding(.top, 6)
        }
    }
}

private struct TunerSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var isInt: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(isInt ? "\(Int(value.rounded()))" : String(format: format, value))
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(.white)
                    .frame(width: 52, alignment: .trailing)
            }
            Slider(value: $value, in: range).tint(.purple)
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
    }
}

private struct TunerToggle: View {
    let label: String
    @Binding var value: Bool
    var body: some View {
        HStack {
            Text(label).font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.8))
            Spacer()
            Toggle("", isOn: $value).toggleStyle(.switch).scaleEffect(0.75, anchor: .trailing).labelsHidden()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
}

// MARK: - Keyboard navigation

struct KeyboardNavigatorView: UIViewRepresentable {
    let onLeft:  () -> Void
    let onRight: () -> Void
    func makeUIView(context: Context) -> _KeyNavView {
        let v = _KeyNavView(); v.onLeft = onLeft; v.onRight = onRight; return v
    }
    func updateUIView(_ uiView: _KeyNavView, context: Context) {
        uiView.onLeft = onLeft; uiView.onRight = onRight
    }
    class _KeyNavView: UIView {
        var onLeft:  (() -> Void)?
        var onRight: (() -> Void)?
        override var canBecomeFirstResponder: Bool { true }
        override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { becomeFirstResponder() } }
        override var keyCommands: [UIKeyCommand]? {[
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow,  modifierFlags: [], action: #selector(handleLeft)),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(handleRight))
        ]}
        @objc private func handleLeft()  { onLeft?() }
        @objc private func handleRight() { onRight?() }
    }
}
#endif
