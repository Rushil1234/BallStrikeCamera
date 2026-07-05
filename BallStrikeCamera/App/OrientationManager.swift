import UIKit

// MARK: - Orientation Manager

/// Singleton that controls the interface orientation lock for the whole app.
/// Game-mode screens call lockLandscape() on appear and lockPortrait() on disappear.
/// AppDelegate.application(_:supportedInterfaceOrientationsFor:) reads currentLock.
final class OrientationManager {

    static let shared = OrientationManager()
    private init() {}

    // MARK: - State

    /// Default: follow the device tilt (portrait + both landscapes). Camera
    /// capture screens temporarily lock landscape; everything else autorotates.
    private(set) var currentLock: UIInterfaceOrientationMask = .allButUpsideDown

    // MARK: - Public API

    func lockPortrait() {
        print("OrientationManager: locking portrait")
        currentLock = .portrait
        rotate(to: .portrait)
    }

    /// Locks landscape. Lefty golfers mount the phone upside-down relative to righty, so we lock
    /// the OPPOSITE landscape orientation (.landscapeLeft) — iOS then renders the whole UI rotated
    /// 180°, which reads upright once the phone is physically flipped. Hand is read from the
    /// persisted "tc_hitting_hand" preference so every caller stays in sync.
    func lockLandscape() {
        let lefty = UserDefaults.standard.string(forKey: "tc_hitting_hand") == "L"
        let orientation: UIInterfaceOrientation = lefty ? .landscapeLeft : .landscapeRight
        print("OrientationManager: locking landscape (\(lefty ? "lefty/landscapeLeft" : "righty/landscapeRight"))")
        currentLock = lefty ? .landscapeLeft : .landscapeRight
        rotate(to: orientation)
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
            let mask: UIInterfaceOrientationMask
            switch orientation {
            case .portrait, .portraitUpsideDown: mask = .portrait
            case .landscapeLeft:                 mask = .landscapeLeft
            default:                             mask = .landscapeRight
            }
            // Refresh the controller's supported orientations FIRST (it reads currentLock, already
            // updated above). setNeedsUpdate marks the VC dirty but the system re-queries it on the
            // NEXT runloop tick — so issue the geometry request async, otherwise it validates against
            // the stale (portrait) set and logs "None of the requested orientations are supported".
            let rootVC = scene.keyWindow?.rootViewController
            rootVC?.setNeedsUpdateOfSupportedInterfaceOrientations()
            DispatchQueue.main.async {
                rootVC?.setNeedsUpdateOfSupportedInterfaceOrientations()
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                    // Benign at cold start before the root VC adopts the mask; rotation still
                    // applies on the next layout pass.
                    #if DEBUG
                    print("OrientationManager: geometry update pending — \(error.localizedDescription)")
                    #endif
                }
            }
        } else {
            UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}
