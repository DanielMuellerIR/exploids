import SpriteKit

/// Die **Weltraumkatze** – ein Miniboss (kleiner als der Kopf-Boss „Der Götze"). Sie treibt sich
/// nicht sinnlos herum, sondern agiert gezielt: Sie pirscht sich an den Spieler heran, sucht dabei
/// **Deckung hinter großen Asteroiden** und weicht Objekten sowie Spielerschüssen aus. Ihr Angriff
/// sind die **Laseraugen**: ein **Zwillings-Laser** (zwei parallele, längere, langsame Streifen) mit
/// **vorausberechnetem Zielen** (Predictive Aim) – fliegt der Spieler unbeirrt weiter, wird er
/// getroffen. Ausgeglichen wird das durch die geringe Schuss-Frequenz und die halbe Schuss-
/// geschwindigkeit.
///
/// Ablauf: **dreimal** je ein Doppelschuss-Versuch, **dazwischen jeweils ausweichen**; danach
/// **Flucht zum Bildschirmrand – ohne Wrap** (sie verschwindet und kommt nicht zurück).
///
/// Die Grafik ist reines Retro-Vektor-Linienwerk (y nach oben = SpriteKit-Standard, daher – anders
/// als beim Kopf-Boss – keine Spiegelung nötig). Mehrere `SKShapeNode`-Kinder hängen direkt im Node.
public final class SpaceCat: SKNode {

    // MARK: - Phasen des Lebenszyklus

    public enum Phase: Sendable, Equatable {
        case entering        // schwebt vom Bildrand herein
        case stalking        // pirscht sich an, sucht Deckung, zielt – bis der Doppelschuss kommt
        case repositioning   // weicht nach einem Schuss aus, bevor der nächste Versuch folgt
        case fleeing         // flieht nach dem dritten Versuch zum Rand (kein Wrap)
    }

    // MARK: - Zustand

    public private(set) var phase: Phase = .entering

    /// Treffer bis zur Zerstörung – zentral justierbar (Miniboss). Default 2 (mehr als ein normales
    /// UFO mit 1 Treffer, aber deutlich weniger als der Kopf-Boss mit 10).
    public static var hitsToDestroy: Int = 2
    /// Verbleibende Treffer bis zur Zerstörung.
    public private(set) var hitsRemaining: Int = SpaceCat.hitsToDestroy

    /// True, sobald die Katze nach der Flucht komplett aus dem Bild ist (von der GameScene entfernt).
    public private(set) var isFinished: Bool = false

    /// Punkte fürs Zerstören – zwischen kleinem UFO (500) und Kopf-Boss (2000).
    public let pointValue: Int = 750

    /// Ungefährer Kollisionsradius (Kreis) in Szenen-Einheiten.
    public let collisionRadius: CGFloat = 20.0

    /// Geschwindigkeit der Augen-Laser: **halbe Spielerschuss-Geschwindigkeit** (Spieler = 600).
    public static let laserSpeed: CGFloat = 300.0

    // MARK: - Tuning (für Tests/Justierung überschreibbar)

    /// Dauer des Anpirschens/Zielens, bis der Doppelschuss ausgelöst wird (bewusst träge = niedrige
    /// Frequenz; gibt dem Spieler ein Reaktionsfenster).
    public var aimDuration: TimeInterval = 1.6
    /// Dauer des Ausweichens zwischen zwei Schuss-Versuchen.
    public var repositionDuration: TimeInterval = 1.3
    /// Gesamtzahl der Doppelschuss-Versuche, danach Flucht.
    public var totalAttacks: Int = 3

    // MARK: - Intern

    private let screenSize: CGSize
    private let entryTarget: CGPoint

    private var stateTime: TimeInterval = 0.0
    private var attacksRemaining: Int
    private var fleeDirX: CGFloat = 1.0   // Richtung der Flucht (+1 = nach rechts raus)

    // Bewegung (Steering) – eigene, gedeckelte Geschwindigkeit. Nimble, aber nicht irrwitzig.
    private var moveVelocity: CGPoint = .zero
    private let maxMoveSpeed: CGFloat = 230.0
    private let enterSpeed: CGFloat = 240.0
    private let fleeSpeed: CGFloat = 360.0
    private let attackDistance: CGFloat = 280.0   // bevorzugter Schuss-Abstand zum Schiff
    private let minDistance: CGFloat = 170.0      // näher will die Katze nicht heran
    private let approachStrength: CGFloat = 520.0
    private let coverStrength: CGFloat = 360.0    // Sog Richtung „hinter einem Asteroiden"
    private let coverSearchRange: CGFloat = 360.0 // nur Asteroiden in dieser Nähe als Deckung nutzen
    private let coverMargin: CGFloat = 14.0       // Sicherheitsabstand hinter der Deckung
    private let avoidBuffer: CGFloat = 18.0       // Abstand, ab dem Objekten ausgewichen wird
    private let avoidStrength: CGFloat = 900.0
    private let dodgeStrength: CGFloat = 1100.0   // Ausweichen vor Spielerschüssen
    private let dodgeRadius: CGFloat = 70.0       // seitlicher Gefahren-Korridor um einen Schuss
    private let dodgeLookahead: CGFloat = 240.0   // wie weit voraus Schüsse beachtet werden
    private let boundsStrength: CGFloat = 26.0    // hält sie im sichtbaren Bereich (außer bei Flucht)
    private let moveFriction: CGFloat = 0.86      // Dämpfung pro 1/60 s, frameraten-normiert

    // Augen-Geometrie (lokale Koordinaten) – Ursprung der Laser liegt vor den Augen.
    private let eyeSpacing: CGFloat = 7.0         // halber Augenabstand (parallele Laser)
    private let muzzleAhead: CGFloat = 18.0       // Laser-Ursprung etwas vor den Körper legen

    // Farben (Retro-Vektor, Violett-Körper mit glühenden Orange-Augen – klar verschieden von
    // den grün/pinken UFOs und dem Stein-Boss).
    private let body  = SKColor(red: 0.72, green: 0.42, blue: 1.0, alpha: 1.0)
    private let glow  = SKColor(red: 1.0,  green: 0.55, blue: 0.1, alpha: 1.0)
    private let whisk = SKColor(red: 0.85, green: 0.8,  blue: 1.0, alpha: 0.9)

    // Grafik-Referenzen (Augen werden beim Schuss kurz hell aufgepulst).
    private var leftEye: SKShapeNode!
    private var rightEye: SKShapeNode!

    // MARK: - Rückgabe beim Schuss

    /// Beschreibung eines Doppelschusses: zwei **parallele** Laser-Ursprünge und der gemeinsame
    /// Winkel. Die GameScene baut daraus zwei `Laser` vom Typ `.catEye`.
    public struct TwinLaserShot: Sendable {
        public let origins: [CGPoint]   // genau zwei, parallel versetzt
        public let angle: CGFloat
    }

    // MARK: - Init

    /// Erzeugt eine Weltraumkatze für eine gegebene Szenengröße. Sie startet komplett außerhalb des
    /// Bildrands (links oder rechts) und schwebt in den sichtbaren Bereich; danach übernimmt die KI.
    public init(screenSize: CGSize, startOnLeft: Bool) {
        self.screenSize = screenSize
        self.attacksRemaining = totalAttacks
        let halfW = screenSize.width / 2
        let entryY = CGFloat.random(in: -screenSize.height * 0.25...screenSize.height * 0.25)
        self.entryTarget = CGPoint(x: startOnLeft ? -halfW * 0.45 : halfW * 0.45, y: entryY)
        super.init()

        self.position = CGPoint(x: startOnLeft ? -halfW - 50.0 : halfW + 50.0, y: entryY)
        self.zPosition = 5
        buildArt()
    }

    public required init?(coder aDecoder: NSCoder) {
        self.screenSize = CGSize(width: 1024, height: 768)
        self.attacksRemaining = 3
        self.entryTarget = CGPoint(x: 200, y: 0)
        super.init(coder: aDecoder)
    }

    // MARK: - Öffentliche API (Spiel-Logik)

    /// Schreitet den Zustandsautomaten um `deltaTime` voran.
    /// - Parameter coverObjects: Positionen + Radien geeigneter Deckungsobjekte (große/mittlere
    ///   Asteroiden), hinter die sich die Katze stellt.
    /// - Parameter laserThreats: Position + Geschwindigkeit der Spielerschüsse (zum Ausweichen).
    /// - Returns: Einen `TwinLaserShot`, falls die Katze **in diesem Frame** feuert, sonst `nil`.
    @discardableResult
    public func update(deltaTime: TimeInterval, shipPosition: CGPoint, shipVelocity: CGPoint,
                       coverObjects: [(position: CGPoint, radius: CGFloat)] = [],
                       laserThreats: [(position: CGPoint, velocity: CGPoint)] = []) -> TwinLaserShot? {
        var shot: TwinLaserShot? = nil

        switch phase {
        case .entering:
            moveToward(entryTarget, speed: enterSpeed, dt: deltaTime)
            if distance(position, entryTarget) < 6.0 {
                position = entryTarget
                enterStalking()
            }

        case .stalking:
            updateMovement(dt: deltaTime, shipPos: shipPosition, cover: coverObjects,
                           threats: laserThreats, seekCover: true)
            stateTime += deltaTime
            if stateTime >= aimDuration {
                shot = makeTwinShot(shipPos: shipPosition, shipVel: shipVelocity)
                flashEyes()
                attacksRemaining -= 1
                if attacksRemaining > 0 {
                    enterRepositioning(awayFrom: shipPosition)
                } else {
                    enterFleeing(awayFrom: shipPosition)
                }
            }

        case .repositioning:
            updateMovement(dt: deltaTime, shipPos: shipPosition, cover: coverObjects,
                           threats: laserThreats, seekCover: false)
            stateTime += deltaTime
            if stateTime >= repositionDuration {
                enterStalking()
            }

        case .fleeing:
            // Geradlinig zum Rand hinaus – keine weiteren Manöver, kein Wrap.
            position.x += fleeDirX * fleeSpeed * CGFloat(deltaTime)
            let threshold = screenSize.width / 2 + 60.0
            if abs(position.x) > threshold {
                isFinished = true
            }
        }

        return shot
    }

    /// Verarbeitet einen Spieler-Treffer. Gibt `true` zurück, wenn die Katze dadurch zerstört ist.
    @discardableResult
    public func registerHit() -> Bool {
        guard hitsRemaining > 0 else { return true }
        hitsRemaining -= 1
        flashEyes()
        return hitsRemaining <= 0
    }

    /// Für Tests: überspringt die Einschweb-Phase und beginnt sofort am Lauer-Ort mit dem Anpirschen.
    public func beginStalkingForTesting() {
        position = entryTarget
        enterStalking()
    }

    // MARK: - Phasenübergänge

    private func enterStalking() {
        phase = .stalking
        stateTime = 0.0
    }

    private func enterRepositioning(awayFrom shipPos: CGPoint) {
        phase = .repositioning
        stateTime = 0.0
        // Seitlicher Ausweich-Impuls senkrecht zur Linie Katze→Schiff (zufällige Seite).
        let dx = position.x - shipPos.x, dy = position.y - shipPos.y
        let d = max(1.0, hypot(dx, dy))
        let perpX = -dy / d, perpY = dx / d
        let side: CGFloat = Bool.random() ? 1.0 : -1.0
        moveVelocity.x += perpX * side * maxMoveSpeed
        moveVelocity.y += perpY * side * maxMoveSpeed
    }

    private func enterFleeing(awayFrom shipPos: CGPoint) {
        phase = .fleeing
        // Zum Rand fliehen, der vom Schiff weg zeigt (sonst müsste sie am Spieler vorbei).
        fleeDirX = (position.x >= shipPos.x) ? 1.0 : -1.0
    }

    // MARK: - Schuss (Predictive Aim, Zwillings-Laser)

    private func makeTwinShot(shipPos: CGPoint, shipVel: CGPoint) -> TwinLaserShot {
        // Flugzeit iterativ schätzen und das Ziel entsprechend voraushalten.
        var t = distance(position, shipPos) / SpaceCat.laserSpeed
        for _ in 0..<2 {
            let pred = CGPoint(x: shipPos.x + shipVel.x * t, y: shipPos.y + shipVel.y * t)
            t = distance(position, pred) / SpaceCat.laserSpeed
        }
        let predicted = CGPoint(x: shipPos.x + shipVel.x * t, y: shipPos.y + shipVel.y * t)
        let angle = atan2(predicted.y - position.y, predicted.x - position.x)

        // Zwei parallele Ursprünge: vor den Körper gelegt und senkrecht zum Schuss versetzt.
        let dirX = cos(angle), dirY = sin(angle)
        let perpX = -dirY, perpY = dirX
        let base = CGPoint(x: position.x + dirX * muzzleAhead, y: position.y + dirY * muzzleAhead)
        let a = CGPoint(x: base.x + perpX * eyeSpacing, y: base.y + perpY * eyeSpacing)
        let b = CGPoint(x: base.x - perpX * eyeSpacing, y: base.y - perpY * eyeSpacing)
        return TwinLaserShot(origins: [a, b], angle: angle)
    }

    // MARK: - Bewegung / Steering

    private func moveToward(_ target: CGPoint, speed: CGFloat, dt: TimeInterval) {
        let dx = target.x - position.x, dy = target.y - position.y
        let d = hypot(dx, dy)
        let step = speed * CGFloat(dt)
        if d <= step || d == 0 {
            position = target
        } else {
            position.x += dx / d * step
            position.y += dy / d * step
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    /// Steering aus mehreren Kräften: Abstand zum Schiff halten, Deckung suchen, Schüssen ausweichen,
    /// Objekten ausweichen, im Bild bleiben. Bewusst gedeckelt – fordernd, aber nicht unfair.
    private func updateMovement(dt: TimeInterval, shipPos: CGPoint,
                                cover: [(position: CGPoint, radius: CGFloat)],
                                threats: [(position: CGPoint, velocity: CGPoint)],
                                seekCover: Bool) {
        var fx: CGFloat = 0, fy: CGFloat = 0

        // 1. Schuss-Abstand zum Schiff halten (zu weit → ran, zu nah → weg).
        let ax = shipPos.x - position.x, ay = shipPos.y - position.y
        let d = max(1.0, hypot(ax, ay))
        if d > attackDistance {
            let w = min(1.0, (d - attackDistance) / attackDistance)
            fx += ax / d * approachStrength * w
            fy += ay / d * approachStrength * w
        } else if d < minDistance {
            let w = (minDistance - d) / minDistance
            fx -= ax / d * approachStrength * w
            fy -= ay / d * approachStrength * w
        }

        // 2. Deckung suchen: hinter den nächsten geeigneten Asteroiden (relativ zum Schiff) stellen.
        if seekCover, let best = nearestCover(cover, shipPos: shipPos) {
            let toShipX = shipPos.x - best.position.x, toShipY = shipPos.y - best.position.y
            let dl = max(1.0, hypot(toShipX, toShipY))
            // „Hinter" dem Asteroiden = auf der vom Schiff abgewandten Seite.
            let behind = CGPoint(
                x: best.position.x - toShipX / dl * (best.radius + collisionRadius + coverMargin),
                y: best.position.y - toShipY / dl * (best.radius + collisionRadius + coverMargin)
            )
            let cx = behind.x - position.x, cy = behind.y - position.y
            let cd = max(1.0, hypot(cx, cy))
            fx += cx / cd * coverStrength
            fy += cy / cd * coverStrength
        }

        // 3. Spielerschüssen ausweichen (seitlich aus der Bahn gleiten).
        for tr in threats {
            let dirLen = hypot(tr.velocity.x, tr.velocity.y)
            guard dirLen > 0.001 else { continue }
            let vx = tr.velocity.x / dirLen, vy = tr.velocity.y / dirLen
            let rx = position.x - tr.position.x, ry = position.y - tr.position.y
            let along = rx * vx + ry * vy
            guard along >= 0 && along <= dodgeLookahead else { continue }   // nur heranfliegende Schüsse
            var perpx = rx - vx * along, perpy = ry - vy * along
            let pd = hypot(perpx, perpy)
            guard pd < dodgeRadius else { continue }
            if pd < 1.0 { perpx = -vy; perpy = vx }   // genau auf der Linie: eine Seite wählen
            let n = max(1.0, hypot(perpx, perpy))
            let w = 1.0 - pd / dodgeRadius
            fx += perpx / n * dodgeStrength * w
            fy += perpy / n * dodgeStrength * w
        }

        // 4. Objekten ausweichen (nicht hineinfahren): von zu nahen Asteroiden wegdrücken.
        for obj in cover {
            let ox = position.x - obj.position.x, oy = position.y - obj.position.y
            let od = hypot(ox, oy)
            let safe = obj.radius + collisionRadius + avoidBuffer
            if od < safe && od > 0.001 {
                let w = (safe - od) / safe
                fx += ox / od * avoidStrength * w
                fy += oy / od * avoidStrength * w
            }
        }

        // 5. Im Bild halten (weiche Grenzen).
        let halfW = screenSize.width * 0.5, halfH = screenSize.height * 0.5
        let limX = halfW * 0.86, limY = halfH * 0.78
        if position.x >  limX { fx -= boundsStrength * (position.x - limX) }
        if position.x < -limX { fx += boundsStrength * (-limX - position.x) }
        if position.y >  limY { fy -= boundsStrength * (position.y - limY) }
        if position.y < -limY { fy += boundsStrength * (-limY - position.y) }

        // Integrieren, dämpfen (frameraten-normiert), Geschwindigkeit deckeln.
        moveVelocity.x += fx * CGFloat(dt)
        moveVelocity.y += fy * CGFloat(dt)
        let fr = pow(moveFriction, CGFloat(dt) * 60.0)
        moveVelocity.x *= fr
        moveVelocity.y *= fr
        let sp = hypot(moveVelocity.x, moveVelocity.y)
        if sp > maxMoveSpeed {
            moveVelocity.x *= maxMoveSpeed / sp
            moveVelocity.y *= maxMoveSpeed / sp
        }
        position.x += moveVelocity.x * CGFloat(dt)
        position.y += moveVelocity.y * CGFloat(dt)
    }

    /// Liefert den nächstgelegenen Asteroiden im Suchradius, der als Deckung taugt.
    private func nearestCover(_ cover: [(position: CGPoint, radius: CGFloat)],
                              shipPos: CGPoint) -> (position: CGPoint, radius: CGFloat)? {
        var best: (position: CGPoint, radius: CGFloat)? = nil
        var bestD = coverSearchRange
        for obj in cover {
            let dd = distance(position, obj.position)
            if dd < bestD {
                bestD = dd
                best = obj
            }
        }
        return best
    }

    // MARK: - Grafik

    /// Kurzes Hell-Aufpulsen der Augen (beim Feuern und bei einem Treffer).
    private func flashEyes() {
        guard leftEye != nil, rightEye != nil else { return }
        let pulse = SKAction.sequence([
            .group([.scale(to: 1.7, duration: 0.06), .fadeAlpha(to: 1.0, duration: 0.06)]),
            .group([.scale(to: 1.0, duration: 0.18), .fadeAlpha(to: 0.85, duration: 0.18)])
        ])
        leftEye.run(pulse)
        rightEye.run(pulse)
    }

    private func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    private func buildArt() {
        // Gesicht (geschlossene Kontur).
        let face = CGMutablePath()
        face.move(to: P(-14, 8))
        face.addLine(to: P(-17, -2))
        face.addLine(to: P(-12, -13))
        face.addLine(to: P(0, -17))
        face.addLine(to: P(12, -13))
        face.addLine(to: P(17, -2))
        face.addLine(to: P(14, 8))
        face.closeSubpath()
        let faceNode = SKShapeNode(path: face)
        faceNode.strokeColor = body
        faceNode.fillColor = body.withAlphaComponent(0.12)
        faceNode.lineWidth = 1.8
        faceNode.lineJoin = .round
        addChild(faceNode)

        // Ohren (gefüllte Dreiecke).
        addChild(triangle(P(-14, 7), P(-19, 20), P(-5, 10)))
        addChild(triangle(P(14, 7), P(19, 20), P(5, 10)))

        // Schnurrhaare (dünne Linien beidseits).
        addChild(whiskers([
            [P(-4, -7), P(-18, -5)], [P(-4, -9), P(-18, -12)],
            [P(4, -7), P(18, -5)],  [P(4, -9), P(18, -12)]
        ]))

        // Nase (kleines Dreieck nach unten).
        let nose = triangle(P(-2.5, -6), P(2.5, -6), P(0, -10))
        nose.fillColor = glow
        addChild(nose)

        // Schweif (eine geschwungene Linie, die seitlich nach oben kringelt – signalisiert „Katze").
        let tail = CGMutablePath()
        tail.move(to: P(15, -6))
        tail.addQuadCurve(to: P(26, 12), control: P(31, -2))
        let tailNode = SKShapeNode(path: tail)
        tailNode.strokeColor = body
        tailNode.fillColor = .clear
        tailNode.lineWidth = 2.2
        tailNode.lineCap = .round
        addChild(tailNode)

        // Glühende Schlitz-Augen (die „Laseraugen").
        leftEye = eyeNode(at: P(-7, -1))
        rightEye = eyeNode(at: P(7, -1))
        addChild(leftEye)
        addChild(rightEye)
    }

    /// Ein glühendes Katzenauge: helle Mandel mit dunklem senkrechten Schlitz (Pupille).
    private func eyeNode(at center: CGPoint) -> SKShapeNode {
        let node = SKShapeNode()
        let p = CGMutablePath()
        // Mandelform (breiter als hoch).
        p.addEllipse(in: CGRect(x: -4.0, y: -2.6, width: 8.0, height: 5.2))
        node.path = p
        node.fillColor = glow
        node.strokeColor = glow
        node.lineWidth = 0.8
        node.alpha = 0.85
        node.position = center

        // Senkrechte Schlitz-Pupille.
        let slit = SKShapeNode(rect: CGRect(x: -0.7, y: -2.0, width: 1.4, height: 4.0))
        slit.fillColor = SKColor(red: 0.1, green: 0.02, blue: 0.0, alpha: 1.0)
        slit.strokeColor = .clear
        node.addChild(slit)
        return node
    }

    private func triangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> SKShapeNode {
        let p = CGMutablePath()
        p.move(to: a)
        p.addLine(to: b)
        p.addLine(to: c)
        p.closeSubpath()
        let node = SKShapeNode(path: p)
        node.strokeColor = body
        node.fillColor = body.withAlphaComponent(0.18)
        node.lineWidth = 1.6
        node.lineJoin = .round
        return node
    }

    private func whiskers(_ segments: [[CGPoint]]) -> SKShapeNode {
        let p = CGMutablePath()
        for seg in segments {
            guard let first = seg.first else { continue }
            p.move(to: first)
            for pt in seg.dropFirst() { p.addLine(to: pt) }
        }
        let node = SKShapeNode(path: p)
        node.strokeColor = whisk
        node.fillColor = .clear
        node.lineWidth = 1.0
        node.lineCap = .round
        return node
    }
}
