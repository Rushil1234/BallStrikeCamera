import SwiftUI

// MARK: - Golf Ball Helper

private func drawGolfBall(ctx: GraphicsContext, center: CGPoint, radius r: CGFloat, phaseColor: Color) {
    ctx.fill(Path(ellipseIn: CGRect(x: center.x-r*2.2, y: center.y-r*2.2, width: r*4.4, height: r*4.4)),
             with: .color(phaseColor.opacity(0.15)))
    ctx.fill(Path(ellipseIn: CGRect(x: center.x-r, y: center.y-r, width: r*2, height: r*2)),
             with: .color(.white))
    ctx.stroke(Path(ellipseIn: CGRect(x: center.x-r, y: center.y-r, width: r*2, height: r*2)),
               with: .color(Color(white: 0.72)), lineWidth: max(0.5, r*0.08))
    let dr = max(0.8, r*0.14)
    let dc = Color(white: 0.68).opacity(0.80)
    for (dx, dy): (CGFloat, CGFloat) in [(-r*0.38,-r*0.38),(r*0.38,-r*0.38),(0,0),(-r*0.38,r*0.38),(r*0.38,r*0.38)] {
        ctx.fill(Path(ellipseIn: CGRect(x: center.x+dx-dr, y: center.y+dy-dr, width: dr*2, height: dr*2)),
                 with: .color(dc))
    }
    let ar = max(0.6, r*0.11)
    ctx.fill(Path(ellipseIn: CGRect(x: center.x-ar, y: center.y-ar, width: ar*2, height: ar*2)),
             with: .color(phaseColor.opacity(0.55)))
}

// MARK: - ShotResultView

struct ShotResultView: View {
    let analysis: ShotAnalysisResult
    var context: ShotContext? = nil
    var selectedClubId: UUID? = nil
    var selectedClubName: String? = nil
    var onShotSaved: ((SavedShot) -> Void)? = nil
    let onDone: () -> Void

    @State private var animationStartDate: Date? = nil
    @State private var animationFinished: Bool   = false
    @State private var showReplay: Bool          = false

    // Course-mode save state
    @EnvironmentObject private var session: AuthSessionStore
    @State private var isSavingCourseShot = false

    private var m: ShotMetricsResult? { analysis.metrics }

    static let airborneColor = Color(red: 0.02, green: 0.16, blue: 0.42)
    static let rolloutColor  = Color(red: 0.02, green: 0.34, blue: 0.14)
    static let totalColor    = Color(red: 0.62, green: 1.00, blue: 0.48)
    static let metricValueColor = Color.white
    static let metricLabelColor = Color.white.opacity(0.55)

    init(analysis: ShotAnalysisResult,
         context: ShotContext? = nil,
         selectedClubId: UUID? = nil,
         selectedClubName: String? = nil,
         onShotSaved: ((SavedShot) -> Void)? = nil,
         onDone: @escaping () -> Void) {
        self.analysis = analysis
        self.context = context
        self.selectedClubId = selectedClubId
        self.selectedClubName = selectedClubName
        self.onShotSaved = onShotSaved
        self.onDone = onDone
    }

    // MARK: - Timing

    private var durations: (flight: Double, rollout: Double) {
        guard let spd = m?.ballLaunch.ballSpeedMph,
              let vla = m?.ballLaunch.vlaDegrees,
              spd > 0, vla > 0 else { return (3.0, 1.2) }
        let speedMps = spd * 0.44704
        let vertVel  = speedMps * sin(vla * .pi / 180.0)
        let hang     = max(0.8, min(7.0, 2.0 * vertVel / 9.81))
        let flt      = min(max(hang * 1.25, 2.4), 6.5)
        let rollYd   = max(0, (m?.distance.totalYards ?? 0) - (m?.distance.carryYards ?? 0))
        let roll     = min(max(rollYd / 20.0 * 1.20, 0.6), 3.0)
        return (flt, roll)
    }

    private var hasRollout: Bool {
        max(0, (m?.distance.totalYards ?? 0) - (m?.distance.carryYards ?? 0)) > 0.2
    }

    private var totalDuration: Double {
        let d = durations; return hasRollout ? d.flight + d.rollout : d.flight
    }

    private func progressValues(elapsed: Double) -> (fp: Double, rp: Double) {
        let d = durations
        let t  = min(max(elapsed / max(d.flight, 0.001), 0), 1)
        let fp = 1 - pow(1 - t, 3)
        guard hasRollout else { return (fp, 0) }
        let s = elapsed > d.flight ? min((elapsed - d.flight) / max(d.rollout, 0.001), 1) : 0
        return (fp, s * s)
    }

    // MARK: - Body

    var body: some View {
        rangeResultBody
    }

    private var rangeResultBody: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                topBar

                TimelineView(.animation(minimumInterval: nil, paused: animationFinished)) { tl in
                    let elapsed   = animationStartDate.map { tl.date.timeIntervalSince($0) } ?? 0.0
                    let (fp, rp)  = progressValues(elapsed: max(0, elapsed))
                    let showCarry = fp >= 1.0
                    let showTotal = rp >= 1.0

                    HStack(spacing: 0) {
                        // Left: side-view + overlays
                        ZStack(alignment: .top) {
                            Canvas { ctx, size in
                                drawSideView(ctx: ctx, size: size, fp: fp, rp: rp,
                                             showCarry: showCarry, showTotal: showTotal)
                            }
                            // Metrics top-right (Part A/J)
                            HStack {
                                Spacer()
                                metricsOverlay
                                    .padding(.top, 6).padding(.trailing, 6)
                            }
                            // Tap prompt bottom-center (Part I)
                            VStack {
                                Spacer()
                                tapPromptOverlay.padding(.bottom, 20)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1)

                        Rectangle().fill(Color.white.opacity(0.09)).frame(width: 1)

                        // Right: satellite landing map (course) or abstract top-down grid (range)
                        if context?.sourceMode == .course, let ctx = context {
                            CourseLandingMapView(
                                context: ctx,
                                metrics: m,
                                flightProgress: fp,
                                rolloutProgress: rp
                            )
                            .frame(width: geo.size.width * 0.44)
                        } else {
                            Canvas { ctx, size in
                                drawTopDown(ctx: ctx, size: size, fp: fp, rp: rp,
                                            showCarry: showCarry, showTotal: showTotal)
                            }
                            .frame(width: geo.size.width * 0.30)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                metricsBar
            }
        }
        .background(Color(white: 0.06).ignoresSafeArea())
        .tcAppearance()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .contentShape(Rectangle())
        .onTapGesture { guard animationFinished else { return }; openReplay() }
        .onAppear { startAnimation() }
        .fullScreenCover(isPresented: $showReplay) {
            ShotTrackingReviewView(
                analysis: analysis,
                context: context,
                selectedClubId: selectedClubId,
                selectedClubName: selectedClubName,
                onShotSaved: onShotSaved
            ) {
                showReplay = false
                onDone()
            }
        }
    }

    // MARK: - Course Result Body

    private var courseResultBody: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(context?.courseName ?? "Course")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                Spacer()
                if let hole = context?.holeNumber {
                    Text("Hole \(hole)\(context?.holePar.map { " · Par \($0)" } ?? "")")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 8)

            Spacer()

            // Club + hero distance
            VStack(spacing: 6) {
                if let club = selectedClubName {
                    Text(club.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .tracking(2)
                        .foregroundColor(Color(red: 0.55, green: 0.73, blue: 0.37))
                }
                Text(yds(m?.distance.totalYards ?? m?.distance.carryYards))
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("TOTAL DISTANCE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.5))
            }

            // Carry / yd-to-pin / direction
            HStack(spacing: 0) {
                courseStat("Carry", yds(m?.distance.carryYards))
                divider
                courseStat("To Pin", ydToPin)
                divider
                courseStat("Direction", m?.ballLaunch.hlaDisplay ?? "—")
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)

            Spacer()

            // Primary action: persist + return to the course (where the flight plays).
            Button {
                Task { await saveAndContinue() }
            } label: {
                HStack(spacing: 8) {
                    if isSavingCourseShot { ProgressView().tint(.black) }
                    else { Image(systemName: "scope") }
                    Text(isSavingCourseShot ? "Saving…" : "View Ball Flight on Course")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(red: 0.55, green: 0.73, blue: 0.37))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSavingCourseShot)
            .padding(.horizontal, 20)

            Button("Discard") { onDone() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .padding(.top, 14)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.06).ignoresSafeArea())
        .tcAppearance()
        .statusBarHidden(true)
    }

    private var ydToPin: String {
        guard let carry = m?.distance.totalYards ?? m?.distance.carryYards,
              let yd = context?.holeYardage else { return "—" }
        return "\(max(0, yd - Int(carry)))"
    }

    private func courseStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 32)
    }

    /// Persist the shot, then hand it back so the course screen can animate the flight.
    private func saveAndContinue() async {
        guard !isSavingCourseShot else { return }
        guard let uid = session.currentUser?.id, let metrics = analysis.metrics else {
            onDone(); return
        }
        isSavingCourseShot = true
        defer { isSavingCourseShot = false }
        do {
            let service = ShotPersistenceService(userId: uid, backend: session.backend)
            let impact = analysis.detectedImpactFrameIndex
            let frames = analysis.frames
                .sorted { $0.frameIndex < $1.frameIndex }
                .filter { abs($0.frameIndex - impact) <= 5 }
                .map { $0.originalFrame.image }
            let shot = try await service.saveShot(
                metrics: SavedShotMetrics(metrics),
                compositeImage: nil,
                originalFrames: frames,
                clubId: selectedClubId,
                clubName: selectedClubName,
                mode: context?.shotMode ?? .course,
                saveOriginalFrames: false,
                roundId: context?.courseRoundId,
                holeNumber: context?.holeNumber,
                isBadShot: false,
                badShotReason: nil
            )
            onShotSaved?(shot)
        } catch {
            // Even if remote save fails, returning lets the user place the shot manually.
        }
        onDone()
    }

    // MARK: - Animation Control

    private func startAnimation() {
        animationStartDate = Date()
        animationFinished  = false
        let total = totalDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + total) {
            guard !animationFinished else { return }
            animationFinished = true
        }
    }

    private func skipToEnd() {
        animationStartDate = Date(timeIntervalSinceNow: -(totalDuration + 0.5))
        animationFinished  = true
    }

    private func openReplay() { showReplay = true }

    // MARK: - Course Context Panel (right side for course mode)

    private var courseContextPanel: some View {
        VStack(spacing: 0) {
            // Course info header
            VStack(spacing: 6) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color(red: 0.55, green: 0.73, blue: 0.37))

                if let name = context?.courseName {
                    Text(name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.70))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                if let hole = context?.holeNumber {
                    Text("Hole \(hole)")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(.white)
                }

                if let par = context?.holePar {
                    Text("Par \(par)")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.50))
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().background(Color.white.opacity(0.12))

            // Carry to par remaining
            VStack(spacing: 8) {
                if let carry = m?.distance.carryYards,
                   let yd = context?.holeYardage {
                    let remaining = max(0, yd - Int(carry))
                    VStack(spacing: 2) {
                        Text("\(remaining)")
                            .font(.system(size: 26, weight: .black))
                            .foregroundColor(Self.metricValueColor)
                        Text("yd left")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Self.metricLabelColor)
                    }
                }

                VStack(spacing: 2) {
                    Text(yds(m?.distance.carryYards))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Self.metricValueColor)
                    Text("carry")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Self.metricLabelColor)
                }
            }
            .padding(.top, 10)

            Spacer()

            // Direction indicator
            if let hla = m?.ballLaunch.hlaDegrees {
                VStack(spacing: 4) {
                    Image(systemName: hla < -1 ? "arrow.up.left" :
                                      hla > 1  ? "arrow.up.right" : "arrow.up")
                        .font(.system(size: 18))
                        .foregroundColor(Self.metricValueColor)
                    Text(m?.ballLaunch.hlaDisplay ?? "")
                        .font(.system(size: 9))
                        .foregroundColor(Self.metricLabelColor)
                }
                .padding(.bottom, 10)
            }
        }
        .background(Color(white: 0.08))
    }

    // MARK: - Top Bar

    private var topBar: some View {
        let doneLabel = context?.sourceMode == .course ? "Discard" : "Done"
        return HStack(spacing: 8) {
            Button(doneLabel) { onDone() }
                .font(.system(size: 14, weight: .semibold)).foregroundColor(.blue)
            Spacer()
            Text("Shot Result").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
            Spacer()
            if !animationFinished {
                Button("Skip ›") { skipToEnd() }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.70))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.white.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            Button("GO BACK TO HITTING") { onDone() }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.white.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Color(white: 0.10))
    }

    // MARK: - Tap Prompt (Part I: displayed inside left animation)

    private var tapPromptOverlay: some View {
        let finishedLabel = context?.sourceMode == .course
            ? "Tap to save & view flight"
            : "Tap to view frame replay"
        return Group {
            if animationFinished {
                Text(finishedLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .transition(.opacity.combined(with: .scale(scale: 0.93)))
            } else {
                Text("Shot in flight…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.30))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.40), value: animationFinished)
    }

    // MARK: - Metrics Overlay (Carry / Rollout / Total only)

    private var rolloutYds: String {
        guard let t = m?.distance.totalYards, let c = m?.distance.carryYards else { return "--" }
        let r = max(0, t - c)
        return r < 0.5 ? "--" : yds(r)
    }

    private var metricsOverlay: some View {
        VStack(alignment: .leading, spacing: 3) {
            metricRow("Carry",   yds(m?.distance.carryYards))
            metricRow("Rollout", rolloutYds)
            metricRow("Total",   yds(m?.distance.totalYards))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.black.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Self.metricLabelColor)
                .frame(width: 42, alignment: .leading)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Self.metricValueColor)
        }
    }

    // MARK: - Bottom Metrics Bar

    private var metricsBar: some View {
        HStack(spacing: 0) {
            metricCard("Carry",      yds(m?.distance.carryYards))
            metricCard("Total",      yds(m?.distance.totalYards))
            metricCard("Ball Speed", spd(m?.ballLaunch.ballSpeedMph))
            metricCard("Club Speed", spd(m?.club.clubSpeedMph))
            metricCard("HLA",        m?.ballLaunch.hlaDisplay ?? "--")
            metricCard("VLA",        vlaDeg(m?.ballLaunch.vlaDegrees))
        }
        .padding(.vertical, 8)
        .background(Color.black)
    }

    private func metricCard(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Self.metricValueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.60)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Self.metricLabelColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Peak Height

    private var peakHeightYards: Double {
        guard let spd = m?.ballLaunch.ballSpeedMph,
              let vla = m?.ballLaunch.vlaDegrees, spd > 0, vla > 0 else {
            return max(5.0, (m?.distance.carryYards ?? 100) * 0.12)
        }
        let vertVel = spd * 0.44704 * sin(vla * .pi / 180.0)
        return max((vertVel * vertVel) / (2.0 * 9.81) * 1.09361, 4.0)
    }

    // MARK: - Side-View Canvas

    private func drawSideView(ctx: GraphicsContext, size: CGSize,
                               fp: Double, rp: Double,
                               showCarry: Bool, showTotal: Bool) {
        let totalYd = m?.distance.totalYards ?? m?.distance.carryYards ?? 100
        let carryYd = m?.distance.carryYards ?? totalYd
        let rollYd  = max(0, totalYd - carryYd)
        let peakYd  = peakHeightYards

        // Part B: nice feet-based y scale
        let peakFt: Double = peakYd * 3.0
        let niceSteps: [Double] = [25, 50, 75, 100, 125, 150, 200, 250, 300]
        let yAxisMaxFt = niceSteps.first { $0 >= peakFt } ?? 300.0
        let tickFtInt: Double  = yAxisMaxFt <= 100 ? 25 : (yAxisMaxFt <= 200 ? 50 : 100)
        let yRange = yAxisMaxFt / 3.0   // yards; grid top aligns to yAxisMaxFt

        let groundY:  CGFloat = size.height * 0.78
        let leftPad:  CGFloat = 48
        let rightPad: CGFloat = 14
        let topPad:   CGFloat = 16
        let xRange = totalYd * 1.08
        let plotW  = size.width - leftPad - rightPad
        let plotH  = groundY - topPad

        func sx(_ yd: Double) -> CGFloat { leftPad + CGFloat(yd / xRange) * plotW }
        func sy(_ yd: Double) -> CGFloat { groundY - CGFloat(yd / yRange) * plotH }

        // Part C: asymmetric flight curve (peaks at ~69% of carry, steeper descent)
        func asymFlightH(_ x: Double) -> Double {
            guard carryYd > 0, x > 0, x < carryYd else { return 0 }
            let p = x / carryYd
            let rExp = 1.1, fExp = 0.50
            let peakP = rExp / (rExp + fExp)
            let normF = pow(peakP, rExp) * pow(1.0 - peakP, fExp)
            return peakYd * pow(p, rExp) * pow(1.0 - p, fExp) / normF
        }

        let teeX   = sx(0)
        let carryX = sx(carryYd)
        let totalX = sx(totalYd)
        let ballXFlight = carryYd * fp

        // Background
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.06)))

        // Part B: horizontal height gridlines + y-axis labels in feet
        var tickFt = 0.0
        while tickFt <= yAxisMaxFt + 0.1 {
            let tickY = sy(tickFt / 3.0)
            guard tickY >= topPad - 2 && tickY <= groundY + 2 else { tickFt += tickFtInt; continue }
            if tickFt > 0 {
                var h = Path()
                h.move(to: CGPoint(x: leftPad, y: tickY))
                h.addLine(to: CGPoint(x: size.width - rightPad, y: tickY))
                ctx.stroke(h, with: .color(Color.white.opacity(0.08)), lineWidth: 1)
            }
            let lbl = tickFt == 0 ? "0" : String(format: "%.0f ft", tickFt)
            ctx.draw(Text(lbl).font(.system(size: 8, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.40)),
                     at: CGPoint(x: leftPad - 4, y: tickY), anchor: .trailing)
            tickFt += tickFtInt
        }

        // Ground line
        var gnd = Path()
        gnd.move(to: CGPoint(x: 0, y: groundY)); gnd.addLine(to: CGPoint(x: size.width, y: groundY))
        ctx.stroke(gnd, with: .color(Color.white.opacity(0.28)), lineWidth: 1.5)

        // Part B: x-axis yard labels
        let stepYd: Double = totalYd <= 75 ? 25 : (totalYd <= 150 ? 50 : 100)
        var tickYd = stepYd
        while tickYd < totalYd {
            let tx = sx(tickYd)
            var tick = Path()
            tick.move(to: CGPoint(x: tx, y: groundY - 4)); tick.addLine(to: CGPoint(x: tx, y: groundY + 4))
            ctx.stroke(tick, with: .color(Color.white.opacity(0.18)), lineWidth: 1)
            ctx.draw(Text("\(Int(tickYd))").font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.28)),
                     at: CGPoint(x: tx, y: groundY + 14), anchor: .center)
            tickYd += stepYd
        }

        // Tee peg
        var tee = Path()
        tee.move(to: CGPoint(x: teeX - 6, y: groundY - 8)); tee.addLine(to: CGPoint(x: teeX + 6, y: groundY - 8))
        tee.move(to: CGPoint(x: teeX, y: groundY - 8));     tee.addLine(to: CGPoint(x: teeX, y: groundY))
        ctx.stroke(tee, with: .color(Color.white.opacity(0.65)),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round))

        // Max height label (Part B: top-left, always visible)
        ctx.draw(Text(String(format: "Max Ht  %.0f ft", peakFt))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Self.airborneColor.opacity(0.60)),
                 at: CGPoint(x: leftPad + 6, y: topPad + 2), anchor: .topLeading)

        // Part C: progressive airborne arc (asymmetric curve)
        if fp > 0.001 {
            let steps    = 80
            let stepSize = max(ballXFlight / Double(steps), 0.001)
            var arcPath  = Path()
            var arcFirst = true
            var xi = 0.0
            while xi <= ballXFlight {
                let ht = xi == 0 ? 0 : asymFlightH(xi)
                let pt = CGPoint(x: sx(xi), y: sy(ht))
                if arcFirst { arcPath.move(to: pt); arcFirst = false } else { arcPath.addLine(to: pt) }
                xi += stepSize
            }
            let finalHt = ballXFlight == 0 ? 0 : asymFlightH(min(ballXFlight, carryYd - 0.001))
            if !arcFirst { arcPath.addLine(to: CGPoint(x: sx(ballXFlight), y: sy(finalHt))) }
            ctx.stroke(arcPath, with: .color(Self.airborneColor),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }

        // Rollout with bounces
        if fp >= 1.0 && rollYd > 0.2 {
            if rollYd < 2.0 {
                // Pure roll, no bounce
                if rp > 0.001 {
                    var rp2 = Path()
                    rp2.move(to: CGPoint(x: carryX, y: groundY - 1))
                    rp2.addLine(to: CGPoint(x: sx(carryYd + rollYd * rp), y: groundY - 1))
                    ctx.stroke(rp2, with: .color(Self.rolloutColor),
                               style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                }
            } else if rollYd <= 6.0 {
                // One bounce: rp 0→0.45, then roll rp 0.45→1
                let b1Dist = rollYd * 0.45
                let b1Ht   = min(max(0.667, peakYd * 0.03), 1.0)
                let drawB1Frac = rp < 0.45 ? rp / 0.45 : 1.0
                let drawB1Max  = max(1, Int(20.0 * drawB1Frac))
                var b1Path = Path(); var b1First = true
                for i in 0...drawB1Max {
                    let p  = Double(i) / 20.0
                    let xi = carryYd + b1Dist * p
                    let ht = b1Ht * 4.0 * p * (1.0 - p)
                    let pt = CGPoint(x: sx(xi), y: sy(ht))
                    if b1First { b1Path.move(to: pt); b1First = false } else { b1Path.addLine(to: pt) }
                }
                ctx.stroke(b1Path, with: .color(Self.rolloutColor.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 3.0, lineCap: .round))
                if rp >= 0.45 {
                    let rollP = (rp - 0.45) / 0.55
                    var rl = Path()
                    rl.move(to: CGPoint(x: sx(carryYd + b1Dist), y: groundY - 1))
                    rl.addLine(to: CGPoint(x: sx(carryYd + b1Dist + (rollYd - b1Dist) * rollP), y: groundY - 1))
                    ctx.stroke(rl, with: .color(Self.rolloutColor),
                               style: StrokeStyle(lineWidth: 4.0, lineCap: .round))
                }
            } else {
                // Two bounces: rp 0→0.50 (b1), 0.50→0.70 (b2), 0.70→1.0 (roll)
                let b1Dist = rollYd * 0.50, b1Ht = min(peakYd * 0.08, 1.0)
                let b2Dist = rollYd * 0.20, b2Ht = min(peakYd * 0.04, 0.417)
                let b2Start = b1Dist; let rollStart = b1Dist + b2Dist
                // Bounce 1
                let drawB1Frac = rp < 0.50 ? rp / 0.50 : 1.0
                let drawB1Max  = max(1, Int(20.0 * drawB1Frac))
                var b1Path = Path(); var b1First = true
                for i in 0...drawB1Max {
                    let p = Double(i) / 20.0
                    let pt = CGPoint(x: sx(carryYd + b1Dist * p), y: sy(b1Ht * 4.0 * p * (1-p)))
                    if b1First { b1Path.move(to: pt); b1First = false } else { b1Path.addLine(to: pt) }
                }
                ctx.stroke(b1Path, with: .color(Self.rolloutColor.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 3.0, lineCap: .round))
                // Bounce 2
                if rp >= 0.50 {
                    let drawB2Frac = rp < 0.70 ? (rp - 0.50) / 0.20 : 1.0
                    let drawB2Max  = max(1, Int(20.0 * drawB2Frac))
                    var b2Path = Path(); var b2First = true
                    for i in 0...drawB2Max {
                        let p = Double(i) / 20.0
                        let pt = CGPoint(x: sx(carryYd + b2Start + b2Dist * p), y: sy(b2Ht * 4.0 * p * (1-p)))
                        if b2First { b2Path.move(to: pt); b2First = false } else { b2Path.addLine(to: pt) }
                    }
                    ctx.stroke(b2Path, with: .color(Self.rolloutColor.opacity(0.70)),
                               style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
                // Final roll
                if rp >= 0.70 {
                    let rollP = (rp - 0.70) / 0.30
                    var rl = Path()
                    rl.move(to: CGPoint(x: sx(carryYd + rollStart), y: groundY - 1))
                    rl.addLine(to: CGPoint(x: sx(carryYd + rollStart + (rollYd - rollStart) * rollP), y: groundY - 1))
                    ctx.stroke(rl, with: .color(Self.rolloutColor),
                               style: StrokeStyle(lineWidth: 4.0, lineCap: .round))
                }
            }
        }

        // Ball position (bounce-aware during rollout)
        let ballPos: CGPoint
        let ballColor: Color
        if fp >= 1.0 && rp > 0.002 && rollYd > 0.2 {
            ballColor = Self.rolloutColor
            if rollYd < 2.0 {
                ballPos = CGPoint(x: sx(carryYd + rollYd * rp), y: groundY - 1)
            } else if rollYd <= 6.0 {
                let b1Dist = rollYd * 0.45, b1Ht = min(max(0.667, peakYd * 0.03), 1.0)
                if rp < 0.45 {
                    let p = rp / 0.45
                    ballPos = CGPoint(x: sx(carryYd + b1Dist * p), y: sy(b1Ht * 4.0 * p * (1-p)))
                } else {
                    let rollP = (rp - 0.45) / 0.55
                    ballPos = CGPoint(x: sx(carryYd + b1Dist + (rollYd - b1Dist) * rollP), y: groundY - 1)
                }
            } else {
                let b1Dist = rollYd * 0.50, b1Ht = min(peakYd * 0.08, 1.0)
                let b2Dist = rollYd * 0.20, b2Ht = min(peakYd * 0.04, 0.417)
                let b2Start = b1Dist; let rollStart = b1Dist + b2Dist
                if rp < 0.50 {
                    let p = rp / 0.50
                    ballPos = CGPoint(x: sx(carryYd + b1Dist * p), y: sy(b1Ht * 4.0 * p * (1-p)))
                } else if rp < 0.70 {
                    let p = (rp - 0.50) / 0.20
                    ballPos = CGPoint(x: sx(carryYd + b2Start + b2Dist * p), y: sy(b2Ht * 4.0 * p * (1-p)))
                } else {
                    let rollP = (rp - 0.70) / 0.30
                    ballPos = CGPoint(x: sx(carryYd + rollStart + (rollYd - rollStart) * rollP), y: groundY - 1)
                }
            }
        } else {
            let ht = ballXFlight > 0 && ballXFlight < carryYd ? asymFlightH(ballXFlight) : 0
            ballPos   = CGPoint(x: sx(ballXFlight), y: sy(ht))
            ballColor = Self.airborneColor
        }
        drawGolfBall(ctx: ctx, center: ballPos, radius: 10, phaseColor: ballColor)

        // Carry marker
        if showCarry {
            var drop = Path()
            drop.move(to: CGPoint(x: carryX, y: sy(peakYd * 0.15)))
            drop.addLine(to: CGPoint(x: carryX, y: groundY))
            ctx.stroke(drop, with: .color(Self.airborneColor.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            ctx.fill(Path(ellipseIn: CGRect(x: carryX-5, y: groundY-5, width: 10, height: 10)),
                     with: .color(Self.airborneColor))
            ctx.draw(Text(String(format: "Carry  %.0f yd", carryYd))
                        .font(.system(size: 11, weight: .bold)).foregroundColor(Self.airborneColor),
                     at: CGPoint(x: carryX, y: groundY + 22), anchor: .center)
        }

        // Total marker
        if showTotal {
            ctx.fill(Path(ellipseIn: CGRect(x: totalX-7, y: groundY-7, width: 14, height: 14)),
                     with: .color(Self.totalColor))
            ctx.draw(Text(String(format: "Total  %.0f yd", totalYd))
                        .font(.system(size: 11, weight: .bold)).foregroundColor(Self.totalColor),
                     at: CGPoint(x: totalX, y: groundY + 40), anchor: .center)
            if rollYd > 0.5 {
                ctx.draw(Text(String(format: "Roll  %.0f yd", rollYd))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Self.rolloutColor.opacity(0.85)),
                         at: CGPoint(x: totalX, y: groundY + 54), anchor: .center)
            }
        }
    }

    // MARK: - Top-Down Canvas (Parts F, G, H)

    private func drawTopDown(ctx: GraphicsContext, size: CGSize,
                              fp: Double, rp: Double,
                              showCarry: Bool, showTotal: Bool) {
        let totalYd  = m?.distance.totalYards ?? m?.distance.carryYards ?? 100
        let carryYd  = m?.distance.carryYards ?? totalYd
        let hlaRad = (m?.ballLaunch.hlaDegrees ?? 0) * .pi / 180.0

        // Monotonic curve — single bend direction, no S-curve
        let spinAxis = m?.spin.estimatedSpinAxisDegreesSigned
        let sidespin = m?.spin.estimatedSidespinRpmSigned
        let curveStrength: Double
        if let sa = spinAxis, abs(sa) > 0.5 {
            curveStrength = (sa > 0 ? 1.0 : -1.0) * min(abs(sa) / 16.0, 1.0)
        } else if let ss = sidespin, abs(ss) > 30 {
            curveStrength = (ss > 0 ? 1.0 : -1.0) * min(abs(ss) / 1100.0, 1.0)
        } else {
            curveStrength = 0
        }
        let curveMagnitude = abs(curveStrength) * max(totalYd * 0.10, 8.0)
        let curveSign: Double = curveStrength >= 0 ? 1.0 : -1.0

        // lateral(p) = HLA component + monotonic curve component
        func offAt(_ p: Double) -> Double {
            tan(hlaRad) * totalYd * p + curveSign * curveMagnitude * pow(max(0, p), 1.6)
        }

        // Scale: sample path to find max lateral extent
        var maxSampledOff = 0.0
        for i in 0...20 { maxSampledOff = max(maxSampledOff, abs(offAt(Double(i) / 20.0))) }
        let neededOff = max(maxSampledOff, 5.0)
        let maxOff: Double
        if      neededOff <= 10 { maxOff = 20 }
        else if neededOff <= 20 { maxOff = 30 }
        else if neededOff <= 30 { maxOff = 40 }
        else if neededOff <= 45 { maxOff = 55 }
        else                    { maxOff = ceil((neededOff + 15) / 10) * 10 }
        let downNice: [Double] = [50, 100, 150, 200, 250, 300, 350, 400]
        let maxDown = downNice.first { $0 >= totalYd * 1.08 } ?? 400.0

        let padH: CGFloat  = 8
        let padTop: CGFloat = 14
        let padBot: CGFloat = 22
        let originX  = size.width / 2
        let originY  = size.height - padBot
        let plotW    = size.width - padH * 2
        let plotH    = size.height - padTop - padBot

        func px(_ off: Double) -> CGFloat { originX + CGFloat(off / maxOff) * (plotW / 2) }
        func py(_ dn: Double) -> CGFloat  { originY - CGFloat(dn / maxDown) * plotH }

        // Background
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.08)))

        // Part F: distance arc grid
        let dnStep: Double = maxDown <= 100 ? 25 : (maxDown <= 200 ? 50 : 100)
        var arcD = dnStep
        while arcD <= totalYd * 1.05 {
            let arcSteps = 32
            var arcPath = Path(); var arcFirst = true
            for i in 0...arcSteps {
                let angle = Double(i) / Double(arcSteps) * .pi - .pi / 2
                let offYd = arcD * sin(angle)
                let dnYd  = arcD * cos(angle)
                guard dnYd >= 0 else { arcFirst = true; continue }
                let cx = px(offYd); let cy = py(dnYd)
                guard cx >= padH - 2 && cx <= size.width - padH + 2
                   && cy >= padTop - 2 && cy <= originY + 2 else { arcFirst = true; continue }
                if arcFirst { arcPath.move(to: CGPoint(x: cx, y: cy)); arcFirst = false }
                else { arcPath.addLine(to: CGPoint(x: cx, y: cy)) }
            }
            ctx.stroke(arcPath, with: .color(Color.white.opacity(0.10)),
                       style: StrokeStyle(lineWidth: 0.75, dash: [3, 5]))
            // Distance label at top of arc (off=0)
            ctx.draw(Text("\(Int(arcD))").font(.system(size: 7, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.32)),
                     at: CGPoint(x: originX + 4, y: py(arcD)), anchor: .leading)
            arcD += dnStep
        }

        // Part F: lateral gridlines + labels
        let latStep: Double = maxOff <= 25 ? 10 : (maxOff <= 50 ? 15 : 25)
        var latOff = latStep
        while latOff < maxOff {
            for sign: Double in [-1, 1] {
                let lx = px(sign * latOff)
                guard lx > padH && lx < size.width - padH else { continue }
                var vl = Path()
                vl.move(to: CGPoint(x: lx, y: padTop)); vl.addLine(to: CGPoint(x: lx, y: originY))
                ctx.stroke(vl, with: .color(Color.white.opacity(0.07)),
                           style: StrokeStyle(lineWidth: 0.75, dash: [3, 5]))
                let dir = sign < 0 ? "\(Int(latOff))L" : "\(Int(latOff))R"
                ctx.draw(Text(dir).font(.system(size: 6, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.30)),
                         at: CGPoint(x: lx, y: originY - 4), anchor: .bottom)
            }
            latOff += latStep
        }

        // Part F: target centerline (brighter)
        var cLine = Path()
        cLine.move(to: CGPoint(x: originX, y: originY))
        cLine.addLine(to: CGPoint(x: originX, y: padTop))
        ctx.stroke(cLine, with: .color(Color.white.opacity(0.22)),
                   style: StrokeStyle(lineWidth: 1.2, dash: [5, 7]))
        ctx.draw(Text("0").font(.system(size: 8, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.40)),
                 at: CGPoint(x: originX, y: padTop + 4), anchor: .top)

        // Origin dot
        ctx.fill(Path(ellipseIn: CGRect(x: originX-4, y: originY-4, width: 8, height: 8)),
                 with: .color(.white))

        // Monotonic path sampling: p = 0...1 (fraction of totalYd downrange)
        func pathPt(_ p: Double) -> CGPoint {
            CGPoint(x: px(offAt(p)), y: py(p * totalYd))
        }

        let carryFrac  = totalYd > 0 ? carryYd / totalYd : 1.0
        let currentP: Double = fp < 1.0 ? fp * carryFrac : carryFrac + rp * (1.0 - carryFrac)

        // Faint full-path guide
        let guideSteps = 30
        var guide = Path(); var guideFirst = true
        for i in 0...guideSteps {
            let pt = pathPt(Double(i) / Double(guideSteps))
            if guideFirst { guide.move(to: pt); guideFirst = false } else { guide.addLine(to: pt) }
        }
        ctx.stroke(guide, with: .color(Color.white.opacity(0.08)),
                   style: StrokeStyle(lineWidth: 1.5, dash: [3, 5]))

        // Airborne path (cyan) — progressive
        if currentP > 0.001 {
            let airEndP = min(currentP, carryFrac)
            let steps   = 40
            let maxStep = max(1, Int(Double(steps) * airEndP / max(carryFrac, 0.001)))
            var airPath = Path(); airPath.move(to: pathPt(0))
            for i in 1...maxStep {
                airPath.addLine(to: pathPt(Double(i) / Double(steps) * carryFrac))
            }
            ctx.stroke(airPath, with: .color(Self.airborneColor),
                       style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
        }

        // Rollout path (orange) — progressive
        if fp >= 1.0 && currentP > carryFrac + 0.001 {
            let rollFrac = (currentP - carryFrac) / max(1.0 - carryFrac, 0.001)
            let steps    = 20
            let maxStep  = max(1, Int(Double(steps) * rollFrac))
            var rollPath = Path(); rollPath.move(to: pathPt(carryFrac))
            for i in 1...maxStep {
                rollPath.addLine(to: pathPt(carryFrac + Double(i) / Double(steps) * (1.0 - carryFrac)))
            }
            ctx.stroke(rollPath, with: .color(Self.rolloutColor),
                       style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        }

        // Ball
        if currentP > 0.005 && currentP < 0.995 {
            drawGolfBall(ctx: ctx, center: pathPt(currentP),
                         radius: 7, phaseColor: fp < 1.0 ? Self.airborneColor : Self.rolloutColor)
        }

        // Carry dot
        if showCarry {
            let cp = pathPt(carryFrac)
            ctx.fill(Path(ellipseIn: CGRect(x: cp.x-4, y: cp.y-4, width: 8, height: 8)),
                     with: .color(Self.airborneColor))
        }

        // Total dot + drop line
        if showTotal {
            let tp = pathPt(1.0)
            ctx.fill(Path(ellipseIn: CGRect(x: tp.x-5, y: tp.y-5, width: 10, height: 10)),
                     with: .color(Self.totalColor))
            var drop = Path()
            drop.move(to: tp); drop.addLine(to: CGPoint(x: tp.x, y: originY))
            ctx.stroke(drop, with: .color(Color.white.opacity(0.15)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
        }

        // Scale indicator
        ctx.draw(Text(String(format: "±%.0f", maxOff))
                    .font(.system(size: 6, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.22)),
                 at: CGPoint(x: size.width - 3, y: padTop + 3), anchor: .topTrailing)
    }

    // MARK: - Formatters

    private func yds(_ v: Double?) -> String { v.map { String(format: "%.0f yd", $0) } ?? "--" }
    private func spd(_ v: Double?) -> String { v.map { String(format: "%.0f mph", $0) } ?? "--" }
    private func vlaDeg(_ v: Double?) -> String { v.map { String(format: "%.1f°", $0) } ?? "--" }
}
