import CoreGraphics

/// Eine „Persona" für den Demo-Autopiloten: ein Satz Tuning-Werte, der beschreibt, WIE ein
/// computergesteuerter Pilot das Spiel spielt. Über diese Werte entstehen unterschiedliche
/// Spielstile – vorsichtig ↔ draufgängerisch und gut ↔ schlecht –, ohne dass die eigentliche
/// Autopilot-Logik (in `GameScene`) sich ändern muss.
///
/// Grundverhalten (siehe `GameScene.applyAutopilotInput`): Potenzialfeld-Navigation. Alle
/// Bedrohungen stoßen das Schiff ab, Schützen/Power-ups ziehen es (schwach) an; die Summe ergibt
/// eine Flugrichtung „ins Freie". Das Schiff fliegt kontinuierlich dorthin (bleibt mobil → feindliche
/// Schüsse verfehlen) und feuert dabei nach vorn (räumt den Weg). Die Level sind zeitbasiert
/// (60 s pro Level überleben), es muss also nicht alles abgeräumt werden – Überleben zählt.
public struct AutopilotPersona: Sendable {

    /// Anzeigename (erscheint während der Demo als kleines Overlay).
    public let name: String

    /// Startlevel, mit dem eine Demo dieser Persona beginnt. Bewusst pro Persona gewählt: der
    /// Experte startet niedrig für einen langen Vorzeigelauf, Draufgänger starten hoch (mehr Action).
    public let startLevel: Int

    /// Reichweite (Rand zu Rand, Punkte), ab der eine Bedrohung das Schiff abzustoßen beginnt. Groß =
    /// hält viel Abstand, weicht früh aus (vorsichtig); klein = lässt alles nah heran (riskant).
    public let influence: CGFloat

    /// Reise-Wunschtempo (Punkte/s): so schnell fliegt der Pilot durch die Lücken. Klein = ruhig und
    /// kontrolliert (vorsichtig), groß = schnell und offensiv (draufgängerisch).
    public let cruiseSpeed: CGFloat

    /// Multiplikator für die Angst vor Schwarzen Löchern (Gravity Wells): deren Sog tötet aus der
    /// Ferne, darum werden sie stärker abstoßend gewichtet als andere Objekte.
    public let wellFearMult: CGFloat

    /// Zufälliger Steuerfehler in Radiant, der pro Schritt auf die Wunschrichtung addiert wird.
    /// 0 = perfekt; große Werte = der Pilot „zittert" und fliegt/zielt ungenau (wirkt unbeholfener).
    public let aimJitter: CGFloat

    /// Totzone der Drehsteuerung in Radiant: liegt der Kursfehler darunter, wird nicht gedreht.
    /// Größer = träges, grobes Ausrichten.
    public let deadzone: CGFloat

    public init(name: String, startLevel: Int, influence: CGFloat, cruiseSpeed: CGFloat,
                wellFearMult: CGFloat, aimJitter: CGFloat, deadzone: CGFloat) {
        self.name = name
        self.startLevel = startLevel
        self.influence = influence
        self.cruiseSpeed = cruiseSpeed
        self.wellFearMult = wellFearMult
        self.aimJitter = aimJitter
        self.deadzone = deadzone
    }

    // MARK: - Roster (die vier Demo-Personas)

    /// „Ace" – der Experte: sehr vorsichtig und präzise. Hält großen Abstand (weicht früh aus), meidet
    /// Schwarze Löcher stark, fliegt kontrolliert. Soll ab Level 4 die vollen ~10 Minuten (bis in
    /// Level 10) durchhalten – der Vorzeigelauf.
    public static let ace = AutopilotPersona(
        name: "ACE", startLevel: 4, influence: 225, cruiseSpeed: 150,
        wellFearMult: 2.3, aimJitter: 0.03, deadzone: 0.05)

    /// „Cowboy" – draufgängerisch, aber gut: lässt Gegner näher heran (kleinerer Abstand) und fliegt
    /// zügig, steuert aber sauber (wenig Zittern). Startet mittelhoch (Level 6).
    public static let cowboy = AutopilotPersona(
        name: "COWBOY", startLevel: 6, influence: 172, cruiseSpeed: 168,
        wellFearMult: 1.8, aimJitter: 0.08, deadzone: 0.09)

    /// „Rookie" – vorsichtig, aber mittelmäßig: will Abstand halten (großer Reaktionsradius), steuert
    /// aber grob und ungenau (hoher Jitter, große Totzone). Überlebt eine Weile, geht an eigener
    /// Schlampigkeit ein.
    public static let rookie = AutopilotPersona(
        name: "ROOKIE", startLevel: 5, influence: 185, cruiseSpeed: 135,
        wellFearMult: 1.8, aimJitter: 0.26, deadzone: 0.20)

    /// „Kamikaze" – draufgängerisch und riskant: lässt alles nah heran (kleiner Abstand) und heizt
    /// schnell umher. Stirbt am ehesten früh, dafür spektakulär – startet hoch (aber nicht ganz oben).
    public static let kamikaze = AutopilotPersona(
        name: "KAMIKAZE", startLevel: 7, influence: 165, cruiseSpeed: 195,
        wellFearMult: 1.5, aimJitter: 0.18, deadzone: 0.12)

    /// Reihenfolge, in der die Demo reihum durch die Personas schaltet.
    public static let roster: [AutopilotPersona] = [.ace, .cowboy, .rookie, .kamikaze]
}
