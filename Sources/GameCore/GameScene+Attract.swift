// GameScene+Attract.swift — Demo-/Attract-Modus und Autopilot (Potenzialfeld-Navigation,
// Demo-Start/-Abbruch, Attract-Phasen-Scheduler, Demo-Overlay).
// Reiner Datei-Split aus GameScene.swift — kein Verhalten geändert.

import SpriteKit

extension GameScene {
    // MARK: - Autopilot (Demo/Attract-Modus)

    /// Kürzeste Verbindung (dx,dy) von `from` nach `to` unter Berücksichtigung des Kanten-Wraps
    /// (Ancient-Modus: Objekte wrappen bei ±size/2). Entscheidend für den Autopiloten – sonst
    /// erscheint ein über die Naht heranfliegender Asteroid fälschlich „am anderen Ende" und weit weg.
    private func wrappedDelta(from: CGPoint, to: CGPoint) -> CGPoint {
        var dx = to.x - from.x
        var dy = to.y - from.y
        let w = size.width, h = size.height
        if dx > w/2 { dx -= w } else if dx < -w/2 { dx += w }
        if dy > h/2 { dy -= h } else if dy < -h/2 { dy += h }
        return CGPoint(x: dx, y: dy)
    }

    /// Berechnet die Bewegungseingaben des Demo-Autopiloten für DIESEN Simulationsschritt und setzt
    /// sie als „gedrückte Tasten" (`activeKeys`): Schub (Keycode 126) und Drehen links/rechts
    /// (123/124). Gefeuert wird separat über `autoFire` (beim Demo-Start aktiviert).
    ///
    /// Modell: **Potenzialfeld-Navigation.** Jede Bedrohung stößt das Schiff ab (Stärke ∝ Nähe²),
    /// Schützen (UFO/Katze/Boss) und wertvolle Power-ups ziehen es schwach an. Die Summe ergibt eine
    /// Wunsch-Flugrichtung „durch die Lücke ins Freie". Das Schiff dreht dorthin und hält per Schub
    /// sein Reisetempo (`cruiseSpeed`) – es bleibt also ständig in Bewegung (feindliche Snipes auf die
    /// aktuelle Position verfehlen) und feuert nach vorn (räumt den Weg). Weil die Level zeitbasiert
    /// sind (60 s überleben), ist Ausweichen wichtiger als Abräumen.
    ///
    /// Wichtige Feinheit: einen NAHEN großen Asteroiden zerschießt man NICHT gern (die zwei Splitter
    /// fliegen schneller weiter Richtung Schiff) – das Feld lenkt lieber drumherum.
    func applyAutopilotInput(persona: AutopilotPersona) {
        let shipPos = ship.position
        let shipVel = ship.velocity
        let shipR: CGFloat = 12.0   // grober Schiffsradius für die Rand-zu-Rand-Distanz

        // Abstoßungs-Vektor (weg von Gefahren) und der bedrohlichste einzelne Beitrag.
        var fleeX: CGFloat = 0, fleeY: CGFloat = 0
        var maxThreat: CGFloat = 0
        // Vorausschau: gegen die ZUKÜNFTIGE Position bewegter Gefahren ausweichen, nicht die aktuelle.
        let lookahead: CGFloat = 0.50

        // Ziel-Kandidaten: bedrohlichster Asteroid (zum präventiven Wegschießen) und nächster Schütze.
        var aimAngle: CGFloat? = nil; var aimEdge = CGFloat.greatestFiniteMagnitude
        var shooterRel: CGPoint? = nil; var shooterDist = CGFloat.greatestFiniteMagnitude

        // Eine Gefahr einrechnen: abstoßen (Stärke ∝ Nähe² zur vorausgeschauten Position) und – falls
        // beschießbar – als möglichen Zielkandidaten (nach Rand-Abstand JETZT) merken.
        func repel(pos: CGPoint, vel: CGPoint, radius: CGFloat, weight: CGFloat, aimable: Bool) {
            // Abstoßung gegen die vorausgeschaute Position (fängt schnelle Objekte rechtzeitig ab).
            let futurePos = CGPoint(x: pos.x + vel.x * lookahead, y: pos.y + vel.y * lookahead)
            let fRel = wrappedDelta(from: shipPos, to: futurePos)
            let fCenter = sqrt(fRel.x*fRel.x + fRel.y*fRel.y)
            if fCenter > 0.0001 {
                let fEdge = fCenter - radius - shipR
                let range = persona.influence
                if fEdge < range {
                    let proximity = max(0, (range - fEdge) / range)   // 0 (fern) .. 1 (berührt sich)
                    let strength = proximity * proximity * weight
                    fleeX -= fRel.x / fCenter * strength
                    fleeY -= fRel.y / fCenter * strength
                    if strength > maxThreat { maxThreat = strength }
                }
            }
            // Zielauswahl nach aktuellem Rand-Abstand (das Nächste zuerst wegschießen), mit Vorhalt.
            guard aimable else { return }
            let rel = wrappedDelta(from: shipPos, to: pos)
            let d = sqrt(rel.x*rel.x + rel.y*rel.y)
            let edge = d - radius - shipR
            if edge < aimEdge {
                aimEdge = edge
                let t = d / 600.0
                aimAngle = atan2(rel.y + vel.y * t, rel.x + vel.x * t)
            }
        }

        for a in activeAsteroids where a.hasEnteredScreen {
            repel(pos: a.position, vel: a.velocity, radius: a.sizeClass.rawValue, weight: 1.0, aimable: true)
        }
        for u in activeUFOs {
            repel(pos: u.position, vel: u.velocity, radius: 16, weight: 1.1, aimable: true)
            let rel = wrappedDelta(from: shipPos, to: u.position)
            let d = sqrt(rel.x*rel.x + rel.y*rel.y)
            if d < shooterDist { shooterDist = d; shooterRel = rel }
        }
        for c in activeCats {
            repel(pos: c.position, vel: .zero, radius: c.collisionRadius, weight: 1.2, aimable: true)
            let rel = wrappedDelta(from: shipPos, to: c.position)
            let d = sqrt(rel.x*rel.x + rel.y*rel.y)
            if d < shooterDist { shooterDist = d; shooterRel = rel }
        }
        if let head = activeHead {
            repel(pos: head.position, vel: .zero, radius: head.collisionRadius, weight: 1.5, aimable: true)
        }
        // Feindliche Schüsse (UFO- und Katzenlaser) sind schnell und tödlich – stark abstoßen, nicht anpeilen.
        for l in activeLasers where l.type == .enemy || l.type == .catEye {
            repel(pos: l.position, vel: l.velocity, radius: 4, weight: 1.7, aimable: false)
        }
        // Schwarze Löcher: distanzbasiert aus dem Sog-Einflussradius abstoßen (nähern sich nicht selbst).
        for well in activeGravityWells {
            let rel = wrappedDelta(from: shipPos, to: well.position)
            let center = sqrt(rel.x*rel.x + rel.y*rel.y)
            let range = well.influenceRadius
            guard center > 0.0001, center < range else { continue }
            let nx = rel.x / center, ny = rel.y / center
            let proximity = (range - center) / range
            let strength = proximity * proximity * 3.5 * persona.wellFearMult
            fleeX -= nx * strength; fleeY -= ny * strength
            if strength > maxThreat { maxThreat = strength }
        }

        // Power-up-Ziel (Schild/Extra-Leben zuerst) für die sichere Phase merken.
        var seekRel: CGPoint? = nil; var seekScore = CGFloat.greatestFiniteMagnitude
        for p in activePowerUps {
            let rel = wrappedDelta(from: shipPos, to: p.position)
            let d = sqrt(rel.x*rel.x + rel.y*rel.y)
            guard d < 340 else { continue }
            let value: CGFloat
            switch p.type {
            case .extraLife: value = 0.30
            case .shield:    value = 0.40
            case .bomb:      value = 0.55
            case .compress:  value = 0.65   // schrumpft das Schiff → kleineres Ziel (defensiv gut)
            default:         value = 0.85
            }
            let score = d * value
            if score < seekScore { seekScore = score; seekRel = rel }
        }

        // --- Kurs + Schubwunsch: Ausweichen hat Vorrang, sonst zielen/sammeln, dabei mobil bleiben ---
        let fleeMag = sqrt(fleeX*fleeX + fleeY*fleeY)
        let dodging = fleeMag > 0.20                       // spürbare Bedrohung → aktiv ausweichen
        let speed = sqrt(shipVel.x*shipVel.x + shipVel.y*shipVel.y)

        let desiredAngle: CGFloat
        var wantThrust = false
        var cruise = persona.cruiseSpeed
        if dodging {
            desiredAngle = atan2(fleeY, fleeX)             // weg von der (vorausgeschauten) Gefahr
            wantThrust = true
        } else if let rel = seekRel {
            desiredAngle = atan2(rel.y, rel.x)             // Power-up anfliegen (mobil, sammelt Schilde)
            wantThrust = true
            cruise = min(cruise, 150)
        } else if let rel = shooterRel {
            desiredAngle = atan2(rel.y, rel.x)             // Schütze: draufhalten und langsam anfliegen
            wantThrust = speed < 70                        // (leichte Drift → Snipes verfehlen)
            cruise = 90
        } else if let aim = aimAngle {
            desiredAngle = aim                             // ruhig den nächsten Asteroiden anpeilen
            wantThrust = false
        } else {
            desiredAngle = ship.zRotation
            wantThrust = false
        }

        // --- In Tasten übersetzen ---
        // Persona-Zittern (Skill-Fehler) auf den Kursfehler addieren; Fehler auf [-π, π] normieren.
        let jitter = persona.aimJitter > 0
            ? CGFloat.random(in: -persona.aimJitter...persona.aimJitter, using: &autopilotRng)
            : 0
        var err = desiredAngle - ship.zRotation + jitter
        while err > .pi { err -= 2 * .pi }
        while err < -.pi { err += 2 * .pi }

        // Bewegungstasten dieses Schritts frisch setzen (nur die vom Autopiloten genutzten Codes).
        activeKeys.remove(126); activeKeys.remove(13)
        activeKeys.remove(123); activeKeys.remove(0)
        activeKeys.remove(124); activeKeys.remove(2)

        // Drehen: positiver Winkel (gegen Uhrzeiger) ⇒ Linkstaste (123 setzt rotationInput +1).
        if err > persona.deadzone {
            activeKeys.insert(123)
        } else if err < -persona.deadzone {
            activeKeys.insert(124)
        }

        // Schub: solange der Kurs grob passt und das Wunschtempo nicht erreicht ist. Beim Ausweichen
        // großzügiger (auch bei schrägem Kurs schon beschleunigen → schneller aus der Gefahr).
        let alignTol: CGFloat = dodging ? 1.8 : 1.0
        if wantThrust && abs(err) < alignTol && speed < cruise {
            activeKeys.insert(126)
        }
    }

    /// Startet die nächste Demo: nächste Persona aus dem Roster (reihum), deren passendes Startlevel,
    /// klassischer Modus, frisches Spiel mit aktivem Autopilot. Demo-Läufe werden nicht aufgezeichnet.
    func startDemo() {
        let persona = AutopilotPersona.roster[nextPersonaIndex % AutopilotPersona.roster.count]
        nextPersonaIndex = (nextPersonaIndex + 1) % AutopilotPersona.roster.count
        autopilotPersona = persona
        // Autopilot-Jitter reproduzierbar seeden (Persona-Index + Startlevel), getrennt vom Gameplay-RNG.
        autopilotRng = GameRandom(seed: 0xA0710_5EED
                                  &+ UInt64(nextPersonaIndex) &* 0x9E37_79B9
                                  &+ UInt64(persona.startLevel))
        selectedMode = .ancientAsteroids     // klassischer Modus: berechenbares, langes Überleben
        selectedStartLevel = persona.startLevel
        autoFire = true                       // Demo feuert durchgehend
        attractPhase = .demoPlaying
        attractTimer = 0
        startNewGame()                        // Fresh-Game-Pfad (kein Recorder, da isDemoActive)
        updateDemoOverlay()
    }

    /// Bricht die laufende Automatik (Demo oder Zwischen-Menü-Phase) ab und kehrt in den ruhigen
    /// Leerlauf am Startbildschirm zurück – der Mensch übernimmt.
    func abortAttractToIdle() {
        autopilotPersona = nil
        attractPhase = .idle
        attractTimer = 0
        // Vom Autopiloten zuletzt gesetzte Bewegungstasten (Drehen/Schub) verwerfen – sonst „erbt"
        // ein danach vom Menschen gestartetes Spiel diese Tasten und das Schiff dreht/schiebt von
        // selbst weiter, bis der Spieler die Richtung einmal selbst drückt und wieder loslässt.
        activeKeys.removeAll()
        transitionTo(.startScreen)
    }

    /// Ob gerade ein Autopilot-Demolauf aktiv ist (für die iOS-Schicht, um im Demo-Modus die
    /// Touch-Controls auszublenden – ein Zuschauer braucht sie nicht).
    public var isDemoRunning: Bool { isDemoActive }

    /// Startet sofort eine Demo aus dem Menü heraus (iOS-DEMO-Button; auf macOS macht das die Taste
    /// „D"). Nur vom Startbildschirm und nur bei aktivem Attract-Modus – sonst passiert nichts.
    public func startDemoFromMenu() {
        guard attractModeEnabled, gameState == .startScreen else { return }
        startDemo()
    }

    /// Treibt die Menü-Phasen des Attract-Kreislaufs über die Echtzeit-Uhr. Die Demo selbst
    /// (`.demoPlaying`) läuft bis zum Game Over; dort wird auf `.demoScores` weitergeschaltet.
    func updateAttract(realDelta: TimeInterval) {
        switch attractPhase {
        case .idle:
            // Nur am Startbildschirm hochzählen; in anderen Menüs (Glossar/Einstellungen/…) ruht der
            // Leerlauf-Timer, damit nicht mitten im Blättern eine Demo losläuft.
            if gameState == .startScreen {
                attractTimer += realDelta
                if attractTimer >= 30.0 { startDemo() }
            } else {
                attractTimer = 0
            }
        case .demoScores:
            attractTimer += realDelta
            if attractTimer >= 10.0 {          // Highscore-Liste 10 s zeigen …
                attractPhase = .demoRestScreen
                attractTimer = 0
                transitionTo(.startScreen)
            }
        case .demoRestScreen:
            attractTimer += realDelta
            if attractTimer >= 15.0 { startDemo() }   // … dann 15 s Startbildschirm, dann nächste Demo.
        case .demoPlaying:
            break   // läuft bis Game Over (weitergeschaltet in triggerGameOver)
        }
    }

    /// Blendet das Demo-Overlay („DEMO — <PERSONA>") ein, solange der Autopilot im laufenden Spiel
    /// steuert, sonst aus.
    func updateDemoOverlay() {
        if let persona = autopilotPersona, gameState == .playing {
            // Text nur bei Änderung neu setzen (spart die String-Allokation im Pro-Frame-Aufruf
            // aus dem Game-Loop, siehe update()).
            // NUR ASCII verwenden: Der Pixel-Font (PressStart2P) enthält keine Sonderzeichen wie
            // „▷" oder Em-Dash „—" – fehlt schon das erste Glyph, rendert SpriteKit das GANZE Label
            // leer (auf iOS so beobachtet). „>" und „-" sind im Font vorhanden.
            let text = "> DEMO - \(persona.name)"
            if demoOverlayLabel.text != text { demoOverlayLabel.text = text }
            demoOverlayLabel.isHidden = false
        } else {
            demoOverlayLabel.isHidden = true
        }
    }
}
