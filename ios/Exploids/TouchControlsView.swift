import UIKit
import GameCore

// MARK: - Modell-Typen

/// Beschreibt, wie ein Touch-Button die GameScene-API aufruft.
enum ButtonKind {
    /// Taste bleibt gedrückt solange der Finger liegt (z.B. Schub, Drehen, Feuer).
    case hold(keyCode: UInt16)
    /// Einmaliger Tap: keyDown sofort gefolgt von keyUp (z.B. Start, Replay).
    case tap(keyCode: UInt16)
    /// Zeichen-Eingabe: simulateTypeCharacter(_:) — für Initialen und Glossar-Taste.
    case typeChar(String)
}

/// Ein einzelner virtueller Button im Touch-Overlay.
struct TouchButton {
    /// Eindeutige ID – wird als Wörterbuch-Schlüssel für aktive Touches verwendet.
    let id: Int
    /// Position und Größe relativ zu den Bounds der TouchControlsView (0…1 Koordinaten).
    /// In layoutSubviews/draw(_:) werden daraus absolute CGRects berechnet.
    let relativeRect: CGRect
    /// Angezeigtes Kürzel auf dem Button.
    let label: String
    /// Verhalten beim Berühren.
    let kind: ButtonKind
}

// MARK: - TouchControlsView

/// Transparente UIView-Subklasse, die zustandsabhängige virtuelle Buttons rendert
/// und Multitouch auf die öffentliche GameScene-Eingabe-API mappt.
///
/// Das Overlay sitzt direkt über dem SKView. Es empfängt alle Touches; der SKView
/// darunter bekommt keine Touches (passthrough findet nicht statt – GameScene wird
/// ausschließlich über die simulateKey*-Methoden gesteuert).
final class TouchControlsView: UIView {

    // MARK: - Öffentliche Eigenschaften

    /// Schwache Referenz auf die GameScene – das Overlay kennt nur die öffentliche Bridge-API.
    weak var scene: GameScene?

    // MARK: - Private Eigenschaften

    /// Aktuell angezeigte Button-Definitionen (abhängig vom GameState).
    private var buttons: [TouchButton] = []

    /// Berechnete absolute Rects für jeden Button (aktualisiert in layoutSubviews).
    private var buttonFrames: [Int: CGRect] = [:]

    /// Welcher Button ist gerade von welchem Touch berührt?
    /// Key: UITouch (Objekt-Identität), Value: Button-ID.
    private var activeHoldTouches: [UITouch: Int] = [:]

    /// Neon-Cyan-Farbe für alle Button-Outlines und Beschriftungen.
    private let neonColor = UIColor(red: 0.0, green: 1.0, blue: 0.9, alpha: 0.75)

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("Nur programmatisch initialisieren")
    }

    // MARK: - Zustand wechseln

    /// Wird vom GameViewController bei jedem GameState-Wechsel aufgerufen.
    /// Baut das Button-Set für den neuen Zustand auf und löst Neuzeichnen aus.
    func update(for state: GameState) {
        // Alle aktiven Hold-Touches sauber beenden, bevor wir die Buttons austauschen.
        releaseAllHoldTouches()

        buttons = makeButtons(for: state)
        buttonFrames = [:]      // werden in layoutSubviews neu berechnet
        setNeedsLayout()
        setNeedsDisplay()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Sicherer Bereich (Notch, Home-Indikator) berücksichtigen.
        let safe = bounds.inset(by: safeAreaInsets)
        // Absolute Frames aus relativen Rects berechnen.
        buttonFrames = [:]
        for btn in buttons {
            let r = btn.relativeRect
            buttonFrames[btn.id] = CGRect(
                x: safe.minX + r.minX * safe.width,
                y: safe.minY + r.minY * safe.height,
                width: r.width  * safe.width,
                height: r.height * safe.height
            )
        }
    }

    // MARK: - Rendering

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        // Hintergrund: vollständig transparent (SKView scheint durch)
        ctx.clear(rect)

        for btn in buttons {
            guard let frame = buttonFrames[btn.id] else { continue }
            drawButton(ctx: ctx, frame: frame, label: btn.label)
        }
    }

    /// Zeichnet einen einzelnen Button mit Neon-Outline und zentriertem Text.
    private func drawButton(ctx: CGContext, frame: CGRect, label: String) {
        let inset = frame.insetBy(dx: 3, dy: 3)

        // Halbtransparenter Füllhintergrund
        ctx.setFillColor(UIColor(red: 0, green: 0.9, blue: 0.85, alpha: 0.08).cgColor)
        ctx.fillEllipse(in: inset)

        // Neon-Outline
        ctx.setStrokeColor(neonColor.cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: inset)

        // Beschriftung zentriert
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: min(frame.height * 0.28, 14), weight: .medium),
            .foregroundColor: neonColor
        ]
        let str = label as NSString
        let textSize = str.size(withAttributes: attrs)
        let textRect = CGRect(
            x: frame.midX - textSize.width / 2,
            y: frame.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        str.draw(in: textRect, withAttributes: attrs)
    }

    // MARK: - Touch-Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let pt = touch.location(in: self)
            guard let btn = hitButton(at: pt) else { continue }

            switch btn.kind {
            case .hold(let kc):
                // Taste als gedrückt markieren und merken, welcher Touch sie hält.
                scene?.simulateKeyDown(keyCode: kc)
                activeHoldTouches[touch] = btn.id

            case .tap(let kc):
                // Einmaliger Tap: sofort drücken und loslassen.
                scene?.simulateKeyDown(keyCode: kc)
                scene?.simulateKeyUp(keyCode: kc)

            case .typeChar(let ch):
                // Zeichen an die Initialen-/Glossar-Eingabe übergeben.
                scene?.simulateTypeCharacter(ch)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Wenn ein Finger von einem Hold-Button auf einen anderen gleitet:
        // alten keyUp auslösen, neuen keyDown starten – verhindert hängende Tasten.
        for touch in touches {
            let pt = touch.location(in: self)
            let newBtn = hitButton(at: pt)

            if let oldId = activeHoldTouches[touch] {
                let oldBtn = buttons.first(where: { $0.id == oldId })
                let oldKey: UInt16?
                if case .hold(let kc) = oldBtn?.kind { oldKey = kc } else { oldKey = nil }

                if let newBtn, case .hold(let newKc) = newBtn.kind, newBtn.id != oldId {
                    // Finger gleitet auf neuen Hold-Button
                    if let ok = oldKey { scene?.simulateKeyUp(keyCode: ok) }
                    scene?.simulateKeyDown(keyCode: newKc)
                    activeHoldTouches[touch] = newBtn.id
                } else if newBtn == nil {
                    // Finger hat den Button verlassen, ohne einen neuen zu betreten
                    if let ok = oldKey { scene?.simulateKeyUp(keyCode: ok) }
                    activeHoldTouches.removeValue(forKey: touch)
                }
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseTouches(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseTouches(touches)
    }

    // MARK: - Hilfsfunktionen

    /// Lässt für eine Menge beendeter Touches alle Hold-Tasten los.
    private func releaseTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            guard let id = activeHoldTouches.removeValue(forKey: touch) else { continue }
            guard let btn = buttons.first(where: { $0.id == id }) else { continue }
            if case .hold(let kc) = btn.kind {
                scene?.simulateKeyUp(keyCode: kc)
            }
        }
    }

    /// Lässt alle aktuell gedrückten Hold-Tasten los (beim Zustandswechsel).
    private func releaseAllHoldTouches() {
        for (_, id) in activeHoldTouches {
            guard let btn = buttons.first(where: { $0.id == id }) else { continue }
            if case .hold(let kc) = btn.kind {
                scene?.simulateKeyUp(keyCode: kc)
            }
        }
        activeHoldTouches = [:]
    }

    /// Treffertest: gibt den ersten Button zurück, dessen absoluter Frame den Punkt enthält.
    private func hitButton(at point: CGPoint) -> TouchButton? {
        for btn in buttons {
            guard let frame = buttonFrames[btn.id] else { continue }
            if frame.contains(point) { return btn }
        }
        return nil
    }

    // MARK: - Button-Definitionen je GameState

    /// Erzeugt die passende Button-Liste für einen GameState.
    /// Alle Rects sind relativ zum sicheren Bereich (0…1 normalisiert).
    private func makeButtons(for state: GameState) -> [TouchButton] {
        switch state {

        // ── Spielfeld ──────────────────────────────────────────────────────────────
        case .playing:
            // Links unten: Dreh-Cluster (◄ und ►)
            // Rechts unten: SCHUB (W=13, hold) und FEUER (Space=49, hold)
            // Oben rechts: ESC (53, tap) – klein
            return [
                TouchButton(id: 0, relativeRect: CGRect(x: 0.02, y: 0.55, width: 0.14, height: 0.35),
                            label: "◄", kind: .hold(keyCode: 123)),   // Links drehen (A=0 wäre auch möglich, 123 = Left-Arrow)
                TouchButton(id: 1, relativeRect: CGRect(x: 0.17, y: 0.55, width: 0.14, height: 0.35),
                            label: "►", kind: .hold(keyCode: 124)),   // Rechts drehen
                TouchButton(id: 2, relativeRect: CGRect(x: 0.70, y: 0.45, width: 0.14, height: 0.45),
                            label: "SCHUB", kind: .hold(keyCode: 13)), // W = Schub halten
                TouchButton(id: 3, relativeRect: CGRect(x: 0.86, y: 0.45, width: 0.14, height: 0.45),
                            label: "FEUER", kind: .hold(keyCode: 49)), // Space = Feuer / Charge-Shot halten
                TouchButton(id: 4, relativeRect: CGRect(x: 0.88, y: 0.04, width: 0.10, height: 0.22),
                            label: "ESC", kind: .tap(keyCode: 53)),    // Quit-Bestätigung
            ]

        // ── Startbildschirm ────────────────────────────────────────────────────────
        case .startScreen:
            // Level − / Level +, Modus umschalten, START (groß), INFO (kleiner Tap)
            return [
                TouchButton(id: 10, relativeRect: CGRect(x: 0.02, y: 0.10, width: 0.12, height: 0.35),
                            label: "LVL−", kind: .tap(keyCode: 123)),  // Left = Level runter
                TouchButton(id: 11, relativeRect: CGRect(x: 0.02, y: 0.55, width: 0.12, height: 0.35),
                            label: "LVL+", kind: .tap(keyCode: 124)),  // Right = Level rauf
                TouchButton(id: 12, relativeRect: CGRect(x: 0.16, y: 0.30, width: 0.14, height: 0.40),
                            label: "MODUS", kind: .tap(keyCode: 126)), // Up = Modus wechseln
                TouchButton(id: 13, relativeRect: CGRect(x: 0.38, y: 0.25, width: 0.24, height: 0.50),
                            label: "START", kind: .tap(keyCode: 36)),  // Enter = Starten
                TouchButton(id: 14, relativeRect: CGRect(x: 0.86, y: 0.04, width: 0.12, height: 0.25),
                            label: "INFO", kind: .typeChar("i")),       // Glossar öffnen
            ]

        // ── Initialen-Eingabe ──────────────────────────────────────────────────────
        case .nameEntry:
            // Buchstaben-/Zahlen-Grid (A–Z, 0–9), DEL und OK.
            // Landscape: 9 Spalten × 4 Reihen; Buchstaben A–Z (26) + Ziffern 0–9 (10) = 36 Felder.
            var result: [TouchButton] = []
            let chars: [String] = (65...90).map { String(UnicodeScalar($0)!) }   // A–Z
                                 + (0...9).map { String($0) }                      // 0–9
            let cols = 9
            let cellW = 0.78 / CGFloat(cols)
            let cellH = 0.42 / 4.0  // 4 Reihen
            for (idx, ch) in chars.enumerated() {
                let col = idx % cols
                let row = idx / cols
                let x = 0.02 + CGFloat(col) * cellW
                let y = 0.10 + CGFloat(row) * cellH
                result.append(TouchButton(
                    id: 20 + idx,
                    relativeRect: CGRect(x: x, y: y, width: cellW * 0.90, height: cellH * 0.85),
                    label: ch,
                    kind: .typeChar(ch)
                ))
            }
            // DEL (Backspace) und OK (Enter)
            result.append(TouchButton(id: 90,
                relativeRect: CGRect(x: 0.84, y: 0.55, width: 0.14, height: 0.35),
                label: "DEL", kind: .tap(keyCode: 51)))
            result.append(TouchButton(id: 91,
                relativeRect: CGRect(x: 0.84, y: 0.10, width: 0.14, height: 0.35),
                label: "OK", kind: .tap(keyCode: 36)))
            return result

        // ── Game Over ─────────────────────────────────────────────────────────────
        case .gameOver:
            return [
                TouchButton(id: 100, relativeRect: CGRect(x: 0.30, y: 0.25, width: 0.20, height: 0.50),
                            label: "REPLAY", kind: .tap(keyCode: 49)), // Space = Replay
                TouchButton(id: 101, relativeRect: CGRect(x: 0.55, y: 0.25, width: 0.18, height: 0.50),
                            label: "ZURÜCK", kind: .tap(keyCode: 53)), // Esc = zurück zum Start
            ]

        // ── Quit-Bestätigung ───────────────────────────────────────────────────────
        // Tasten aus handleKeyDown case .quitConfirmation:
        //   Esc(53) = resume (weiterspielen), "y" = startScreen (bestätigen+beenden)
        case .quitConfirmation:
            return [
                TouchButton(id: 110, relativeRect: CGRect(x: 0.28, y: 0.25, width: 0.20, height: 0.50),
                            label: "WEITER", kind: .tap(keyCode: 53)),   // Esc = resume
                TouchButton(id: 111, relativeRect: CGRect(x: 0.54, y: 0.25, width: 0.20, height: 0.50),
                            label: "BEENDEN", kind: .typeChar("y")),      // "y" = zur Startseite
            ]

        // ── Glossar ───────────────────────────────────────────────────────────────
        // Tasten aus handleKeyDown case .glossary:
        //   Esc(53) oder "i" = zurück zum Titel
        //   Up(126)/W(13) = nach oben scrollen
        //   Down(125)/S(1) = nach unten scrollen
        case .glossary:
            return [
                TouchButton(id: 120, relativeRect: CGRect(x: 0.88, y: 0.04, width: 0.10, height: 0.22),
                            label: "✕", kind: .tap(keyCode: 53)),         // Esc = zurück
                TouchButton(id: 121, relativeRect: CGRect(x: 0.88, y: 0.30, width: 0.10, height: 0.28),
                            label: "▲", kind: .tap(keyCode: 126)),        // Up = nach oben scrollen
                TouchButton(id: 122, relativeRect: CGRect(x: 0.88, y: 0.62, width: 0.10, height: 0.28),
                            label: "▼", kind: .tap(keyCode: 125)),        // Down = nach unten scrollen
            ]
        }
    }
}
