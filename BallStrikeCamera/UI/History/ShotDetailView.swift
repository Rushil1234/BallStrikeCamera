import SwiftUI

struct ShotDetailView: View {
    let shot: SavedShot
    @EnvironmentObject private var session: AuthSessionStore

    @State private var resolvedFramesDir: String?   // local dir after ensuring frames (cloud → disk)
    @State private var framesResolved = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ZStack {
            TrueCarryBackground().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: TCTheme.sectionGap) {
                    replaySection
                    metricsSection
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 12)
            }
        }
        .navigationTitle(shot.clubName ?? "Shot")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.clear, for: .navigationBar)
        .task { await resolveFrames() }
    }

    /// Ensures the replay frames exist on disk (downloading from cloud if this
    /// device doesn't have them), then points the player at the local folder.
    private func resolveFrames() async {
        guard !framesResolved, shot.media.frameCount > 0,
              let uid = session.currentUser?.id else { framesResolved = true; return }
        let svc = ShotPersistenceService(userId: uid, backend: session.backend)
        resolvedFramesDir = (await svc.ensureFramesAvailable(for: shot))?.path
        framesResolved = true
    }

    // MARK: - Replay

    @ViewBuilder
    private var replaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TCSectionHeader(title: "Replay")
            Group {
                if let framesDir = resolvedFramesDir, shot.media.frameCount > 0 {
                    AnimatedFramesView(framesDir: framesDir, frameCount: shot.media.frameCount)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else if !framesResolved, shot.media.frameCount > 0 {
                    // Fetching frames from cloud for this device.
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if let composite = shot.media.compositePath {
                    AsyncImage(url: URL(fileURLWithPath: composite)) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFit()
                        default:
                            replayPlaceholder
                        }
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    replayPlaceholder
                }
            }
            HStack(spacing: 8) {
                TCPill(text: shot.source == .simulated ? "Simulated" : "Live Shot", color: TCTheme.sage)
                if let name = shot.clubName {
                    TCPill(text: name, color: TCTheme.gold)
                }
                Spacer()
                Text(Self.dateFormatter.string(from: shot.timestamp))
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.textMuted)
            }
        }
        .tcCard()
    }

    private var replayPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(TCTheme.panelRaised)
                .frame(height: 220)
            VStack(spacing: 8) {
                Image(systemName: "film.stack")
                    .font(.system(size: 32))
                    .foregroundColor(TCTheme.textUltraMuted)
                Text("No replay available")
                    .font(.system(size: 13))
                    .foregroundColor(TCTheme.textMuted)
            }
        }
    }

    // MARK: - Metrics

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TCSectionHeader(title: "Launch Metrics")
            VStack(spacing: 1) {
                metricGroup("Distance", [
                    ("Carry",   carry,  "yds"),
                    ("Total",   total,  "yds"),
                    ("Rollout", rollout, "yds"),
                ])
                TCDivider().padding(.vertical, 6)
                metricGroup("Ball Launch", [
                    ("Ball Speed", ballSpeed,   "mph"),
                    ("VLA",        vla,         "°"),
                    ("HLA",        hla,         ""),
                ])
                TCDivider().padding(.vertical, 6)
                metricGroup("Club", [
                    ("Club Speed",   clubSpeed,   "mph"),
                    ("Smash Factor", smash,       ""),
                    ("Club Path",    clubPath,    "°"),
                ])
                TCDivider().padding(.vertical, 6)
                metricGroup("Spin", [
                    ("Backspin",   backspin,   "rpm"),
                    ("Sidespin",   sidespin,   "rpm"),
                    ("Spin Axis",  spinAxis,   "°"),
                ])
                TCDivider().padding(.vertical, 6)
                metricGroup("Face", [
                    ("Face Angle",  faceAngle,   "°"),
                    ("Face-to-Path", facePath,   "°"),
                ])
            }
        }
        .tcCard()
    }

    private func metricGroup(_ title: String, _ items: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(TCTheme.textMuted)
                .tracking(0.8)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                spacing: 10
            ) {
                ForEach(items, id: \.0) { label, value, unit in
                    metricCell(label, value, unit)
                }
            }
        }
    }

    private func metricCell(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundColor(value == "—" ? TCTheme.textUltraMuted : TCTheme.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundColor(TCTheme.textMuted)
                }
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(TCTheme.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(TCTheme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Formatted values

    private var m: SavedShotMetrics { shot.metrics }

    private func fmt(_ v: Double, decimals: Int = 0) -> String {
        v == 0 ? "—" : String(format: "%.\(decimals)f", v)
    }

    private var carry:     String { fmt(m.carryYards) }
    private var total:     String { fmt(m.totalYards) }
    private var rollout:   String { fmt(m.rolloutYards) }
    private var ballSpeed: String { fmt(m.ballSpeedMph, decimals: 1) }
    private var vla:       String { fmt(m.vlaDegrees, decimals: 1) }
    private var hla: String {
        guard m.hlaDegrees != 0 else { return "—" }
        let dir = m.hlaDirection.isEmpty ? "" : " \(m.hlaDirection)"
        return String(format: "%.1f°%@", m.hlaDegrees, dir)
    }
    private var clubSpeed:  String { fmt(m.clubSpeedMph, decimals: 1) }
    private var smash:      String { m.smashFactor == 0 ? "—" : String(format: "%.2f", m.smashFactor) }
    private var clubPath:   String {
        guard m.clubPathDegrees != 0 else { return "—" }
        return String(format: "%.1f°", m.clubPathDegrees)
    }
    private var backspin:  String { fmt(m.backspinRpm) }
    private var sidespin:  String {
        guard m.sidespinRpm != 0 else { return "—" }
        return String(format: "%.0f", m.sidespinRpm)
    }
    private var spinAxis:  String {
        guard m.spinAxisDegrees != 0 else { return "—" }
        return String(format: "%.1f°", m.spinAxisDegrees)
    }
    private var faceAngle: String {
        guard m.faceAngleDegrees != 0 else { return "—" }
        return String(format: "%.1f°", m.faceAngleDegrees)
    }
    private var facePath:  String {
        guard m.faceToPathDegrees != 0 else { return "—" }
        return String(format: "%.1f°", m.faceToPathDegrees)
    }
}
