import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
        uiView.videoPreviewLayer.videoGravity = .resizeAspectFill
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer.frame = bounds
        if let connection = videoPreviewLayer.connection, connection.isVideoOrientationSupported {
            // Match the locked interface orientation so the preview reads naturally (motion in the
            // correct directions). Lefty locks .landscapeLeft, which is 180° from righty.
            let lefty = UserDefaults.standard.string(forKey: "tc_hitting_hand") == "L"
            connection.videoOrientation = lefty ? .landscapeLeft : .landscapeRight
        }
    }
}
