import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {

    // Set this from game-mode views before presenting, reset on dismiss.
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }
}
