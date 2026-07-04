import SwiftUI

struct ShotVisualizationPanel: View {
    @ObservedObject var camera: CameraController

    var body: some View {
        GeometryReader { geo in
            let crop = previewCrop(for: geo.size)
            ZStack {
                Color.black

                // Offset pans the guide-circle center to the container center.
                // scaleEffect then zooms from that center to fill the pane with the circle region.
                // The AVCaptureSession pipeline is untouched — recording stays full 1x.
                CameraPreview(session: camera.session)
                    .offset(x: crop.offsetX, y: crop.offsetY)
                    .scaleEffect(crop.zoom)

                // Static aim fan sits at the placement circle only before a ball is found; once
                // found, the fan emanates from the ball itself (in BallCircleOverlayView).
                if camera.currentBallRect == nil {
                    AimLineOverlayView()
                }

                BallCircleOverlayView(rect: camera.currentBallRect, crop: crop, phase: camera.phase)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .animation(.easeInOut(duration: 0.18), value: camera.phase)
            // .onAppear fires synchronously on first render — more reliable than .task alone.
            .onAppear {
                print("ShotVisualizationPanel appeared size: \(geo.size)")
                guard geo.size.width > 0, geo.size.height > 0 else { return }
                let roi = placementCircleROI(in: geo.size)
                print("Updating search ROI: \(roi)")
                camera.updateSearchROI(roi)
            }
            // .onChange catches rotation or any deferred first-layout where size was zero on appear.
            .onChange(of: geo.size) { newSize in
                print("ShotVisualizationPanel size changed: \(newSize)")
                guard newSize.width > 0, newSize.height > 0 else { return }
                let roi = placementCircleROI(in: newSize)
                print("Updating search ROI: \(roi)")
                camera.updateSearchROI(roi)
            }
            // .task kept as a third safety net (async, fires after appear).
            .task(id: geo.size) {
                guard geo.size.width > 0, geo.size.height > 0 else { return }
                camera.updateSearchROI(placementCircleROI(in: geo.size))
            }
        }
    }

    // Computes the pan + zoom that brings the guide-circle region to fill the container.
    private func previewCrop(for size: CGSize) -> PreviewCrop {
        guard size.width > 0, size.height > 0 else {
            return PreviewCrop(offsetX: 0, offsetY: 0, zoom: 1)
        }
        let cx   = size.width  * PreviewTargetLayout.centerXRatio
        let cy   = size.height * PreviewTargetLayout.centerYRatio
        let r    = min(size.width, size.height) * PreviewTargetLayout.radiusRatio
        let zoom = max(size.width, size.height) / (r * 2)
        return PreviewCrop(offsetX: size.width / 2 - cx,
                           offsetY: size.height / 2 - cy,
                           zoom: zoom)
    }

    // Maps the visual guide circle into 1x camera-normalized space for the detector.
    // The guide circle has radius `min(W,H)*radiusRatio` in the ZOOMED display, so its
    // footprint in the unzoomed camera feed is that radius divided by crop.zoom.
    private func placementCircleROI(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let cx   = size.width  * PreviewTargetLayout.centerXRatio
        let cy   = size.height * PreviewTargetLayout.centerYRatio
        let crop = previewCrop(for: size)
        // Divide by zoom: the visual circle is `radiusRatio` fraction of the screen,
        // but the camera was zoomed in by crop.zoom, so the actual 1x region is smaller.
        let r    = min(size.width, size.height) * PreviewTargetLayout.radiusRatio / crop.zoom

        let vf  = aspectFillVideoFrame(for: size)
        let nx  = (cx - vf.minX) / vf.width
        let ny  = (cy - vf.minY) / vf.height
        let nrX = r / vf.width
        let nrY = r / vf.height

        return CGRect(x: nx - nrX, y: ny - nrY, width: nrX * 2, height: nrY * 2)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}

// Shared by ShotVisualizationPanel and BallCircleOverlayView
private struct PreviewCrop {
    let offsetX: CGFloat
    let offsetY: CGFloat
    let zoom: CGFloat
}

private enum PreviewTargetLayout {
    static let centerXRatio: CGFloat = 0.28
    static let centerYRatio: CGFloat = 0.50
    static let radiusRatio: CGFloat  = 0.48
    static let sourceAspect: CGFloat = 16.0 / 9.0
}

// Returns the CGRect in which the 16:9 video renders inside `size` with aspect-fill gravity.
// The rect may extend outside `size` (overflow is clipped by the layer).
private func aspectFillVideoFrame(for size: CGSize) -> CGRect {
    let W = size.width, H = size.height, a = PreviewTargetLayout.sourceAspect
    let vW = W / H > a ? W : H * a
    let vH = W / H > a ? W / a : H
    return CGRect(x: (W - vW) / 2, y: (H - vH) / 2, width: vW, height: vH)
}

private struct AimLineOverlayView: View {
    private let fanAngles: [CGFloat] = [-20, -10, 0, 10, 20]
    @AppStorage("tc_hitting_hand") private var hand = "R"
    // Fan points along the ball's travel direction; lefty aims it the opposite way.
    private var dirSign: CGFloat { HitDirection.signCG * (hand == "L" ? -1 : 1) }
    // Lefty renders through a 180° orientation lock, which inverts the vertical axis. Flip the
    // sign so +° stays above the 0-line and −° below it from the user's view — same as righty.
    private var vSign: CGFloat { hand == "L" ? 1 : -1 }

    var body: some View {
        GeometryReader { geo in
            // The zoomed camera centers the ball placement target at the container center.
            let origin = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let length = max(geo.size.width, geo.size.height) * 1.45

            ZStack {
                ForEach(fanAngles, id: \.self) { angle in
                    aimLine(angle: angle, length: length, origin: origin, isMain: angle == 0)

                    Text(angle == 0 ? "0°" : (angle > 0 ? "+\(Int(angle))°" : "\(Int(angle))°"))
                        .font(.system(size: angle == 0 ? 10 : 9, weight: angle == 0 ? .bold : .semibold, design: .monospaced))
                        .foregroundColor(angle == 0 ? .white.opacity(0.68) : .white.opacity(0.38))
                        .padding(.horizontal, angle == 0 ? 6 : 4)
                        .padding(.vertical, angle == 0 ? 4 : 3)
                        .background(Color.black.opacity(angle == 0 ? 0.22 : 0.15))
                        .cornerRadius(5)
                        .position(labelPosition(for: angle, origin: origin, distance: angle == 0 ? 150 : 120))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func aimLine(angle: CGFloat, length: CGFloat, origin: CGPoint, isMain: Bool) -> some View {
        Path { path in
            path.move(to: origin)
            let radians = angle * .pi / 180
            // Fan extends in the ball's travel direction: right (original) or left (reversed mount).
            path.addLine(to: CGPoint(
                x: origin.x + dirSign * length * cos(radians),
                y: origin.y + vSign * length * sin(radians)   // vSign puts + above, − below (both hands)
            ))
        }
        .stroke(
            isMain ? Color.white.opacity(0.55) : Color.white.opacity(0.16),
            style: StrokeStyle(lineWidth: isMain ? 1.5 : 0.9, dash: isMain ? [] : [4, 5])
        )
    }

    private func labelPosition(for angle: CGFloat, origin: CGPoint, distance: CGFloat) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(
            x: origin.x + dirSign * distance * cos(radians),
            y: origin.y + vSign * distance * sin(radians)   // + above the 0° line, − below
        )
    }
}

private struct BallCircleOverlayView: View {
    let rect: CGRect?
    let crop: PreviewCrop
    let phase: CameraPhase

    private var isSearching: Bool { phase == .searching }
    private var ballFound: Bool { rect != nil && (phase == .tracking || phase == .ready) }

    var body: some View {
        GeometryReader { geo in
            // In the zoomed view the placement target is always at the container center.
            let placementCenter = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let placementRadius = min(geo.size.width, geo.size.height) * PreviewTargetLayout.radiusRatio
            let ballRect = rect.map { zoomedBallRect($0, in: geo.size) }

            // TimelineView drives the pulse + arrow continuously (reliable, no state churn).
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate

                ZStack {
                    // Item 5: once the ball is found, dim everything except a clear disc around it.
                    if ballFound, let ballRect {
                        Path { p in
                            p.addRect(CGRect(origin: .zero, size: geo.size))
                            p.addEllipse(in: ballRect.insetBy(dx: -ballRect.width * 0.35,
                                                              dy: -ballRect.height * 0.35))
                        }
                        .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
                        .allowsHitTesting(false)
                    }

                    // Item 1 + 5: placement circle + "Set into" — constantly radiates while
                    // searching, and disappears entirely once a ball is locked.
                    if !ballFound {
                        let pulse = isSearching ? (1 + 0.06 * CGFloat(sin(t * 3.2))) : 1.0
                        Circle()
                            .stroke(Color.white.opacity(0.72), lineWidth: 1.9)
                            .frame(width: placementRadius * 2 * pulse, height: placementRadius * 2 * pulse)
                            .position(placementCenter)
                        VStack(spacing: -6) {
                            Text("Set")
                                .font(.system(size: max(18, placementRadius * 0.55), weight: .heavy))
                                .foregroundColor(.white.opacity(0.88))
                            Text("into")
                                .font(.system(size: max(12, placementRadius * 0.25), weight: .semibold))
                                .foregroundColor(.white.opacity(0.82))
                        }
                        .position(placementCenter)
                    }

                    if let ballRect {
                        let ballCenter = CGPoint(x: ballRect.midX, y: ballRect.midY)

                        Circle()
                            .stroke(Color.green.opacity(0.82), lineWidth: 2.2)
                            .frame(width: ballRect.width, height: ballRect.height)
                            .position(ballCenter)
                            .shadow(color: Color.green.opacity(0.65), radius: 6)

                        // The whole 0°–±20° aim fan grows from the ball (white), fades, and repeats
                        // while armed — replacing the static center fan.
                        if phase == .ready {
                            let cycle = 1.3
                            let progress = CGFloat(t.truncatingRemainder(dividingBy: cycle) / cycle)
                            AnimatedAimFan(progress: progress,
                                           ballCenter: ballCenter,
                                           ballRadius: ballRect.width / 2,
                                           maxLen: max(geo.size.width, geo.size.height) * 0.9)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    // Map the 1x normalized ball rect into zoomed display coordinates.
    private func zoomedBallRect(_ rect: CGRect, in size: CGSize) -> CGRect {
        let vf = aspectFillVideoFrame(for: size)
        let mapped = CGRect(x: vf.minX + rect.minX * vf.width,
                            y: vf.minY + rect.minY * vf.height,
                            width: rect.width * vf.width,
                            height: rect.height * vf.height)
        let cx = size.width / 2, cy = size.height / 2, z = crop.zoom
        return CGRect(x: (mapped.minX + crop.offsetX - cx) * z + cx,
                      y: (mapped.minY + crop.offsetY - cy) * z + cy,
                      width: mapped.width * z, height: mapped.height * z)
    }
}

/// The full 0°–±20° aim fan emanating from the ball. Each line grows outward, fades as it
/// lengthens, then restarts — a live "armed, ready to hit" cue. Replaces the single arrow.
private struct AnimatedAimFan: View {
    let progress: CGFloat
    let ballCenter: CGPoint
    let ballRadius: CGFloat
    let maxLen: CGFloat

    private let angles: [CGFloat] = [-20, -10, 0, 10, 20]
    @AppStorage("tc_hitting_hand") private var hand = "R"

    var body: some View {
        let dir = HitDirection.signCG * (hand == "L" ? -1 : 1)   // lefty aims the fan the other way
        let vSign: CGFloat = hand == "L" ? 1 : -1                 // lefty's 180° lock inverts vertical
        let opacity = progress < 0.6 ? 1.0 : Double(max(0, 1 - (progress - 0.6) / 0.4))

        return ZStack {
            ForEach(angles, id: \.self) { angle in
                let isMain = angle == 0
                let rad = angle * .pi / 180
                // Base travel direction (±x) fanned by `angle`.
                let ux = dir * cos(rad)
                let uy = vSign * sin(rad)   // + above the 0° line, − below (both hands)
                let start = CGPoint(x: ballCenter.x + ux * (ballRadius + 6),
                                    y: ballCenter.y + uy * (ballRadius + 6))
                let len = max(0, progress) * maxLen * (isMain ? 1.0 : 0.9)
                let tip = CGPoint(x: start.x + ux * len, y: start.y + uy * len)

                Path { p in p.move(to: start); p.addLine(to: tip) }
                    .stroke(Color.white.opacity(isMain ? 0.95 : 0.5),
                            style: StrokeStyle(lineWidth: isMain ? 2.6 : 1.4,
                                               lineCap: .round,
                                               dash: isMain ? [] : [5, 5]))
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
    }
}
