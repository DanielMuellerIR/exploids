import SpriteKit

extension GameScene {
    var shipStartPosition: CGPoint {
        gameMode == .eventHorizon ? CGPoint(x: 0, y: -size.height * 0.32) : .zero
    }

    var eventHorizonScreenBounds: CGRect {
        CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
    }

    /// Nur die Komponente senkrecht zur Wand wechselt das Vorzeichen. Der bereits zurückgelegte
    /// Weg über die Wand wird gespiegelt; Drehung und tangentiale Geschwindigkeit bleiben erhalten.
    func reflectEventHorizonShip() {
        let bounds = eventHorizonBounds(ship.getWorldVertices(), padding: ship.lineWidth / 2)
        let screen = eventHorizonScreenBounds
        let minX = ship.position.x + screen.minX - bounds.minX
        let maxX = ship.position.x + screen.maxX - bounds.maxX
        let minY = ship.position.y + screen.minY - bounds.minY
        let maxY = ship.position.y + screen.maxY - bounds.maxY
        reflectCoordinate(&ship.position.x, velocity: &ship.velocity.x, lower: minX, upper: maxX)
        reflectCoordinate(&ship.position.y, velocity: &ship.velocity.y, lower: minY, upper: maxY)
    }

    private func reflectCoordinate(_ coordinate: inout CGFloat, velocity: inout CGFloat,
                                   lower: CGFloat, upper: CGFloat) {
        guard upper > lower else { coordinate = (lower + upper) / 2; velocity = 0; return }
        guard coordinate < lower || coordinate > upper else { return }
        // Beim Drehen kann die Kontur eine Wand berühren, obwohl das Schiff schon wegfliegt.
        // Dann nur ins Feld schieben; die einwärts gerichtete Bewegung nicht zurückwerfen.
        if coordinate < lower && velocity >= 0 { coordinate = lower; return }
        if coordinate > upper && velocity <= 0 { coordinate = upper; return }
        let span = upper - lower
        var phase = (coordinate - lower).truncatingRemainder(dividingBy: 2 * span)
        if phase < 0 { phase += 2 * span }
        coordinate = phase <= span ? lower + phase : upper - (phase - span)
        if phase > span { velocity = -velocity }
    }

    /// Einfliegende Gegner dürfen zuerst sichtbar werden. Erst danach gilt das vollständige
    /// Verlassen als endgültiges Ende; Projektile und Beute entstehen dagegen im Spielfeld.
    /// Die Grenzen stammen aus fester Geometrie, niemals aus SKActions oder dem Renderzeitpunkt.
    func removeExitedEventHorizonEntities() {
        activeAsteroids.removeAll { asteroid in
            let bounds = eventHorizonBounds(asteroid.getWorldBoundaryVertices(), padding: asteroid.lineWidth / 2)
            if bounds.intersects(eventHorizonScreenBounds) { asteroid.hasEnteredScreen = true }
            return removeIfExited(asteroid, bounds: bounds, canEnter: !asteroid.hasEnteredScreen)
        }
        activeLasers.removeAll { laser in
            let segment = laser.getWorldSegment()
            return removeIfExited(laser, bounds: eventHorizonBounds([segment.0, segment.1], padding: laser.lineWidth / 2))
        }
        activeUFOs.removeAll { ufo in
            removeIfExited(ufo, bounds: eventHorizonBounds(ufo.getWorldVertices(), padding: ufo.lineWidth / 2), canEnter: true)
        }
        activePowerUps.removeAll { powerUp in
            let local = powerUp.path?.boundingBoxOfPath ?? .zero
            return removeIfExited(powerUp, bounds: eventHorizonWorldBounds(local, node: powerUp, padding: powerUp.lineWidth / 2))
        }
        options.removeAll { drone in
            removeIfExited(drone, bounds: eventHorizonWorldBounds(drone.path?.boundingBoxOfPath ?? .zero,
                                                                 node: drone, padding: drone.lineWidth / 2))
        }
        activeCats.removeAll { cat in
            removeIfExited(cat, bounds: eventHorizonWorldBounds(cat.boundaryLocalBounds, node: cat), canEnter: true)
        }
        if let head = activeHead,
           removeIfExited(head, bounds: eventHorizonWorldBounds(head.boundaryLocalBounds, node: head), canEnter: true) {
            activeHead = nil
            SoundManager.shared.stopAllHeadSounds()
        }
        let liveNodes: [SKNode] = activeAsteroids + activeLasers + activeUFOs + activePowerUps + activeCats
            + (activeHead.map { [$0] } ?? [])
        eventHorizonEnteredNodes.formIntersection(Set(liveNodes.map(ObjectIdentifier.init)))
    }

    private func removeIfExited(_ node: SKNode, bounds: CGRect, canEnter: Bool = false) -> Bool {
        let identifier = ObjectIdentifier(node)
        if bounds.intersects(eventHorizonScreenBounds) {
            eventHorizonEnteredNodes.insert(identifier)
            return false
        }
        if canEnter && !eventHorizonEnteredNodes.contains(identifier) { return false }
        node.removeFromParent()
        return true
    }

    func eventHorizonBounds(_ points: [CGPoint], padding: CGFloat = 0) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return CGRect(x: minX - padding, y: minY - padding,
                      width: maxX - minX + 2 * padding, height: maxY - minY + 2 * padding)
    }

    private func eventHorizonWorldBounds(_ local: CGRect, node: SKNode, padding: CGFloat = 0) -> CGRect {
        let c = cos(node.zRotation), s = sin(node.zRotation)
        let corners = [CGPoint(x: local.minX, y: local.minY), CGPoint(x: local.maxX, y: local.minY),
                       CGPoint(x: local.maxX, y: local.maxY), CGPoint(x: local.minX, y: local.maxY)]
        let points = corners.map { point in
            CGPoint(x: node.position.x + point.x * node.xScale * c - point.y * node.yScale * s,
                    y: node.position.y + point.x * node.xScale * s + point.y * node.yScale * c)
        }
        return eventHorizonBounds(points, padding: padding)
    }
}
