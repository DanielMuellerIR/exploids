import SpriteKit

// Gemeinsame Vektor-/Bewegungs-Helfer für die Entity-Klassen.
//
// Vorher waren `distance`/`moveToward` in FloatingHead und SpaceCat identisch dupliziert
// und `wrapAround` dreifach (Ship/PowerUp/Asteroid). Hier zentral, mit EXAKT denselben
// Rechenoperationen wie die Originale — das Replay-System ist bit-exakt deterministisch,
// eine andere Formel (z.B. `sqrt(dx*dx+dy*dy)` statt `hypot`) würde alte Aufnahmen driften
// lassen. Deshalb: beim Anfassen dieser Helfer nie die Float-Operationen umstellen.

extension CGPoint {
    /// Euklidischer Abstand zu einem anderen Punkt (`hypot`-Form, wie in den Bossen).
    func distance(to other: CGPoint) -> CGFloat {
        return hypot(x - other.x, y - other.y)
    }
}

extension SKNode {
    /// Bewegt die Node mit fester Geschwindigkeit auf ein Ziel zu; ist das Ziel näher als
    /// ein Schritt, wird es exakt erreicht (kein Überschießen). Aus FloatingHead/SpaceCat
    /// zusammengeführt (dort waren die Implementierungen zeichengleich).
    func moveToward(_ target: CGPoint, speed: CGFloat, dt: TimeInterval) {
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

    /// Klappt die Position am Bildschirmrand auf die gegenüberliegende Seite um
    /// (Torus-Wrap um das zentrierte Spielfeld). Aus Ship/PowerUp/Asteroid zusammengeführt.
    func wrapPositionAround(screenSize: CGSize) {
        let halfWidth = screenSize.width / 2
        let halfHeight = screenSize.height / 2

        if position.x < -halfWidth {
            position.x += screenSize.width
        } else if position.x > halfWidth {
            position.x -= screenSize.width
        }

        if position.y < -halfHeight {
            position.y += screenSize.height
        } else if position.y > halfHeight {
            position.y -= screenSize.height
        }
    }
}
