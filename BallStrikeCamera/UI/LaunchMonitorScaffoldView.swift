import SwiftUI

struct LaunchMonitorScaffoldView: View {
    @ObservedObject var camera: CameraController
    let modeTitle: String
    @Binding var selectedClub: String
    let selectedClubId: UUID?
    let shotCount: Int
    var context: ShotContext? = nil
    var onChooseClub: (() -> Void)? = nil
    var onDismiss: () -> Void = {}
    var onSaveSession: (() -> Void)? = nil
    var canSaveSession: Bool = false
    var onShotSaved: ((SavedShot) -> Void)? = nil
    var onShotComplete: (() -> Void)? = nil
    @State private var exportedURL: URL?
    @State private var showShareSheet = false
    @State private var exportError: String?
    @State private var lastComposite: PlatformImage?   // last shot's composite for the side panel
    @State private var showHandPicker = false

    // Player's hitting hand (persisted default). Lefty = the whole hitting view is mirrored
    // vertically so a golfer set up the opposite way sees everything oriented for them — a pure
    // view flip that never touches the tracking algo.
    @AppStorage("tc_hitting_hand") private var hitHandRaw = "R"
    private var isLefty: Bool { hitHandRaw == "L" }

    var body: some View {
        GeometryReader { geo in
            let summaryWidth = min(330, geo.size.width * 0.24)
            let bottomHeight = geo.size.height * 0.21
            let mainHeight = geo.size.height - bottomHeight

            ZStack {
                Color(white: 0.05)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ZStack(alignment: .top) {
                            ShotVisualizationPanel(camera: camera)

                            HStack(alignment: .top) {
                                TopOverlayBarView(
                                    title: modeTitle,
                                    subtitle: "\(camera.phase.rawValue.uppercased()) · 240 FPS",
                                    onBack: onDismiss
                                )

                                Spacer(minLength: 8)

                                ExposureModePickerView(
                                    selectedShutter: camera.selectedShutter,
                                    onShutterSelected: camera.applyShutter
                                )
                                .padding(.trailing, 12)
                            }
                            .padding(.top, 8)

                            // Course context HUD — only while playing a round.
                            if context?.sourceMode == .course {
                                courseContextHUD
                                    .padding(.top, 10)
                            }

                            VStack {
                                Spacer()

                                HStack {
                                    if let onChooseClub {
                                        Button(action: onChooseClub) {
                                            clubPill
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        clubPill
                                    }


                                    RangeOverlayPill {
                                        HStack(spacing: 4) {
                                            Text("Count")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(.white.opacity(0.88))

                                            Text("\(shotCount)")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }

                                    Spacer()

                                    Button(action: { camera.simulateShot() }) {
                                        RangeOverlayPill {
                                            HStack(spacing: 5) {
                                                Image(systemName: "play.circle")
                                                    .font(.system(size: 11, weight: .bold))
                                                Text(camera.isAnalyzingShot ? "Simulating…" : "Simulate Shot")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .lineLimit(1)
                                            }
                                            .foregroundColor(.white.opacity(
                                                (camera.isAnalyzingShot || camera.showShotResult) ? 0.42 : 0.94
                                            ))
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(camera.isAnalyzingShot || camera.showShotResult)

                                    Button { showHandPicker = true } label: {
                                        RangeOverlayPill {
                                            HStack(spacing: 5) {
                                                Image(systemName: "figure.golf")
                                                    .font(.system(size: 11, weight: .bold))
                                                Text(isLefty ? "Lefty" : "Righty")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .lineLimit(1)
                                            }
                                            .foregroundColor(.white.opacity(0.94))
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    Button(action: exportFrames) {
                                        RangeOverlayPill {
                                            HStack(spacing: 6) {
                                                Image(systemName: "square.and.arrow.up")
                                                    .font(.system(size: 11, weight: .bold))

                                                Text("Share Frames")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .lineLimit(1)
                                            }
                                            .foregroundColor(.white.opacity(camera.capturedFrames.isEmpty ? 0.42 : 0.94))
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(camera.latestShotAnalysis == nil)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .environment(\.layoutDirection, .leftToRight)   // keep column internals LTR

                        ShotSummaryPanelView(metrics: camera.latestShotAnalysis?.metrics,
                                             composite: lastComposite)
                            .frame(width: summaryWidth)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    // Lefty swaps the two columns (summary → left, camera → right). RTL only
                    // reorders these two children; each keeps its own LTR internals above.
                    .environment(\.layoutDirection, isLefty ? .rightToLeft : .leftToRight)
                    .frame(width: geo.size.width, height: mainHeight, alignment: .leading)

                    CompactMetricsBarView(metrics: camera.latestShotAnalysis?.metrics)
                        .frame(width: geo.size.width, height: bottomHeight)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .padding(0)
                .ignoresSafeArea()
                // Lefty orientation is handled by the device orientation lock (.landscapeLeft), not a
                // view transform — see OrientationManager. Re-lock when the hand toggles.
                .onChange(of: hitHandRaw) { _ in
                    OrientationManager.shared.lockLandscape()
                    // The detection buffer must rotate with the UI lock, or the search ROI
                    // maps to the wrong region of the frame (lefty could never see the ball).
                    camera.applyHandOrientation()
                }
            }
        }
        .ignoresSafeArea()
        .navigationBarHidden(true)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        // Cache the last shot's composite for the side panel when a shot completes.
        // Keyed on the analysis timestamp (not showShotResult): the cover now presents BEFORE
        // analysis finishes, so this must fire when the result actually lands. The render runs
        // off-main — doing it on the main thread here was freezing the cover's presentation.
        .onChange(of: camera.latestShotAnalysis?.createdAt) { _ in
            guard camera.showShotResult, let analysis = camera.latestShotAnalysis else { return }
            Task.detached(priority: .utility) {
                if let image = ShotCompositeRenderer().render(analysis: analysis) {
                    await MainActor.run { lastComposite = image }
                }
            }
        }
        .fullScreenCover(isPresented: $camera.showShotResult) {
            if let analysis = camera.latestShotAnalysis {
                ShotResultView(
                    analysis: analysis,
                    context: context,
                    selectedClubId: selectedClubId,
                    selectedClubName: selectedClub,
                    isPutterShot: camera.isPutterMode,
                    onShotSaved: onShotSaved
                ) {
                    camera.dismissShotPresentation()
                    onShotComplete?()
                }
            } else {
                // Analysis still running — the cover appears the instant the swing is captured.
                ZStack {
                    Color(white: 0.06).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView().tint(.white).scaleEffect(1.4)
                        Text("Analyzing shot…")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.92))
                    }
                }
                .tcAppearance()
                .statusBarHidden(true)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let exportedURL {
                ActivityViewController(activityItems: [exportedURL])
            }
        }
        .alert("Export failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        // Lightweight SwiftUI picker instead of .confirmationDialog: the UIKit action sheet throws
        // an _UIAlertControllerPhoneTVMacView height-constraint conflict and presents slowly in
        // landscape. This overlay is instant and warning-free.
        .overlay {
            if showHandPicker {
                HandPickerOverlay(
                    current: hitHandRaw,
                    onSelect: { hand in hitHandRaw = hand; showHandPicker = false },
                    onCancel: { showHandPicker = false }
                )
            }
        }
    }

    private var clubPill: some View {
        RangeOverlayPill {
            HStack(spacing: 4) {
                Text("Club")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))

                Text(selectedClub)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }

    /// Compact hole context shown while hitting from the course, so the golfer sees the
    /// hole, par, and distance to the pin without leaving the HUD.
    private var courseContextHUD: some View {
        HStack(spacing: 10) {
            if let hole = context?.holeNumber {
                Label("Hole \(hole)", systemImage: "flag.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
            if let par = context?.holePar {
                Text("Par \(par)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
            }
            if let yd = context?.holeYardage {
                Divider().frame(height: 12).overlay(Color.white.opacity(0.25))
                HStack(spacing: 4) {
                    Text("\(yd)")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(Color(red: 0.55, green: 0.73, blue: 0.37))
                    Text("yd to pin")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.8))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.26), lineWidth: 1))
    }

    private func exportFrames() {
        guard let analysis = camera.latestShotAnalysis else { return }
        do {
            exportedURL = try ShotExportService().export(from: analysis).zipURL
            showShareSheet = true
        } catch {
            exportError = error.localizedDescription
        }
    }
}

struct RangeOverlayPill<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Pure-SwiftUI hitting-hand chooser. Replaces `.confirmationDialog` (UIKit action sheet) which
/// misbehaves in the app's locked landscape orientation. Renders inside the orientation-locked
/// hierarchy, so it stays upright for both hands.
private struct HandPickerOverlay: View {
    let current: String
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.76)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 14) {
                Text("Hitting Hand")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white.opacity(0.94))

                HStack(spacing: 12) {
                    handButton("Righty", value: "R")
                    handButton("Lefty",  value: "L")
                }

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(white: 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
        }
        .transition(.opacity)
    }

    private func handButton(_ title: String, value: String) -> some View {
        let selected = current == value
        return Button { onSelect(value) } label: {
            HStack(spacing: 6) {
                Image(systemName: "figure.golf")
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(selected ? .black : .white.opacity(0.92))
            .frame(width: 108, height: 42)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.white : Color.white.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }
}
