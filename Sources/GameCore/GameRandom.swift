import Foundation

/// Geseedeter, voll spezifizierter Pseudo-Zufallsgenerator für deterministisches Replay.
///
/// Hintergrund: Swifts eingebauter `SystemRandomNumberGenerator` zieht aus einer globalen,
/// nicht reproduzierbaren Quelle. Für ein Replay-System brauchen wir das Gegenteil — bei
/// gleichem Startwert (`seed`) muss IMMER exakt dieselbe Zahlenfolge herauskommen. Nur so
/// lässt sich ein Spieldurchlauf später bit-genau nachspielen.
///
/// Implementiert ist **SplitMix64**: ein winziger, schneller Generator, dessen Algorithmus
/// vollständig festgeschrieben ist (keine Abhängigkeit von Plattform, Compiler-Version oder
/// globalem Zustand). Die magischen Konstanten stammen aus der Referenz-Definition von
/// SplitMix64 (Steele/Lea/Flood) — sie dürfen nicht verändert werden, sonst ändert sich die
/// Sequenz.
///
/// Weil `GameRandom` das Standard-Protokoll `RandomNumberGenerator` erfüllt, funktionieren alle
/// vorhandenen Schreibweisen unverändert weiter, sobald man den Generator durchreicht — z. B.
/// `Int.random(in: 1...6, using: &rng)` oder `array.randomElement(using: &rng)`.
public struct GameRandom: RandomNumberGenerator {

    /// Der interne Zustand. Bei jedem `next()` wird er um eine feste Konstante weitergedreht
    /// und anschließend gut durchmischt. Aus diesem Zustand ergibt sich die nächste Zahl.
    private var state: UInt64

    /// Erzeugt einen Generator aus einem Startwert. Gleicher `seed` ⇒ gleiche Zahlenfolge.
    public init(seed: UInt64) {
        self.state = seed
    }

    /// Zieht einen frischen Seed aus dem System-RNG. Nur für nicht-deterministische Pfade gedacht
    /// (z. B. Convenience-Initializer in Tests/Editor-Vorschauen, die keinen reproduzierbaren Lauf
    /// brauchen). Im echten Spiel wird der Seed EINMAL beim Spielstart gewürfelt und überall geteilt.
    public static func systemSeed() -> UInt64 {
        var sys = SystemRandomNumberGenerator()
        return sys.next()
    }

    /// Liefert die nächste 64-Bit-Zufallszahl (Kern des `RandomNumberGenerator`-Protokolls).
    ///
    /// Ablauf von SplitMix64:
    /// 1. Den Zustand um die "goldene" Schrittkonstante erhöhen (Überlauf ist gewollt — daher
    ///    `&+`, die überlauf-sichere Addition).
    /// 2. Den so erhöhten Wert über zwei XOR-Shift-/Multiplikations-Runden gründlich verwürfeln,
    ///    damit aufeinanderfolgende Ausgaben keine erkennbare Struktur haben.
    public mutating func next() -> UInt64 {
        // Schritt 1: Zustand deterministisch weiterdrehen.
        state = state &+ 0x9E37_79B9_7F4A_7C15

        // Schritt 2: Den Zustand zu einer gut gemischten Ausgabe verarbeiten (Finalizer).
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
