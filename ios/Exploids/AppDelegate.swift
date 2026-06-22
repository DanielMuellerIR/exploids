import UIKit

/// Einstiegspunkt der iOS-App (klassischer AppDelegate-Pfad, ohne SceneDelegate/Storyboard).
/// @main markiert diese Klasse als Startpunkt; UIKit ruft application(_:didFinishLaunchingWithOptions:) auf.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    /// Das einzige UIWindow der App. Muss als Property gehalten werden, sonst wird es sofort freigegeben.
    var window: UIWindow?

    /// Wird aufgerufen, sobald die App gestartet und die UI bereit ist.
    /// Hier erzeugen wir manuell ein Fenster und setzen den GameViewController als Root.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // UIWindow auf den gesamten Bildschirm spannen
        let win = UIWindow(frame: UIScreen.main.bounds)

        // GameViewController hostet SpriteKit-Scene + Touch-Overlay
        win.rootViewController = GameViewController()

        // Fenster sichtbar machen und zum Key-Window erklären
        win.makeKeyAndVisible()

        self.window = win
        return true
    }
}
