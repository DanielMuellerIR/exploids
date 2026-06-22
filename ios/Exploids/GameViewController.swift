import UIKit
import SpriteKit
import GameCore

/// Haupt-ViewController der iOS-App.
/// Er erzeugt den SpriteKit-View, hostet die GameScene und legt ein Touch-Overlay darüber.
/// Entspricht der Rolle von GameWindow auf macOS (Sources/ExploidsMac/GameWindow.swift).
final class GameViewController: UIViewController {

    // MARK: - Eigenschaften

    /// SpriteKit-Renderansicht – füllt den gesamten Screen.
    private let skView = SKView()

    /// Die laufende Spiel-Scene. Starke Referenz notwendig, damit sie nicht freigegeben wird.
    private var scene: GameScene!

    /// Das transparente Touch-Overlay über dem SpriteKit-View.
    /// Empfängt alle Touches und leitet sie als Tastencodes an die GameScene weiter.
    private var overlay: TouchControlsView!

    /// CADisplayLink verbindet sich mit dem Bildschirm-Refresh-Takt (~60/120 Hz).
    /// Pro Frame liest er gameState und benachrichtigt das Overlay bei Zustandswechseln.
    private var displayLink: CADisplayLink?

    /// Zuletzt gesehener GameState – zum Erkennen von Zustandswechseln ohne ständiges Neuzeichnen.
    private var lastKnownState: GameState?

    // MARK: - Lifecycle

    override func loadView() {
        // SKView direkt als Root-View setzen (kein UIView-Wrapper nötig)
        skView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view = skView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupScene()
        setupOverlay()
        setupDisplayLink()
    }

    // MARK: - Setup

    /// Erzeugt und präsentiert die GameScene in der SKView.
    /// Entspricht dem Init-Code in GameWindow.swift (macOS).
    private func setupScene() {
        // Szenen-Größe: 1024×768 – identisch mit der macOS-Variante.
        // scaleMode .resizeFill passt die Szene an den tatsächlichen View-Frame an.
        let s = GameScene(size: CGSize(width: 1024, height: 768))
        s.scaleMode = .resizeFill
        s.backgroundColor = .black

        // onQuit absichtlich NICHT setzen: iOS-Apps dürfen sich nicht selbst beenden (Apple HIG).

        skView.presentScene(s)
        self.scene = s
    }

    /// Legt das Touch-Overlay als transparente Subview über den SKView.
    private func setupOverlay() {
        // Gleiche Bounds wie skView; autoresizing hält das auch nach Rotation korrekt.
        overlay = TouchControlsView(frame: skView.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.isMultipleTouchEnabled = true
        overlay.backgroundColor = .clear

        // Schwache Referenz auf die Scene: das Overlay kennt nur die öffentliche API.
        overlay.scene = scene

        skView.addSubview(overlay)
    }

    /// Startet den CADisplayLink, der pro Frame den GameState prüft und bei Wechsel
    /// das Overlay benachrichtigt, damit es seine Button-Anordnung anpasst.
    private func setupDisplayLink() {
        let link = CADisplayLink(target: self, selector: #selector(onDisplayLink))
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }

    /// Wird jeden Frame auf dem Main-Thread aufgerufen (CADisplayLink-Callback).
    @objc private func onDisplayLink() {
        let current = scene.gameState
        // Overlay nur aktualisieren, wenn sich der State tatsächlich geändert hat.
        if case .some(let last) = lastKnownState, statesEqual(last, current) { return }
        lastKnownState = current
        overlay.update(for: current)
    }

    // MARK: - Interface-Konfiguration

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .landscape
    }

    override var prefersStatusBarHidden: Bool {
        true
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        true
    }

    // MARK: - Hilfsfunktion

    // In Swift 6 ist deinit nonisolated; CADisplayLink ist nicht Sendable.
    // Daher stoppen wir den Link bereits in viewDidDisappear (Main-Thread),
    // sodass deinit nichts mehr anfassen muss.
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        displayLink?.invalidate()
        displayLink = nil
    }
}

/// Hilfsfunktion: vergleicht zwei GameState-Werte auf Gleichheit.
/// GameState hat keinen synthetisierten Equatable-Konformismus – einfacher manueller Vergleich.
private func statesEqual(_ a: GameState, _ b: GameState) -> Bool {
    switch (a, b) {
    case (.startScreen,      .startScreen):      return true
    case (.playing,          .playing):          return true
    case (.nameEntry,        .nameEntry):         return true
    case (.gameOver,         .gameOver):          return true
    case (.quitConfirmation, .quitConfirmation): return true
    case (.glossary,         .glossary):         return true
    default:                                     return false
    }
}
