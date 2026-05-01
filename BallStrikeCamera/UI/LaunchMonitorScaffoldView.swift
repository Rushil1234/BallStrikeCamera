import SwiftUI

struct LaunchMonitorScaffoldView: View {
    @ObservedObject var camera: CameraController
    let modeTitle: String
    @Binding var selectedClub: String
    let shotCount: Int

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
                                    onBack: {}
                                )

                                Spacer(minLength: 8)

                                ExposureModePickerView(
                                    selectedShutter: camera.selectedShutter,
                                    onShutterSelected: camera.applyShutter
                                )
                                .padding(.trailing, 12)
                            }
                            .padding(.top, 8)

                            VStack {
                                Spacer()

                                HStack {
                                    Button(action: {}) {
                                        RangeOverlayPill {
                                            HStack(spacing: 4) {
                                                Text("Club")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundColor(.white.opacity(0.6))

                                                Text(selectedClub)
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    RangeOverlayPill {
                                        HStack(spacing: 4) {
                                            Text("Count")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(.white.opacity(0.6))

                                            Text("\(shotCount)")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }

                                    Spacer()

                                    Button(action: {}) {
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
                                    .disabled(camera.capturedFrames.isEmpty)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                        ShotSummaryPanelView()
                            .frame(width: summaryWidth)
                    }
                    .frame(width: geo.size.width, height: mainHeight, alignment: .leading)

                    CompactMetricsBarView()
                        .frame(width: geo.size.width, height: bottomHeight)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .padding(0)
                .ignoresSafeArea()
            }
        }
        .ignoresSafeArea()
        .navigationBarHidden(true)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .fullScreenCover(isPresented: $camera.showReview) {
            if let analysis = camera.latestShotAnalysis {
                ShotTrackingReviewView(analysis: analysis) {
                    camera.showReview = false
                    print("ShotTrackingReviewView dismissed")
                }
            }
        }
    }
}

struct RangeOverlayPill<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.6))
            .clipShape(Capsule())
    }
}
