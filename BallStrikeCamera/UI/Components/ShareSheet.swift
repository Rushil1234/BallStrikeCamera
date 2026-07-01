import SwiftUI
import UIKit

/// Thin SwiftUI wrapper over UIActivityViewController for sharing a shot card
/// (composite image + caption) to Messages, Instagram, Mail, etc.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
