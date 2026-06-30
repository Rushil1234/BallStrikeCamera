import SwiftUI
import ARKit

/// Pre-shot calibration screen: shows the live AR camera, reports the measured
/// tripod height, and hands a `CalibrationResult` back when confirmed. The caller
/// should then start the 240 fps capture session (ARKit + high-speed capture
/// can't run at once). See `AR_GROUND_CALIBRATION_PLAN.md`.
struct GroundCalibrationView: View {
    /// Called with the result on confirm, or nil if the user cancels.
    var onDone: (CalibrationResult?) -> Void

    @StateObject private var cal = GroundCalibration()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            ARCameraPreview(session: cal.session).ignoresSafeArea()

            // Top bar
            VStack {
                HStack {
                    Button("Cancel") { cal.stop(); onDone(nil); dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 18).padding(.top, 14)
                Spacer()
            }

            // Status + confirm
            VStack(spacing: 16) {
                Text(cal.statusText)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 24)

                Button {
                    cal.stop()
                    onDone(cal.result)
                    dismiss()
                } label: {
                    Text(cal.result != nil ? "Use this height" : "Finding the ground…")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(cal.result != nil ? Color.green : Color.white.opacity(0.18))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(cal.result == nil)
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 34)
        }
        .onAppear { cal.start() }
        .onDisappear { cal.stop() }
    }
}

/// Lightweight SwiftUI wrapper that renders an existing ARSession.
struct ARCameraPreview: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session = session
        view.automaticallyUpdatesLighting = true
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}
