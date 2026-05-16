import UIKit

// MARK: - Orientation Manager

/// Singleton that controls the interface orientation lock for the whole app.
/// Game-mode screens call lockLandscape() on appear and lockPortrait() on disappear.
/// AppDelegate.application(_:supportedInterfaceOrientationsFor:) reads currentLock.
final class OrientationManager {

    static let shared = OrientationManager()
    private init() {}

    // MARK: - State

    private(set) var currentLock: UIInterfaceOrientationMask = .portrait

    // MARK: - Public API

    func lockPortrait() {
        print("OrientationManager: locking portrait")
        currentLock = .portrait
        rotate(to: .portrait)
    }

    func lockLandscape() {
        print("OrientationManager: locking landscape")
        currentLock = .landscapeRight
        rotate(to: .landscapeRight)
    }

    func unlockAllButUpsideDown() {
        print("OrientationManager: unlocking all but upside-down")
        currentLock = .allButUpsideDown
        // No forced rotation — let the device orientation decide.
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        if #available(iOS 16.0, *) {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    // MARK: - Private

    private func rotate(to orientation: UIInterfaceOrientation) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        if #available(iOS 16.0, *) {
            let mask: UIInterfaceOrientationMask = (orientation == .portrait || orientation == .portraitUpsideDown)
                ? .portrait
                : .landscapeRight
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                print("OrientationManager geometry update error: \(error.localizedDescription)")
            }
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        } else {
            UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}
