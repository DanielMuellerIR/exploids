import SpriteKit

/// Der Kopf-Boss „Der Götze" – ein geschnitzter Greisen-Totem als echter Boss (kein normaler
/// Gegner). Er ist ein **reiner Spawner**: Er schwebt herein, lauert eine Weile (Augen folgen dem
/// Schiff), öffnet dann den Mund und speit eine **Armada von 10 UFOs** (Mix aus großen und kleinen)
/// gestaffelt aus dem Mund-Mittelpunkt, und zieht sich danach zurück.
///
/// Strategie für den Spieler: den Kopf möglichst **vor** dem Mund-Öffnen mit 3 Treffern zerstören,
/// sonst wenigstens die UFOs beim Herauskommen abfangen. Wird der Kopf **während** des Ausstoßes
/// zerstört, bleiben die restlichen UFOs aus (das erledigt die GameScene, indem sie den Kopf entfernt).
///
/// Aussehen wird in den **Koordinaten des Design-Mockups** aufgebaut (y nach unten). Damit der Kopf
/// in SpriteKit (y nach oben) aufrecht steht, sitzen alle Grafikteile in einem Container `art`, der
/// per `yScale < 0` gespiegelt ist; ein Skalierungsfaktor bringt ihn auf die gewünschte Spielgröße.
public final class FloatingHead: SKNode {

    /// Die Phasen des Boss-Lebenszyklus.
    public enum Phase: Sendable, Equatable {
        case entering    // schwebt vom oberen Rand herein
        case lurking     // lauert, Augen tracken – Zeitfenster zum Töten
        case spawning    // Mund auf, speit die UFO-Armada
        case retreating  // Mund zu, zieht sich zurück
    }

    // MARK: - Zustand

    public private(set) var phase: Phase = .entering
    /// Verbleibende Treffer bis zur Zerstörung (Start: 3).
    public private(set) var hitsRemaining: Int = 3
    /// True, sobald der Kopf sich nach dem Rückzug komplett aus dem Bild entfernt hat.
    public private(set) var isFinished: Bool = false

    /// Ungefährer Kollisionsradius (Kreis) in Szenen-Einheiten – etwas größer als der größte
    /// Asteroid (Radius 40).
    public let collisionRadius: CGFloat = 88.0

    // MARK: - Tuning (für Tests überschreibbar)

    /// Lauer-Dauer in Sekunden, bis der Mund aufgeht (im Spiel zufällig 5–8 s).
    public var lurkDuration: TimeInterval = Double.random(in: 5.0...8.0)
    /// Dauer des Mund-Öffnens bzw. -Schließens.
    public var mouthMoveDuration: TimeInterval = 0.45
    /// Abstand zwischen zwei ausgespienen UFOs.
    public var spawnInterval: TimeInterval = 0.25
    /// Gesamtzahl auszuspeiender UFOs.
    public var totalSpawns: Int = 10

    // MARK: - Intern

    private let screenSize: CGSize
    private let hoverTarget: CGPoint
    private let offscreenY: CGFloat
    private let enterSpeed: CGFloat = 190.0

    private var stateTime: TimeInterval = 0.0
    private var spawnsDone: Int = 0
    private var spawnAccumulator: TimeInterval = 0.0
    /// 0 = Mund zu, 1 = Mund ganz offen.
    private var mouthProgress: CGFloat = 0.0

    private let artScale: CGFloat = 0.5

    // Grafik-Referenzen
    private let art = SKNode()
    private var leftPupil: SKShapeNode!
    private var rightPupil: SKShapeNode!
    private let leftSocketCenter = CGPoint(x: -48, y: -18)   // Mockup-Koordinaten (y nach unten)
    private let rightSocketCenter = CGPoint(x: 48, y: -18)
    private var closedLips: SKNode!
    private var openMaw: SKNode!
    // Schadens-Risse (anfangs versteckt, je Treffer eine Stufe sichtbar).
    private var leftEyeCrack: SKShapeNode!
    private var rightEyeCrack: SKShapeNode!
    private var jawCrack: SKShapeNode!
    /// y-Position des Mund-Mittelpunkts in Mockup-Koordinaten (Spawn-Ursprung der UFOs).
    private let mouthLocalY: CGFloat = 108.0

    // Farben (an das Mockup angelehnt)
    private let stone   = SKColor(red: 0.79, green: 0.71, blue: 0.53, alpha: 1.0)
    private let carve   = SKColor(red: 0.55, green: 0.49, blue: 0.33, alpha: 1.0)
    private let eyeGlow = SKColor(red: 0.92, green: 1.0,  blue: 0.97, alpha: 1.0)
    private let pupilCol = SKColor(red: 1.0,  green: 0.27, blue: 0.14, alpha: 1.0)
    private let mouthYellow = SKColor(red: 1.0, green: 0.8, blue: 0.27, alpha: 1.0)
    private let fangCol = SKColor(red: 0.91, green: 0.86, blue: 0.71, alpha: 1.0)
    private let throatCol = SKColor(red: 0.03, green: 0.03, blue: 0.02, alpha: 1.0)
    private let crackRed = SKColor(red: 1.0, green: 0.23, blue: 0.42, alpha: 1.0)

    // MARK: - Init

    /// Erzeugt den Kopf-Boss für eine gegebene Szenengröße. Er startet über dem oberen Bildrand und
    /// schwebt in den oberen Bildbereich hinein.
    public init(screenSize: CGSize) {
        self.screenSize = screenSize
        self.hoverTarget = CGPoint(x: 0, y: screenSize.height * 0.18)
        self.offscreenY = screenSize.height * 0.5 + 280.0
        super.init()

        // Container gespiegelt (Mockup-y nach unten -> SpriteKit-y nach oben) und skaliert.
        art.xScale = artScale
        art.yScale = -artScale
        addChild(art)
        buildArt()

        self.position = CGPoint(x: 0, y: offscreenY)
        self.zPosition = 5
        setMouthOpen(0)
    }

    public required init?(coder aDecoder: NSCoder) {
        self.screenSize = CGSize(width: 1024, height: 768)
        self.hoverTarget = CGPoint(x: 0, y: 138)
        self.offscreenY = 664
        super.init(coder: aDecoder)
    }

    // MARK: - Öffentliche API (Spiel-Logik)

    /// Schreitet den Zustandsautomaten um `deltaTime` voran und richtet die Augen auf das Schiff aus.
    /// Rückgabewert: Anzahl der **in diesem Frame** auszuspeienden UFOs (0, außer in der Spawn-Phase).
    /// Die GameScene erzeugt diese UFOs dann an `mouthWorldPosition`.
    @discardableResult
    public func update(deltaTime: TimeInterval, shipPosition: CGPoint) -> Int {
        trackEyes(towards: shipPosition)
        var emit = 0

        switch phase {
        case .entering:
            moveToward(hoverTarget, speed: enterSpeed, dt: deltaTime)
            if distance(position, hoverTarget) < 6.0 {
                position = hoverTarget
                phase = .lurking
                stateTime = 0.0
            }

        case .lurking:
            stateTime += deltaTime
            if stateTime >= lurkDuration {
                phase = .spawning
                stateTime = 0.0
                spawnsDone = 0
                spawnAccumulator = 0.0
            }

        case .spawning:
            // Mund öffnen.
            advanceMouth(toward: 1.0, dt: deltaTime)
            // Erst speien, wenn der Mund weit genug offen ist.
            if mouthProgress > 0.85 {
                spawnAccumulator += deltaTime
                while spawnAccumulator >= spawnInterval && spawnsDone < totalSpawns {
                    spawnAccumulator -= spawnInterval
                    spawnsDone += 1
                    emit += 1
                }
            }
            if emit > 0 { showMouthSpawnFlash() }
            if spawnsDone >= totalSpawns {
                phase = .retreating
                stateTime = 0.0
            }

        case .retreating:
            advanceMouth(toward: 0.0, dt: deltaTime)
            // Nach oben zurückziehen, von wo er kam.
            moveToward(CGPoint(x: position.x, y: offscreenY), speed: enterSpeed, dt: deltaTime)
            if position.y >= offscreenY - 1.0 {
                isFinished = true
            }
        }

        return emit
    }

    /// Verarbeitet einen Spieler-Treffer. Gibt `true` zurück, wenn der Kopf dadurch zerstört ist.
    /// Bei jedem Treffer ein sichtbares Feedback (Weiß-Flash + zunehmender Vektor-Schaden).
    @discardableResult
    public func registerHit() -> Bool {
        guard hitsRemaining > 0 else { return true }
        hitsRemaining -= 1
        showHitFeedback()
        updateDamageVisual()
        return hitsRemaining <= 0
    }

    /// Für Tests: versetzt den Kopf sofort in die Spawn-Phase an der Lauer-Position (offener Mund),
    /// damit die Einschweb-Phase nicht abgewartet werden muss.
    public func beginSpawningForTesting() {
        position = hoverTarget
        phase = .spawning
        stateTime = 0.0
        spawnsDone = 0
        spawnAccumulator = 0.0
        mouthProgress = 1.0
        setMouthOpen(1.0)
    }

    /// Weltkoordinaten des Mund-Mittelpunkts – Ursprung, an dem die UFOs materialisieren.
    public var mouthWorldPosition: CGPoint {
        if let scene = scene {
            return art.convert(CGPoint(x: 0, y: mouthLocalY), to: scene)
        }
        // Fallback ohne Szene (Tests): über die bekannte Spiegelung/Skalierung rechnen.
        return CGPoint(x: position.x, y: position.y - mouthLocalY * artScale)
    }

    // MARK: - Bewegung / Helfer

    private func moveToward(_ target: CGPoint, speed: CGFloat, dt: TimeInterval) {
        let dx = target.x - position.x
        let dy = target.y - position.y
        let d = hypot(dx, dy)
        let step = speed * CGFloat(dt)
        if d <= step || d == 0 {
            position = target
        } else {
            position.x += dx / d * step
            position.y += dy / d * step
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        return hypot(a.x - b.x, a.y - b.y)
    }

    private func advanceMouth(toward target: CGFloat, dt: TimeInterval) {
        let rate = CGFloat(1.0 / mouthMoveDuration)
        if mouthProgress < target {
            mouthProgress = min(target, mouthProgress + rate * CGFloat(dt))
        } else if mouthProgress > target {
            mouthProgress = max(target, mouthProgress - rate * CGFloat(dt))
        }
        setMouthOpen(mouthProgress)
    }

    /// Setzt die Mund-Öffnung (0 = geschlossen: Lippen sichtbar; 1 = offen: Schlund sichtbar).
    private func setMouthOpen(_ progress: CGFloat) {
        let p = max(0.0, min(1.0, progress))
        closedLips.alpha = 1.0 - p
        openMaw.alpha = p
        // Schlund wächst vertikal aus der Mund-Mitte heraus.
        openMaw.yScale = max(0.05, p)
    }

    private func trackEyes(towards shipWorld: CGPoint) {
        guard scene != nil, leftPupil != nil else { return }
        let localShip = art.convert(shipWorld, from: scene!)
        positionPupil(leftPupil, socket: leftSocketCenter, towards: localShip)
        positionPupil(rightPupil, socket: rightSocketCenter, towards: localShip)
    }

    private func positionPupil(_ pupil: SKShapeNode, socket: CGPoint, towards localShip: CGPoint) {
        let dx = localShip.x - socket.x
        let dy = localShip.y - socket.y
        let d = hypot(dx, dy)
        let maxOffset: CGFloat = 6.0
        if d < 0.001 {
            pupil.position = socket
        } else {
            let k = min(maxOffset, d) / d
            pupil.position = CGPoint(x: socket.x + dx * k, y: socket.y + dy * k)
        }
    }

    private func showHitFeedback() {
        // Kurzer Weiß-Flash über den ganzen Kopf.
        let flash = SKAction.sequence([
            .run { [weak self] in self?.tint(.white) },
            .wait(forDuration: 0.08),
            .run { [weak self] in self?.tint(nil) }
        ])
        art.run(flash)
    }

    /// Färbt alle Linien kurz um (Flash). `nil` stellt die Originalfarben wieder her.
    private func tint(_ color: SKColor?) {
        for node in art.children {
            guard let shape = node as? SKShapeNode else { continue }
            if shape.strokeColor != .clear {
                shape.strokeColor = color ?? originalColor(for: shape)
            }
        }
    }

    private func originalColor(for shape: SKShapeNode) -> SKColor {
        switch shape.name {
        case "yellow": return mouthYellow
        case "red":    return crackRed
        default:       return stone
        }
    }

    /// Zeigt die Schadens-Risse passend zur Trefferzahl (Stufe 1: ein Auge, Stufe 2: zweites Auge + Kiefer).
    private func updateDamageVisual() {
        let stage = 3 - hitsRemaining   // 1, 2 oder 3
        if stage >= 1 { leftEyeCrack.isHidden = false }
        if stage >= 2 {
            rightEyeCrack.isHidden = false
            jawCrack.isHidden = false
        }
    }

    /// Kurzer Materialisier-Blitz (Ring) im Mund-Mittelpunkt, wenn ein UFO ausgespien wird.
    private func showMouthSpawnFlash() {
        guard scene != nil else { return }
        let ring = SKShapeNode(circleOfRadius: 8)
        ring.position = CGPoint(x: 0, y: mouthLocalY)
        ring.strokeColor = eyeGlow
        ring.fillColor = .clear
        ring.lineWidth = 2
        art.addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: 2.6, duration: 0.25), .fadeOut(withDuration: 0.25)]),
            .removeFromParent()
        ]))
    }

    // MARK: - Grafik-Aufbau (Mockup-Koordinaten, y nach unten)

    private func buildArt() {
        // Silhouette (dunkel gefüllt, Stein-Kontur)
        let sil = SKShapeNode(path: silhouettePath())
        sil.fillColor = SKColor(red: 0.05, green: 0.04, blue: 0.03, alpha: 1.0)
        sil.strokeColor = stone
        sil.lineWidth = 3
        sil.lineJoin = .round
        art.addChild(sil)

        // Mähne / Stirn / Wangen / Bart (Stein-Kerben)
        art.addChild(strokeNode(carve, 1.7, segments: [
            [P(-100,-120),P(-78,-95)], [P(-60,-160),P(-52,-128)], [P(-22,-176),P(-20,-140)],
            [P(22,-176),P(20,-140)], [P(60,-160),P(52,-128)], [P(100,-120),P(78,-95)],
            [P(-120,-72),P(-96,-60)], [P(120,-72),P(96,-60)]
        ]))
        art.addChild(quadNode(carve, 1.6, quads: [
            (P(-64,-92),P(0,-104),P(64,-92)), (P(-72,-74),P(0,-86),P(72,-74))
        ]))
        art.addChild(strokeNode(carve, 1.6, segments: [
            [P(-9,-58),P(-11,-40)], [P(9,-58),P(11,-40)], [P(0,-60),P(0,-40)]
        ]))
        art.addChild(strokeNode(carve, 1.5, segments: [
            [P(-96,-4),P(-58,8)], [P(-92,18),P(-56,28)], [P(96,-4),P(58,8)], [P(92,18),P(56,28)]
        ]))
        art.addChild(quadNode(carve, 1.5, quads: [
            (P(-30,32),P(-46,48),P(-44,68)), (P(30,32),P(46,48),P(44,68))
        ]))

        // Schnauzbart
        art.addChild(quadNode(carve, 2.2, quads: [
            (P(-54,72),P(-34,64),P(-8,74)), (P(54,72),P(34,64),P(8,74))
        ]))

        // Bart-Locken zur Kinnspitze
        art.addChild(quadNode(carve, 1.8, quads: [
            (P(-92,64),P(-100,124),P(-72,188)), (P(-66,86),P(-70,146),P(-50,198)),
            (P(-34,158),P(-44,180),P(-10,206)), (P(0,166),P(0,190),P(0,212)),
            (P(34,158),P(44,180),P(10,206)), (P(66,86),P(70,146),P(50,198)),
            (P(92,64),P(100,124),P(72,188))
        ]))

        // Buschige Brauen + Tufts
        art.addChild(quadNode(stone, 5.0, cap: .round, quads: [
            (P(-98,-44),P(-66,-66),P(-34,-44)), (P(98,-44),P(66,-66),P(34,-44))
        ]))
        art.addChild(strokeNode(carve, 2.0, cap: .round, segments: [
            [P(-98,-44),P(-106,-56)], [P(-78,-56),P(-82,-70)], [P(-58,-58),P(-60,-72)], [P(-38,-48),P(-38,-62)],
            [P(98,-44),P(106,-56)], [P(78,-56),P(82,-70)], [P(58,-58),P(60,-72)], [P(38,-48),P(38,-62)]
        ]))

        // Augenhöhlen + Glüh-Augäpfel + bewegliche Pupillen
        art.addChild(socketNode(center: leftSocketCenter, mirror: false))
        art.addChild(socketNode(center: rightSocketCenter, mirror: true))
        art.addChild(circleNode(eyeGlow, filled: true, center: leftSocketCenter, r: 8.5))
        art.addChild(circleNode(eyeGlow, filled: true, center: rightSocketCenter, r: 8.5))
        leftPupil = circleNode(pupilCol, filled: true, center: leftSocketCenter, r: 3.8)
        rightPupil = circleNode(pupilCol, filled: true, center: rightSocketCenter, r: 3.8)
        art.addChild(leftPupil)
        art.addChild(rightPupil)

        // Schadens-Risse (versteckt; je Treffer eine Stufe sichtbar).
        leftEyeCrack = strokeNode(crackRed, 2.0, segments: [
            [P(-60,-26),P(-50,-18),P(-58,-12),P(-46,-10)], [P(-48,-20),P(-40,-28)]
        ])
        leftEyeCrack.name = "red"; leftEyeCrack.isHidden = true
        art.addChild(leftEyeCrack)

        rightEyeCrack = strokeNode(crackRed, 2.0, segments: [
            [P(60,-26),P(50,-18),P(58,-12),P(46,-10)], [P(48,-20),P(40,-28)]
        ])
        rightEyeCrack.name = "red"; rightEyeCrack.isHidden = true
        art.addChild(rightEyeCrack)

        jawCrack = strokeNode(crackRed, 2.0, segments: [
            [P(-118,10),P(-98,4),P(-108,20),P(-90,16)], [P(40,34),P(56,40),P(46,54)], [P(-44,70),P(-28,92)]
        ])
        jawCrack.name = "red"; jawCrack.isHidden = true
        art.addChild(jawCrack)

        // Hakennase
        let nose = SKShapeNode(path: nosePath())
        nose.fillColor = .clear
        nose.strokeColor = stone
        nose.lineWidth = 2.4
        nose.lineJoin = .round
        art.addChild(nose)

        // ---- Mund: geschlossene Lippen ----
        closedLips = SKNode()
        closedLips.addChild(quadNode(stone, 2.8, quadsCubicAsTwo: [
            (P(-46,104),P(-23,95),P(0,101),P(23,95),P(46,104))
        ]))
        closedLips.addChild(quadNode(stone, 2.8, quads: [
            (P(-46,104),P(0,115),P(46,104))
        ]))
        art.addChild(closedLips)

        // ---- Mund: offener Schlund (zentriert um die Mund-Mitte, vertikal skalierbar) ----
        openMaw = SKNode()
        openMaw.position = CGPoint(x: 0, y: mouthLocalY)
        // Rachen (dunkel gefüllt) – Form zentriert um (0,0)
        let throat = SKShapeNode(path: mawPath())
        throat.fillColor = throatCol
        throat.strokeColor = .clear
        openMaw.addChild(throat)
        // Fänge oben/unten
        openMaw.addChild(fangNode(upper: true))
        openMaw.addChild(fangNode(upper: false))
        // gelbe Mund-Umrandung
        let mawOutline = SKShapeNode(path: mawPath())
        mawOutline.fillColor = .clear
        mawOutline.strokeColor = mouthYellow
        mawOutline.lineWidth = 2.6
        mawOutline.lineJoin = .round
        mawOutline.name = "yellow"
        openMaw.addChild(mawOutline)
        art.addChild(openMaw)
    }

    // MARK: - Pfad-Helfer

    private func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    private func silhouettePath() -> CGPath {
        let p = CGMutablePath()
        p.move(to: P(0,-185))
        p.addCurve(to: P(112,-122), control1: P(60,-184), control2: P(100,-160))
        p.addCurve(to: P(124,-50),  control1: P(120,-96), control2: P(116,-74))
        p.addCurve(to: P(104,34),   control1: P(128,-20), control2: P(120,8))
        p.addCurve(to: P(120,150),  control1: P(134,58),  control2: P(150,110))
        p.addCurve(to: P(96,196),   control1: P(132,168), control2: P(120,190))
        p.addCurve(to: P(24,210),   control1: P(74,210),  control2: P(44,206))
        p.addLine(to: P(0,214))
        p.addLine(to: P(-24,210))
        p.addCurve(to: P(-96,196),  control1: P(-44,206), control2: P(-74,210))
        p.addCurve(to: P(-120,150), control1: P(-120,190),control2: P(-132,168))
        p.addCurve(to: P(-104,34),  control1: P(-150,110),control2: P(-134,58))
        p.addCurve(to: P(-124,-50), control1: P(-120,8),  control2: P(-128,-20))
        p.addCurve(to: P(-112,-122),control1: P(-116,-74),control2: P(-120,-96))
        p.addCurve(to: P(0,-185),   control1: P(-100,-160),control2: P(-60,-184))
        p.closeSubpath()
        return p
    }

    private func nosePath() -> CGPath {
        let p = CGMutablePath()
        p.move(to: P(0,-30))
        p.addLine(to: P(-9,2))
        p.addCurve(to: P(-9,36), control1: P(-15,18), control2: P(-19,30))
        p.addCurve(to: P(9,36),  control1: P(-2,40),  control2: P(2,40))
        p.addCurve(to: P(9,2),   control1: P(19,30),  control2: P(15,18))
        p.closeSubpath()
        return p
    }

    /// Schlund-Form, zentriert um (0,0) (wird über `openMaw.position` an die Mund-Mitte gesetzt).
    private func mawPath() -> CGPath {
        let p = CGMutablePath()
        p.move(to: P(-54,-30))
        p.addQuadCurve(to: P(54,-30), control: P(0,-42))
        p.addLine(to: P(46,40))
        p.addQuadCurve(to: P(-46,40), control: P(0,56))
        p.closeSubpath()
        return p
    }

    private func fangNode(upper: Bool) -> SKShapeNode {
        let p = CGMutablePath()
        if upper {
            // unregelmäßige Fänge von der Oberkante (y ~ -28) nach unten
            for t in [(-43,-30,-32,-30,-37,-11), (-23,-30,-14,-30,-18,-15),
                      (14,-30,23,-30,18,-12), (31,-30,42,-30,36,-10)] {
                p.move(to: P(CGFloat(t.0), CGFloat(t.1)))
                p.addLine(to: P(CGFloat(t.2), CGFloat(t.3)))
                p.addLine(to: P(CGFloat(t.4), CGFloat(t.5)))
                p.closeSubpath()
            }
        } else {
            for t in [(-30,40,-19,40,-25,30), (-2,40,9,40,3,28), (24,40,34,40,28,31)] {
                p.move(to: P(CGFloat(t.0), CGFloat(t.1)))
                p.addLine(to: P(CGFloat(t.2), CGFloat(t.3)))
                p.addLine(to: P(CGFloat(t.4), CGFloat(t.5)))
                p.closeSubpath()
            }
        }
        let node = SKShapeNode(path: p)
        node.fillColor = fangCol
        node.strokeColor = carve
        node.lineWidth = 0.7
        return node
    }

    private func socketNode(center: CGPoint, mirror: Bool) -> SKShapeNode {
        // Mandelförmige Augenhöhle um `center`.
        let s: CGFloat = mirror ? -1 : 1
        let p = CGMutablePath()
        p.move(to: P(center.x + s * -20, center.y))
        p.addQuadCurve(to: P(center.x + s * 20, center.y), control: P(center.x, center.y - 14))
        p.addQuadCurve(to: P(center.x + s * -20, center.y), control: P(center.x + s * 2, center.y + 14))
        p.closeSubpath()
        let node = SKShapeNode(path: p)
        node.fillColor = SKColor(red: 0.04, green: 0.06, blue: 0.05, alpha: 1.0)
        node.strokeColor = stone
        node.lineWidth = 2
        return node
    }

    private func circleNode(_ color: SKColor, filled: Bool, center: CGPoint, r: CGFloat) -> SKShapeNode {
        let node = SKShapeNode(circleOfRadius: r)
        node.position = center
        if filled {
            node.fillColor = color
            node.strokeColor = .clear
        } else {
            node.fillColor = .clear
            node.strokeColor = color
            node.lineWidth = 2
        }
        return node
    }

    /// Baut einen SKShapeNode aus mehreren einzelnen Liniensegmenten.
    private func strokeNode(_ color: SKColor, _ width: CGFloat, cap: CGLineCap = .butt,
                            segments: [[CGPoint]]) -> SKShapeNode {
        let p = CGMutablePath()
        for seg in segments {
            guard let first = seg.first else { continue }
            p.move(to: first)
            for pt in seg.dropFirst() { p.addLine(to: pt) }
        }
        let node = SKShapeNode(path: p)
        node.fillColor = .clear
        node.strokeColor = color
        node.lineWidth = width
        node.lineCap = cap
        node.lineJoin = .round
        return node
    }

    /// Baut einen SKShapeNode aus mehreren quadratischen Kurven (Start, Kontrolle, Ende).
    private func quadNode(_ color: SKColor, _ width: CGFloat, cap: CGLineCap = .butt,
                          quads: [(CGPoint, CGPoint, CGPoint)]) -> SKShapeNode {
        let p = CGMutablePath()
        for q in quads {
            p.move(to: q.0)
            p.addQuadCurve(to: q.2, control: q.1)
        }
        let node = SKShapeNode(path: p)
        node.fillColor = .clear
        node.strokeColor = color
        node.lineWidth = width
        node.lineCap = cap
        node.lineJoin = .round
        return node
    }

    /// Variante für die Oberlippe: zwei aneinandergehängte Bögen (Start, c1, mitte, c2, ende).
    private func quadNode(_ color: SKColor, _ width: CGFloat,
                          quadsCubicAsTwo arcs: [(CGPoint, CGPoint, CGPoint, CGPoint, CGPoint)]) -> SKShapeNode {
        let p = CGMutablePath()
        for a in arcs {
            p.move(to: a.0)
            p.addQuadCurve(to: a.2, control: a.1)
            p.addQuadCurve(to: a.4, control: a.3)
        }
        let node = SKShapeNode(path: p)
        node.fillColor = .clear
        node.strokeColor = color
        node.lineWidth = width
        node.lineJoin = .round
        return node
    }
}
