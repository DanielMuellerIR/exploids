// GameScene+MadRotation.swift — Feld-Rotation des Mad-Meteoroids-Modus (Scheduler,
// Plattenscratch, Rotations-Anwendung, kreisförmiges Wrapping) samt Tuning-Enum MadRotation.
// Reiner Datei-Split aus GameScene.swift — kein Verhalten geändert.

import SpriteKit

/// Zentrale Tuning-Konstanten für die Feld-Rotation im Mad-Meteoroids-Modus.
/// Hier justieren, um Drehzahl, Wechsel-Frequenz und „Plattenscratch" anzupassen.
private enum MadRotation {
    /// Drehgeschwindigkeit in Grad/Sekunde auf Level 1.
    static let minSpeedDegPerSec: CGFloat = 6.0
    /// Drehgeschwindigkeit in Grad/Sekunde ab Level 10 (Deckel).
    static let maxSpeedDegPerSec: CGFloat = 30.0
    /// Anzahl Richtungswechsel pro Level für Level 1..9 (Index 0 == Level 1).
    /// Level 1–3: konstante Richtung; danach 2-2-2-3-3-4.
    static let changesPerLevel: [Int] = [0, 0, 0, 2, 2, 2, 3, 3, 4]
    /// Ab Level 10: Abstand zwischen Richtungswechseln in Sekunden.
    static let highLevelChangeInterval: TimeInterval = 10.0
    /// Ab Level 10: Wahrscheinlichkeit, dass ein Wechsel stattdessen ein „Plattenscratch" wird.
    static let scratchChance: Double = 0.15
    /// Dauer eines Plattenscratch (kurzes hartes Vor-Zurück) in Sekunden.
    static let scratchDuration: TimeInterval = 0.4
    /// Geschwindigkeits-Faktor während des Scratch (relativ zur normalen Level-Drehzahl).
    static let scratchSpeedMultiplier: CGFloat = 3.0
}

extension GameScene {
    // MARK: - Mad Meteoroids Field Rotation

    /// Dreht einen Punkt um den Ursprung (Bildschirmmitte) um den Winkel `a` (Radiant).
    func rotatedAroundOrigin(_ p: CGPoint, by a: CGFloat) -> CGPoint {
        if a == 0 { return p }
        let c = cos(a)
        let s = sin(a)
        return CGPoint(x: p.x * c - p.y * s, y: p.x * s + p.y * c)
    }

    /// Radius des kreisförmigen Spielfelds im Mad-Modus. Objekte jenseits dieses Radius werden auf
    /// die diametral gegenüberliegende Seite umgesetzt (rotations-invariantes Wrapping).
    func madFieldRadius() -> CGFloat {
        let halfWidth = (size.width > 100 ? size.width : 1024.0) / 2
        let halfHeight = (size.height > 100 ? size.height : 768.0) / 2
        return sqrt(halfWidth * halfWidth + halfHeight * halfHeight) + 100.0
    }

    /// Setzt einen Punkt, der den Feldradius verlassen hat, auf die gegenüberliegende Seite knapp
    /// innerhalb des Radius (kreisförmiges Wrapping). Punkte innerhalb bleiben unverändert.
    func circularWrapped(_ p: CGPoint, radius r: CGFloat) -> CGPoint {
        let d = hypot(p.x, p.y)
        if d > r {
            let scale = (r * 0.98) / d
            return CGPoint(x: -p.x * scale, y: -p.y * scale)
        }
        return p
    }

    /// Drehgeschwindigkeit (Radiant/Sekunde) für ein Level, linear interpoliert zwischen dem
    /// Level-1- und dem Level-10-Wert, ab Level 10 gedeckelt.
    private func fieldSpeedRadPerSec(forLevel level: Int) -> CGFloat {
        let clamped = max(1, min(level, 10))
        let t = CGFloat(clamped - 1) / 9.0
        let deg = MadRotation.minSpeedDegPerSec + t * (MadRotation.maxSpeedDegPerSec - MadRotation.minSpeedDegPerSec)
        return deg * .pi / 180.0
    }

    /// Initialisiert den Rotations-Scheduler fürs aktuelle Level: Drehrichtung wählen und die
    /// Richtungswechsel zeitlich planen. Im Ancient-Modus wird die Rotation deaktiviert.
    func configureFieldRotationForLevel(currentTime: TimeInterval) {
        scratchActive = false
        scratchElapsed = 0.0

        guard gameMode == .madMeteoroids else {
            fieldAngularVelocity = 0.0
            nextDirectionChangeTime = .greatestFiniteMagnitude
            return
        }

        let speed = fieldSpeedRadPerSec(forLevel: currentLevel)
        fieldRotationDirection = Bool.random(using: &rng) ? 1.0 : -1.0
        fieldAngularVelocity = fieldRotationDirection * speed

        if currentLevel >= 10 {
            directionChangesRemaining = Int.max
            directionChangeInterval = MadRotation.highLevelChangeInterval
            nextDirectionChangeTime = currentTime + directionChangeInterval
        } else {
            let idx = currentLevel - 1
            let changes = (idx >= 0 && idx < MadRotation.changesPerLevel.count) ? MadRotation.changesPerLevel[idx] : 0
            directionChangesRemaining = changes
            if changes > 0 {
                // Wechsel gleichmäßig über die 60-Sekunden-Leveldauer verteilen.
                directionChangeInterval = 60.0 / Double(changes + 1)
                nextDirectionChangeTime = currentTime + directionChangeInterval
            } else {
                directionChangeInterval = 0.0
                nextDirectionChangeTime = .greatestFiniteMagnitude
            }
        }
    }

    /// Schreibt den Rotations-Zustand pro Frame fort: wickelt laufende Plattenscratches ab und
    /// löst fällige Richtungswechsel aus. Aktualisiert `fieldAngularVelocity`.
    func updateFieldRotation(deltaTime: TimeInterval, currentTime: TimeInterval) {
        let speed = fieldSpeedRadPerSec(forLevel: currentLevel)

        // Laufenden Plattenscratch abwickeln: die Drehzahl schwingt kurz vor und wieder zurück.
        if scratchActive {
            scratchElapsed += deltaTime
            let progress = scratchElapsed / MadRotation.scratchDuration
            if progress >= 1.0 {
                scratchActive = false
                fieldAngularVelocity = fieldRotationDirection * speed
            } else {
                let osc = cos(2.0 * .pi * CGFloat(progress)) // +1 -> -1 -> +1 über die Dauer
                fieldAngularVelocity = fieldRotationDirection * speed * MadRotation.scratchSpeedMultiplier * osc
                return
            }
        }

        // Geplanter Richtungswechsel fällig?
        if currentTime >= nextDirectionChangeTime && directionChangesRemaining > 0 {
            if currentLevel >= 10 {
                nextDirectionChangeTime = currentTime + directionChangeInterval
                // Gelegentlich wird aus dem Wechsel ein Plattenscratch statt einer sauberen Umkehr.
                if Double.random(in: 0...1, using: &rng) < MadRotation.scratchChance {
                    scratchActive = true
                    scratchElapsed = 0.0
                    return
                }
            } else {
                directionChangesRemaining -= 1
                nextDirectionChangeTime = (directionChangesRemaining > 0)
                    ? currentTime + directionChangeInterval
                    : .greatestFiniteMagnitude
            }
            fieldRotationDirection *= -1.0
        }

        fieldAngularVelocity = fieldRotationDirection * speed
    }

    /// Wendet die Feld-Rotation dieses Frames auf einen Asteroiden an (Position + Velocity drehen,
    /// Silhouette mitdrehen) und führt das kreisförmige Wrapping mit „erst eintreten"-Gate aus.
    func applyFieldRotation(toAsteroid ast: Asteroid) {
        ast.position = rotatedAroundOrigin(ast.position, by: fieldDeltaThisFrame)
        ast.velocity = rotatedAroundOrigin(ast.velocity, by: fieldDeltaThisFrame)
        ast.zRotation += fieldDeltaThisFrame

        let r = madFieldRadius()
        let d = hypot(ast.position.x, ast.position.y)
        if !ast.hasEnteredScreen {
            // Sichtbaren Bereich erreicht? (Der Bildschirm-Eckradius ist r - 100.)
            if d <= r - 100.0 { ast.hasEnteredScreen = true }
        } else {
            ast.position = circularWrapped(ast.position, radius: r)
        }
    }
}
