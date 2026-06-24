import SpriteKit
// AppKit wird nur für die macOS-Tastatur-Brücke (NSEvent) gebraucht und existiert auf iOS nicht.
#if canImport(AppKit)
import AppKit
#endif

/// A structure representing a saved high score entry.
public struct HighScore: Codable, Sendable {
    public let initials: String
    public let score: Int
    public let date: Date
    public let deathMessage: String?
    
    public init(initials: String, score: Int, date: Date, deathMessage: String? = nil) {
        self.initials = initials
        self.score = score
        self.date = date
        self.deathMessage = deathMessage
    }
}

/// The state of the gameplay scene.
public enum GameState: Sendable {
    case startScreen
    case playing
    case nameEntry
    case gameOver
    case quitConfirmation
    case glossary
    /// Eigene Highscore-Ansicht (mit Zurück). Wird nur auf iOS angesteuert, wenn die
    /// Highscore-Liste vom Startbildschirm in eine separate Ansicht ausgelagert ist.
    case highScores
    /// Einstellungen (Musik / SFX-Stil / Auto-Feuer). Erreichbar vom Startbildschirm.
    case settings
}

/// Auswählbarer Spielmodus.
public enum GameMode: Sendable {
    /// Klassischer Modus: festes Spielfeld, Objekte wrappen an den Bildschirmkanten.
    case ancientAsteroids
    /// Neuer Modus: das gesamte Spielfeld (Objekte + Sternenfeld) rotiert kontinuierlich um die
    /// Bildschirmmitte, nur das Spieler-Raumschiff bleibt davon unberührt (vgl. Crazy Comets).
    case madMeteoroids
}

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

/// Level-based difficulty and entity spawn weight configuration.
public struct LevelSpawnConfig: Sendable {
    public let level: Int
    public let maxAsteroids: Int
    public let spawnRate: TimeInterval
    public let speedMultiplier: CGFloat
    public let powerUpChance: Double
    public let normalWeight: Int
    public let implodingWeight: Int
    public let wobblingWeight: Int
    public let ufoInterval: TimeInterval?
    public let blackHoleInterval: TimeInterval?
}

/// The main gameplay scene representing the Asteroids arena.
/// Handles ship setup, player inputs (keyboard), lasers, wrapping around edges, and physics updates.
public final class GameScene: SKScene {
    
    public enum DeathCause: Sendable {
        case largeAsteroid
        case mediumAsteroid
        case smallAsteroid
        case wobblingAsteroid
        case ufo
        case ufoLaser
        case gravityWell
        case bossHead
        case spaceCat        // von einer Weltraumkatze gerammt
        case spaceCatLaser   // von den Laseraugen einer Weltraumkatze getroffen
    }
    
    public var lastDeathCause: DeathCause = .largeAsteroid
    private let powerUpNotificationLabel = SKLabelNode(fontNamed: "Courier-Bold")
    
    // Level configurations registry
    public static let levelConfigs: [LevelSpawnConfig] = [
        // Schwierigkeitskurve bewusst flach gehalten: weniger Objekte und langsamerer Anstieg von
        // Tempo/Spawn-Frequenz, damit das mittlere Level (5) sich auch wie Mitte anfühlt.
        LevelSpawnConfig(level: 1, maxAsteroids: 3, spawnRate: 2.8, speedMultiplier: 1.0, powerUpChance: 0.12, normalWeight: 100, implodingWeight: 0, wobblingWeight: 0, ufoInterval: nil, blackHoleInterval: nil),
        LevelSpawnConfig(level: 2, maxAsteroids: 4, spawnRate: 2.4, speedMultiplier: 1.08, powerUpChance: 0.14, normalWeight: 90, implodingWeight: 0, wobblingWeight: 10, ufoInterval: 35.0, blackHoleInterval: nil),
        LevelSpawnConfig(level: 3, maxAsteroids: 4, spawnRate: 2.1, speedMultiplier: 1.16, powerUpChance: 0.16, normalWeight: 85, implodingWeight: 5, wobblingWeight: 10, ufoInterval: 30.0, blackHoleInterval: nil),
        LevelSpawnConfig(level: 4, maxAsteroids: 5, spawnRate: 1.8, speedMultiplier: 1.24, powerUpChance: 0.18, normalWeight: 74, implodingWeight: 9, wobblingWeight: 17, ufoInterval: 25.0, blackHoleInterval: nil),
        LevelSpawnConfig(level: 5, maxAsteroids: 6, spawnRate: 1.5, speedMultiplier: 1.32, powerUpChance: 0.20, normalWeight: 66, implodingWeight: 12, wobblingWeight: 22, ufoInterval: 20.0, blackHoleInterval: 110.0)
    ]
    
    public func configForLevel(_ lvl: Int) -> LevelSpawnConfig {
        if lvl > GameScene.levelConfigs.count {
            let last = GameScene.levelConfigs.last!
            let extraLevels = lvl - 5
            return LevelSpawnConfig(
                level: lvl,
                maxAsteroids: min(13, last.maxAsteroids + extraLevels),
                spawnRate: max(0.6, last.spawnRate - Double(extraLevels) * 0.07),
                speedMultiplier: min(2.6, last.speedMultiplier + CGFloat(extraLevels) * 0.08),
                powerUpChance: min(0.35, last.powerUpChance + Double(extraLevels) * 0.02),
                normalWeight: max(40, last.normalWeight - extraLevels * 4),
                implodingWeight: min(20, last.implodingWeight + extraLevels),
                wobblingWeight: min(40, last.wobblingWeight + extraLevels * 2),
                ufoInterval: max(8.0, (last.ufoInterval ?? 15.0) - Double(extraLevels) * 0.8),
                blackHoleInterval: max(70.0, (last.blackHoleInterval ?? 110.0) - Double(extraLevels) * 1.5)
            )
        }
        return GameScene.levelConfigs[max(1, min(lvl, GameScene.levelConfigs.count)) - 1]
    }
    
    // MARK: - Properties
    
    /// The player's spaceship.
    public private(set) var ship: Ship!
    
    /// Active lasers currently in the scene.
    public private(set) var activeLasers: [Laser] = []
    
    /// Active asteroids currently in the scene.
    public private(set) var activeAsteroids: [Asteroid] = []
    
    /// The current state of the game.
    public private(set) var gameState: GameState = .startScreen
    
    /// Whether the game is in a Game Over state (for test compatibility).
    public var isGameOver: Bool {
        return gameState == .gameOver || gameState == .nameEntry
    }
    
    /// The player's current score.
    public private(set) var score: Int = 0
    
    /// Persistent high scores.
    public private(set) var highScores: [HighScore] = []

    // MARK: - Plattform-Layout-Konfiguration (vom Host gesetzt)
    // Defaults erhalten das bisherige macOS-Verhalten 1:1. Der iOS-Host schaltet sie um.

    /// true = kompaktes, touch-orientiertes Menü-Layout fürs iPhone-Breitformat
    /// (Titel sichtbar positioniert, keyboard-zentrierte Hinweise ausgeblendet).
    /// false (Default) = unverändertes 4:3-Layout (macOS).
    public var isCompactLayout: Bool = false

    /// true (Default) = Highscore-Liste erscheint am Startbildschirm (macOS).
    /// false = Liste ist ausgelagert in die eigene `.highScores`-Ansicht (iOS).
    public var showsHighScoresOnStartScreen: Bool = true

    /// Temporary storage for initials entry.
    private var typedInitials: String = ""

    /// Anzahl der bereits eingegebenen Initialen (0…3). Nur lesend – wird von der iOS-Tastatur
    /// (UIKeyInput.hasText) gebraucht, damit die Löschtaste korrekt arbeitet. macOS nutzt das nicht.
    public var enteredInitialsCount: Int { typedInitials.count }
    
    // Spielmodus-Auswahl
    /// Der aktuell laufende Spielmodus.
    public private(set) var gameMode: GameMode = .ancientAsteroids
    /// Der auf dem Startscreen vorgewählte Modus.
    private var selectedMode: GameMode = .ancientAsteroids

    // Mad-Meteoroids: Rotations-Zustand des Spielfelds (nur im madMeteoroids-Modus aktiv)
    /// Aktuelle Winkelgeschwindigkeit des Feldes in Radiant/Sekunde (Vorzeichen = Drehrichtung).
    private var fieldAngularVelocity: CGFloat = 0.0
    /// In diesem Frame angewandte Drehung in Radiant (von Objekten + Sternen genutzt).
    private var fieldDeltaThisFrame: CGFloat = 0.0
    /// Vorzeichen der aktuellen Drehrichtung (+1 oder -1).
    private var fieldRotationDirection: CGFloat = 1.0
    /// Zeitpunkt des nächsten geplanten Richtungswechsels.
    private var nextDirectionChangeTime: TimeInterval = .greatestFiniteMagnitude
    /// Abstand zwischen Richtungswechseln im aktuellen Level (Sekunden).
    private var directionChangeInterval: TimeInterval = 0.0
    /// Verbleibende Richtungswechsel im aktuellen Level (Int.max ab Level 10).
    private var directionChangesRemaining: Int = 0
    /// Ob gerade ein Plattenscratch (Vor-Zurück-Ruck) läuft.
    private var scratchActive: Bool = false
    /// Bereits verstrichene Zeit im aktuellen Scratch.
    private var scratchElapsed: TimeInterval = 0.0
    /// Flag: Beim nächsten Frame den Rotations-Scheduler fürs aktuelle Level neu aufsetzen
    /// (gesetzt aus `transitionTo`/Level-Aufstieg, da dort die absolute Spielzeit fehlt).
    private var fieldRotationPending: Bool = false

    // Level and countdown progression state
    public private(set) var currentLevel: Int = 1
    public private(set) var maxLevelReached: Int = 1
    public private(set) var selectedStartLevel: Int = 1
    public private(set) var levelTimeRemaining: TimeInterval = 120.0
    public private(set) var isLevelClearing: Bool = false
    private var levelClearEndTime: TimeInterval = 0.0
    
    // MARK: - Determinismus / Replay (Phase 1.2)

    /// Geseedeter Zufallsgenerator für die gesamte Spiel-Logik. Wird bei jedem frischen Spielstart
    /// neu aus `currentSeed` aufgesetzt. Alle gameplay-relevanten `.random`-Aufrufe ziehen in
    /// Phase 1.3 nach und nach hierüber (`Int.random(in:using:&rng)`), damit ein Lauf bei gleichem
    /// Seed exakt reproduzierbar ist.
    var rng: GameRandom = GameRandom(seed: 0)

    /// Der Seed des aktuell laufenden Spiels. Nach `startNewGame` gesetzt und auslesbar (u. a. für
    /// die spätere Replay-Aufnahme und für Tests).
    public private(set) var currentSeed: UInt64 = 0

    /// Optional injizierter Seed für den nächsten frischen Spielstart (Replay/Test). Ist er gesetzt,
    /// wird er beim nächsten Fresh-Game übernommen und danach geleert; sonst würfelt das Spiel einen
    /// neuen Seed aus dem System-RNG (einmalig, der einzige nicht-deterministische Punkt).
    private var pendingSeed: UInt64?

    // Difficulty and Time state
    public private(set) var playTime: TimeInterval = 0.0
    
    /// Dynamic difficulty factor from 1.0 up to 2.5 scaling over 10 minutes.
    public var difficultyFactor: CGFloat {
        let maxDifficultyTime: TimeInterval = 600.0 // 10 minutes
        let progress = min(1.0, playTime / maxDifficultyTime)
        return 1.0 + 1.5 * CGFloat(progress)
    }
    
    /// Spawn cooldown settings
    public var isSpawningEnabled: Bool = true
    private var lastSpawnTime: TimeInterval = 0.0
    
    private func currentConfig() -> LevelSpawnConfig {
        let base: LevelSpawnConfig
        if currentLevel >= 10 {
            let effectiveLevel = 10 + Int(playTime / 60.0)
            base = configForLevel(effectiveLevel)
        } else {
            base = configForLevel(currentLevel)
        }

        // Der Mad-Modus ist durch die rotierende Spielfläche ohnehin anspruchsvoller. Damit er
        // fair bleibt: weniger Objekte gleichzeitig und mehr Power-Ups. (Tuning hier anpassen.)
        guard gameMode == .madMeteoroids else { return base }
        let madAsteroidFactor = 0.6      // ~40 % weniger Asteroiden gleichzeitig
        let madPowerUpFactor = 2.0       // doppelte Power-Up-Chance
        let madPowerUpCap = 0.5          // aber höchstens 50 %
        let reducedAsteroids = max(3, Int((Double(base.maxAsteroids) * madAsteroidFactor).rounded()))
        let boostedPowerUp = min(madPowerUpCap, base.powerUpChance * madPowerUpFactor)
        return LevelSpawnConfig(
            level: base.level,
            maxAsteroids: reducedAsteroids,
            spawnRate: base.spawnRate,
            speedMultiplier: base.speedMultiplier,
            powerUpChance: boostedPowerUp,
            normalWeight: base.normalWeight,
            implodingWeight: base.implodingWeight,
            wobblingWeight: base.wobblingWeight,
            ufoInterval: base.ufoInterval,
            blackHoleInterval: base.blackHoleInterval
        )
    }
    
    /// Dynamically adjusted max asteroids based on level configuration
    private var maxAsteroidsCount: Int {
        return currentConfig().maxAsteroids
    }
    
    // Active Entities
    public private(set) var activeUFOs: [UFO] = []
    public private(set) var activeGravityWells: [GravityWell] = []
    public private(set) var activePowerUps: [PowerUp] = []
    private var options: [OptionDrone] = []

    /// Aktiver Kopf-Boss („Der Götze"), falls gerade einer im Bild ist (max. einer gleichzeitig).
    public private(set) var activeHead: FloatingHead?
    /// In welchem Level der Kopf-Boss zum ersten Mal auftaucht – pro Spiel zufällig 5–7.
    private var bossFirstTargetLevel: Int = Int.random(in: 5...7)
    /// Ob der erste Auftritt (Level 5–7) bereits erfolgt ist.
    private var bossFirstDone: Bool = false
    /// Ob der Auftritt in Level 10 bereits erfolgt ist.
    private var bossLevel10Done: Bool = false
    /// Nächster zeitgesteuerter Auftritt in Level 10 (alle 4–7 Min, da es kein weiteres Level gibt).
    private var nextBossTimeLevel10: TimeInterval = 0.0
    /// Flanken-Erkennung: war der Kopf im letzten Frame in der Spawn-Phase? (für den Sample-Trigger)
    private var headWasSpawning: Bool = false

    /// Aktive Weltraumkatzen (Minibosse), die gerade im Bild sind.
    public private(set) var activeCats: [SpaceCat] = []
    /// Ab diesem Level können Katzen auftauchen (vor dem Kopf-Boss in 5–7).
    private let catFirstLevel: Int = 3
    /// Wie viele Katzen gleichzeitig erlaubt sind (bewusst klein – sie sollen besonders bleiben).
    private let maxActiveCats: Int = 1
    /// Ob der Katzen-Timer schon scharfgestellt wurde (erst ab Eignung).
    private var catTimerArmed: Bool = false
    /// Zeitpunkt des nächsten Katzen-Spawns (absolute Spielzeit).
    private var nextCatTime: TimeInterval = 0.0

    // Power-up durations
    private var tripleShotEndTime: TimeInterval = 0.0
    private var rapidFireEndTime: TimeInterval = 0.0
    private var beamEndTime: TimeInterval = 0.0       // Laserbeam (Space halten)
    private var rearLaserEndTime: TimeInterval = 0.0  // Zusätzlicher Schuss nach hinten
    private var compressEndTime: TimeInterval = 0.0   // Schiff auf ~30% verkleinert

    /// Gespeicherte Extra-Leben (Revive in der Mitte statt Game Over).
    private var extraLives: Int = 0

    // Power-up-Tuning (Dauer in Sekunden) – hier zentral justierbar.
    private let beamDuration: TimeInterval = 10.0
    private let rearLaserDuration: TimeInterval = 12.0
    private let compressDuration: TimeInterval = 24.0
    private let compressScale: CGFloat = 0.3          // Stufe 1
    private let compressLevel2Scale: CGFloat = 0.04   // Stufe 2: nur noch ein Pixel
    /// Aktuelle Compress-Stufe (0 = normal, 1 = klein, 2 = winzig). Gilt für Schiff UND Beiboote.
    private var compressLevel: Int = 0
    /// Dämpft die Power-up-Drop-Häufigkeit global (Feedback: kamen zu oft). 1.0 = wie Level-Config.
    private let powerUpDropScale: Double = 0.55
    private let extraLifeInvincibility: TimeInterval = 5.0

    /// Visueller Knoten für den Laserbeam (wird pro Frame neu aufgebaut).
    private let beamNode = SKShapeNode()

    // Invincibility state (blinking on shield burst)
    private var invincibilityEndTime: TimeInterval = 0.0
    
    // Feuertaste-Status: gehalten = Dauerfeuer (mit normaler bzw. Rapidfire-Feuerrate).
    private var isSpaceHeld: Bool = false
    /// Auto-Feuer: das Schiff schießt durchgehend von selbst, ohne dass man die Feuertaste hält.
    /// Engine-Default aus (für Headless-Tests); die App-Hosts (macOS/iOS) schalten es zum Start AN
    /// – entspanntes Spielgefühl, ideal fürs iPhone. Umschaltbar (Einstellungen).
    public var autoFire: Bool = false

    // Enemy Spawning times
    private var lastUFOSpawnTime: TimeInterval = 0.0
    private var lastGravityWellSpawnTime: TimeInterval = 0.0
    
    // UI Label Nodes
    private let titleLabel = SKLabelNode(fontNamed: "Courier-Bold")
    private let startPromptLabel = SKLabelNode(fontNamed: "Courier")
    private let instructionsLabel = SKLabelNode(fontNamed: "Courier")
    
    private let scoreLabel = SKLabelNode(fontNamed: "Courier-Bold")
    private let hiScoreLabel = SKLabelNode(fontNamed: "Courier-Bold")
    
    private let nameEntryPromptLabel = SKLabelNode(fontNamed: "Courier-Bold")
    private let nameEntryInputLabel = SKLabelNode(fontNamed: "Courier-Bold")
    
    private let gameOverLabel = SKLabelNode(fontNamed: "Courier-Bold")
    private let finalScoreLabel = SKLabelNode(fontNamed: "Courier")
    private let restartLabel = SKLabelNode(fontNamed: "Courier")
    
    private let highScoresTitleLabel = SKLabelNode(fontNamed: "Courier-Bold")
    private var highScoreLineLabels: [SKLabelNode] = []
    
    // Level and HUD labels
    private let timerLabel = SKLabelNode(fontNamed: "Courier-Bold")
    private let levelLabel = SKLabelNode(fontNamed: "Courier")
    private let livesLabel = SKLabelNode(fontNamed: "Courier")
    private let levelSelectionLabel = SKLabelNode(fontNamed: "Courier-Bold")
    private let modeSelectionLabel = SKLabelNode(fontNamed: "Courier-Bold")
    // Einstellungen-Ansicht: Titel + drei Umschalt-Zeilen + Bedien-Hinweis.
    private let settingsTitleLabel = SKLabelNode(fontNamed: "Courier-Bold")
    private let settingsMusicLabel = SKLabelNode(fontNamed: "Courier")
    private let settingsSfxLabel = SKLabelNode(fontNamed: "Courier")
    private let settingsAutoFireLabel = SKLabelNode(fontNamed: "Courier")
    private let settingsHintLabel = SKLabelNode(fontNamed: "Courier")
    private let levelClearedLabel = SKLabelNode(fontNamed: "Courier-Bold")
    private let prepareNextLevelLabel = SKLabelNode(fontNamed: "Courier")
    
    // Quit Confirmation Overlay
    private let quitPromptLabel = SKLabelNode(fontNamed: "Courier-Bold")
    private let quitSubPromptLabel = SKLabelNode(fontNamed: "Courier")
    
    // Glossary Elements
    private let glossaryContainer = SKNode()
    private let glossaryStaticContainer = SKNode()
    private let glossaryPromptLabel = SKLabelNode(fontNamed: "Courier")
    /// Y-Position des untersten Glossar-Eintrags (für die Scroll-Schleifengrenzen).
    private var glossaryContentBottom: CGFloat = -750
    /// Untere Scroll-Grenze (Startposition): der oberste Eintrag erscheint von unten.
    private var glossaryScrollBottom: CGFloat { -600 }
    /// Obere Scroll-Grenze: weit genug, dass der unterste Eintrag oben hinausläuft, bevor umgebrochen wird.
    private var glossaryScrollTop: CGFloat { -glossaryContentBottom + 450 }
    
    /// Currently pressed keys.
    private var activeKeys = Set<UInt16>()
    
    /// The timestamp of the last update.
    private var lastUpdateTime: TimeInterval = 0.0
    
    /// The timestamp when the last laser was fired.
    private var lastLaserTime: TimeInterval = 0.0
    
    /// Camera node for screen shake effects.
    private let cameraNode = SKCameraNode()
    
    /// Background stars.
    private var stars: [StarNode] = []
    
    // MARK: - Scene Lifecycle
    
    public override func didMove(to view: SKView) {
        super.didMove(to: view)

        // Gebündelten Pixel-Font registrieren, bevor die Labels konfiguriert werden.
        RetroFont.registerIfNeeded()

        // Center the anchor point for a retro coordinate system centered at (0, 0)
        self.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        
        // Setup camera node
        self.addChild(cameraNode)
        self.camera = cameraNode
        cameraNode.position = .zero
        
        // Setup starfield
        setupStarfield()
        
        // Instantiate and add the ship at the center
        self.ship = Ship()
        self.ship.position = .zero
        self.addChild(self.ship)
        
        // Load high scores from storage
        loadHighScores()
        maxLevelReached = UserDefaults.standard.integer(forKey: "exploids_max_level_reached")
        if maxLevelReached < 1 {
            maxLevelReached = 1
        }
        selectedStartLevel = 1
        
        // Setup UI Labels
        setupUIElements()
        
        // If we are running unit tests, start in .playing directly, otherwise start in .startScreen
        if NSClassFromString("XCTestCase") != nil {
            transitionTo(.playing)
        } else {
            transitionTo(.startScreen)
        }
        
        // Tastatur-Fokus sicherstellen: Die hostende SKView muss First Responder des Fensters sein,
        // sonst erreichen keyDown-Events die Scene nicht. Beim Aufruf von didMove ist das Fenster
        // noch nicht fertig (view.window == nil), daher verzögert auf dem Main-Loop nachsetzen.
        // Nur macOS: First-Responder/keyDown gibt es auf iOS nicht – dort kommt die Eingabe per Touch.
        #if canImport(AppKit)
        DispatchQueue.main.async { [weak view] in
            guard let view = view else { return }
            view.window?.makeFirstResponder(view)
        }
        #endif
    }
    
    // MARK: - Input Handling

    /// Wird ausgelöst, wenn der Spieler die App beenden will (Cmd+Q auf macOS). Die Plattform-Shell
    /// legt das konkrete Verhalten fest (macOS: `NSApplication.terminate`). Auf iOS bleibt das i. d. R.
    /// ungesetzt, da iOS-Apps sich laut Apple-HIG nicht selbst beenden.
    public var onQuit: (() -> Void)?

    // Die folgenden NSEvent-Overrides sind die macOS-Tastatur-Brücke: Sie ziehen die nötigen Felder
    // aus dem Event und reichen sie an die plattformunabhängige Verarbeitung weiter. NSEvent existiert
    // nur auf macOS – auf iOS kommt die Eingabe über die Touch-/Controller-Schicht in `handleKeyDown`.
    #if canImport(AppKit)
    public override func keyDown(with event: NSEvent) {
        handleKeyDown(
            keyCode: event.keyCode,
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            isCommandDown: event.modifierFlags.contains(.command)
        )
    }

    public override func keyUp(with event: NSEvent) {
        handleKeyUp(keyCode: event.keyCode)
    }
    #endif

    /// Plattformunabhängige Verarbeitung eines Tastendrucks. Aufgerufen von der macOS-keyDown-Brücke,
    /// den Simulate-Helfern (Headless-Tests) und künftig der iOS-Touch-/Controller-Schicht.
    /// - Parameters:
    ///   - keyCode: virtueller Tastencode (macOS-Layout; die Spiellogik kennt nur diese Codes)
    ///   - characters: getippte Zeichen (für den „#"-Cheat und die Initialen-Eingabe), ggf. nil
    ///   - charactersIgnoringModifiers: Zeichen ohne Modifier (Cmd+Q, „M"-Musik-Toggle), ggf. nil
    ///   - isCommandDown: ob die Command-Taste gehalten wird (für Cmd+Q)
    private func handleKeyDown(keyCode: UInt16, characters: String?, charactersIgnoringModifiers: String?, isCommandDown: Bool) {
        if isCommandDown, charactersIgnoringModifiers?.lowercased() == "q" {
            onQuit?()
            return
        }

        // „M" schaltet die Hintergrundmusik global ein/aus – in jedem Zustand außer der
        // Initialen-Eingabe (dort ist „M" ein einzugebender Buchstabe).
        if gameState != .nameEntry, charactersIgnoringModifiers?.lowercased() == "m" {
            MusicPlayer.shared.toggle()
            updateSettingsLabels()
            return
        }

        // „N" schaltet den SFX-Stil um: prozedurale Synth-Effekte <-> generierte Samples.
        // Zum sofortigen Vergleich spielt direkt ein Bestätigungs-Sound im NEUEN Modus.
        // Ebenfalls überall außer bei der Initialen-Eingabe (dort ist „N" ein Buchstabe).
        if gameState != .nameEntry, charactersIgnoringModifiers?.lowercased() == "n" {
            SoundManager.shared.useSampledSFX.toggle()
            updateSettingsLabels()
            SoundManager.shared.playPowerUp()
            return
        }

        // „F" schaltet Auto-Feuer um (global außer bei der Initialen-Eingabe).
        if gameState != .nameEntry, charactersIgnoringModifiers?.lowercased() == "f" {
            autoFire.toggle()
            updateSettingsLabels()
            return
        }

        switch gameState {
        case .startScreen:
            if keyCode == 49 || keyCode == 36 { // Space or Enter
                currentLevel = selectedStartLevel
                transitionTo(.playing)
            } else if keyCode == 123 || (keyCode == 0 && characters?.lowercased() == "a") { // Left arrow or A
                if selectedStartLevel > 1 {
                    selectedStartLevel -= 1
                    updateLevelSelectionLabel()
                }
            } else if keyCode == 124 || (keyCode == 2 && characters?.lowercased() == "d") { // Right arrow or D
                if selectedStartLevel < 10 {
                    selectedStartLevel += 1
                    updateLevelSelectionLabel()
                }
            } else if keyCode == 126 || keyCode == 125 { // Up or Down arrow -> toggle game mode
                selectedMode = (selectedMode == .ancientAsteroids) ? .madMeteoroids : .ancientAsteroids
                updateModeSelectionLabel()
            } else if let characters = characters?.lowercased() {
                if characters == "i" {
                    transitionTo(.glossary)
                } else if characters == "h", !showsHighScoresOnStartScreen {
                    // Nur wenn die Liste ausgelagert ist (iOS): eigene Highscore-Ansicht öffnen.
                    transitionTo(.highScores)
                } else if characters == "o" {
                    transitionTo(.settings)
                }
            }

        case .playing:
            if keyCode == 53 { // Escape -> quit confirmation
                transitionTo(.quitConfirmation)
                return
            }
            if characters == "#" { // Undokumentierter Cheat: ein Extra-Leben (zum Testen)
                extraLives += 1
                updateLivesLabel()
                showPowerUpNotification(text: "EXTRA LIFE!", color: SKColor(red: 1.0, green: 0.3, blue: 0.45, alpha: 1.0))
                return
            }
            activeKeys.insert(keyCode)
            if keyCode == 49 { // Feuertaste: erster Schuss sofort, Halten feuert weiter (siehe update)
                if !isSpaceHeld {
                    isSpaceHeld = true
                    fireLaser()
                }
            }

        case .nameEntry:
            if keyCode == 36 { // Enter / Return
                if typedInitials.count == 3 {
                    recordHighScore(initials: typedInitials, score: score)
                    transitionTo(.gameOver)
                }
            } else if keyCode == 51 { // Backspace
                if !typedInitials.isEmpty {
                    typedInitials.removeLast()
                    updateNameEntryInputLabel()
                }
            } else if let chars = characters, !chars.isEmpty {
                let char = chars.first!
                let isAllowed = char.isLetter || char.isNumber || char == " "
                if isAllowed && typedInitials.count < 3 {
                    typedInitials.append(String(char).uppercased())
                    updateNameEntryInputLabel()
                }
            }

        case .gameOver:
            if keyCode == 15 || keyCode == 49 { // R key or Space bar -> replay same mode/level
                transitionTo(.playing)
            } else if keyCode == 53 { // Escape -> back to start screen (choose mode and level)
                transitionTo(.startScreen)
            }

        case .quitConfirmation:
            if keyCode == 53 { // Escape -> resume
                transitionTo(.playing)
            } else if let characters = characters?.lowercased(), characters == "y" {
                transitionTo(.startScreen)
            }

        case .glossary:
            if keyCode == 53 { // Escape -> back to title
                transitionTo(.startScreen)
            } else if keyCode == 126 || keyCode == 13 { // Up Arrow or W
                glossaryContainer.position.y += 20.0
                if glossaryContainer.position.y > glossaryScrollTop {
                    glossaryContainer.position.y = glossaryScrollBottom
                }
            } else if keyCode == 125 || keyCode == 1 { // Down Arrow or S
                glossaryContainer.position.y -= 20.0
                if glossaryContainer.position.y < glossaryScrollBottom {
                    glossaryContainer.position.y = glossaryScrollTop
                }
            } else if let characters = characters?.lowercased() {
                if characters == "i" {
                    transitionTo(.startScreen)
                }
            }

        case .highScores:
            // Eigene Highscore-Ansicht: einzige Aktion ist Zurück zum Startbildschirm.
            if keyCode == 53 { // Escape
                transitionTo(.startScreen)
            }

        case .settings:
            // Umschalten passiert global (M/N/F, oben); hier nur Zurück.
            if keyCode == 53 { // Escape
                transitionTo(.startScreen)
            }
        }
    }

    /// Plattformunabhängige Verarbeitung des Loslassens einer Taste.
    private func handleKeyUp(keyCode: UInt16) {
        if gameState == .playing {
            activeKeys.remove(keyCode)
            if keyCode == 49 { // Feuertaste losgelassen: Dauerfeuer beenden
                isSpaceHeld = false
            }
        }
    }
    
    // MARK: - Laser Firing
    
    /// Spawns a laser from the ship's tip with a cooldown limit.
    private func fireLaser() {
        let now = ProcessInfo.processInfo.systemUptime
        let isRapidActive = now < rapidFireEndTime
        let cooldown: TimeInterval = isRapidActive ? 0.06 : 0.15
        
        guard now - lastLaserTime >= cooldown else { return }
        lastLaserTime = now
        
        let angle = ship.zRotation
        let tipDistance: CGFloat = 18.0
        let spawnPos = CGPoint(
            x: ship.position.x + tipDistance * cos(angle),
            y: ship.position.y + tipDistance * sin(angle)
        )
        
        let isTripleActive = now < tripleShotEndTime
        
        if isTripleActive {
            // Spawn 3 lasers in a spread pattern
            let centerLaser = Laser(position: spawnPos, angle: angle, type: .normal)
            let leftLaser = Laser(position: spawnPos, angle: angle + 0.25, type: .normal)
            let rightLaser = Laser(position: spawnPos, angle: angle - 0.25, type: .normal)
            
            self.addChild(centerLaser)
            self.addChild(leftLaser)
            self.addChild(rightLaser)
            
            self.activeLasers.append(centerLaser)
            self.activeLasers.append(leftLaser)
            self.activeLasers.append(rightLaser)
        } else {
            // Spawn single normal laser
            let laser = Laser(position: spawnPos, angle: angle, type: .normal)
            self.addChild(laser)
            self.activeLasers.append(laser)
        }
        
        // Fire option lasers if drones are collected
        for option in options {
            let optionSpawnPos = option.position
            let optionLaser = Laser(position: optionSpawnPos, angle: angle, type: .normal)
            self.addChild(optionLaser)
            self.activeLasers.append(optionLaser)
        }

        // Rear laser power-up: additionally fire one shot straight backwards.
        if now < rearLaserEndTime {
            let rearAngle = angle + .pi
            let rearSpawn = CGPoint(
                x: ship.position.x + tipDistance * cos(rearAngle),
                y: ship.position.y + tipDistance * sin(rearAngle)
            )
            let rearLaser = Laser(position: rearSpawn, angle: rearAngle, type: .normal)
            self.addChild(rearLaser)
            self.activeLasers.append(rearLaser)
        }

        // Play laser sound effect
        SoundManager.shared.playLaser()
    }
    
    /// Spawns an R-Type Wave Cannon Charge Shot.
    // MARK: - Game Loop
    
    public override func update(_ currentTime: TimeInterval) {
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
            lastSpawnTime = currentTime
            lastUFOSpawnTime = currentTime
            lastGravityWellSpawnTime = currentTime
            return
        }
        let deltaTime = currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        
        if gameState == .quitConfirmation {
            return
        }

        // Mad-Meteoroids: Feld-Drehung dieses Frames bestimmen, BEVOR Sterne/Objekte sie nutzen.
        // Nur im laufenden Spiel und nicht während des Level-Übergangs.
        fieldDeltaThisFrame = 0.0
        if gameState == .playing && gameMode == .madMeteoroids && !isLevelClearing {
            if fieldRotationPending {
                configureFieldRotationForLevel(currentTime: currentTime)
                fieldRotationPending = false
            }
            updateFieldRotation(deltaTime: deltaTime, currentTime: currentTime)
            fieldDeltaThisFrame = fieldAngularVelocity * CGFloat(deltaTime)
        }

        // Background elements (stars) always update
        updateStars(deltaTime: deltaTime)
        
        if gameState == .glossary {
            let scrollSpeed: CGFloat = 35.0
            glossaryContainer.position.y += scrollSpeed * CGFloat(deltaTime)

            if glossaryContainer.position.y > glossaryScrollTop {
                glossaryContainer.position.y = glossaryScrollBottom
            } else if glossaryContainer.position.y < glossaryScrollBottom {
                glossaryContainer.position.y = glossaryScrollTop
            }
            return
        }
        
        switch gameState {
        case .startScreen:
            // Periodically spawn new asteroids for menu background decoration
            if currentTime - lastSpawnTime >= 2.0 {
                lastSpawnTime = currentTime
                if activeAsteroids.count < 4 {
                    spawnAsteroid()
                }
            }
            
        case .playing:
            playTime += deltaTime
            
            if isLevelClearing {
                if currentTime >= levelClearEndTime {
                    isLevelClearing = false
                    currentLevel += 1
                    if currentLevel > maxLevelReached {
                        maxLevelReached = currentLevel
                        UserDefaults.standard.set(maxLevelReached, forKey: "exploids_max_level_reached")
                    }
                    // Drehzahl/Wechsel-Frequenz fürs neue Level neu planen (Mad-Modus).
                    fieldRotationPending = true
                    levelTimeRemaining = (currentLevel >= 10) ? 999999.0 : 60.0
                    levelLabel.text = "LEVEL: \(currentLevel)"
                    if currentLevel >= 10 {
                        timerLabel.text = "TIME: SURVIVAL"
                    } else {
                        timerLabel.text = "TIME: 01:00"
                    }
                    
                    levelClearedLabel.isHidden = true
                    prepareNextLevelLabel.isHidden = true
                    
                    lastSpawnTime = currentTime
                    lastUFOSpawnTime = currentTime
                    lastGravityWellSpawnTime = currentTime
                    
                    // Extend remaining lifetime of active power-ups to at least 5s for the new level
                    for p in activePowerUps {
                        let remaining = p.lifetime - p.elapsedTime
                        if remaining < 5.0 {
                            p.setRemainingLifetime(to: 5.0)
                        }
                    }
                    
                    let initialCount = max(3, currentConfig().maxAsteroids / 2)
                    for _ in 0..<initialCount {
                        spawnAsteroid()
                    }
                }
            } else {
                // Decrement level timer only if level < 10
                if currentLevel < 10 {
                    levelTimeRemaining -= deltaTime
                    if levelTimeRemaining <= 0 {
                        levelTimeRemaining = 0
                        isLevelClearing = true
                        levelClearEndTime = currentTime + 3.5
                        
                        clearGameEntitiesKeepOptions()
                        
                        // Ensure all active powerups persist through the 3.5s transition and for 5s into the next level
                        for p in activePowerUps {
                            let remaining = p.lifetime - p.elapsedTime
                            if remaining < 8.5 {
                                p.setRemainingLifetime(to: 8.5)
                            }
                        }
                        
                        levelClearedLabel.text = "LEVEL \(currentLevel) COMPLETED!"
                        prepareNextLevelLabel.text = "PREPARE FOR LEVEL \(currentLevel + 1)"
                        levelClearedLabel.isHidden = false
                        prepareNextLevelLabel.isHidden = false
                        
                        SoundManager.shared.playLevelComplete()
                        
                        levelClearedLabel.removeAction(forKey: "blink")
                        let fadeOut = SKAction.fadeOut(withDuration: 0.3)
                        let fadeIn = SKAction.fadeIn(withDuration: 0.3)
                        let blink = SKAction.sequence([fadeOut, fadeIn])
                        levelClearedLabel.run(SKAction.repeatForever(blink), withKey: "blink")
                    }
                }
                
                if !isLevelClearing {
                    if currentLevel >= 10 {
                        timerLabel.text = "TIME: SURVIVAL"
                    } else {
                        let minutes = Int(levelTimeRemaining) / 60
                        let seconds = Int(levelTimeRemaining) % 60
                        timerLabel.text = String(format: "TIME: %02d:%02d", minutes, seconds)
                    }
                    
                    // Spawning Logic
                    let config = currentConfig()
                    
                    // Periodically spawn new asteroids
                    if isSpawningEnabled && currentTime - lastSpawnTime >= config.spawnRate {
                        lastSpawnTime = currentTime
                        if activeAsteroids.count < config.maxAsteroids {
                            spawnAsteroid()
                        }
                    }
                    
                    // Periodically spawn UFO enemies
                    if let ufoInt = config.ufoInterval {
                        if isSpawningEnabled && currentTime - lastUFOSpawnTime >= ufoInt {
                            lastUFOSpawnTime = currentTime
                            if activeUFOs.count < 2 {
                                let isSmallUFO = Double.random(in: 0...1) < 0.45
                                let ufo = UFO(isSmall: isSmallUFO, startOnLeft: Bool.random(), screenSize: size)
                                self.addChild(ufo)
                                self.activeUFOs.append(ufo)
                            }
                        }
                    }
                    
                    // Periodically spawn Gravity Wells (Black Holes)
                    if let bhInt = config.blackHoleInterval {
                        if isSpawningEnabled && currentTime - lastGravityWellSpawnTime >= bhInt {
                            lastGravityWellSpawnTime = currentTime
                            if activeGravityWells.isEmpty {
                                let well = GravityWell()
                                
                                let halfW = size.width / 2
                                let halfH = size.height / 2
                                var spawnPos = CGPoint.zero
                                var attempts = 0
                                repeat {
                                    spawnPos = CGPoint(
                                        x: CGFloat.random(in: -halfW * 0.5...halfW * 0.5),
                                        y: CGFloat.random(in: -halfH * 0.5...halfH * 0.5)
                                    )
                                    attempts += 1
                                } while attempts < 50 && distanceBetween(spawnPos, ship.position) < 220.0
                                
                                well.position = spawnPos
                                self.addChild(well)
                                self.activeGravityWells.append(well)
                            }
                        }
                    }
                }
            }
            
            // Kopf-Boss (Boss-Welle) auslösen und aktualisieren – nur im laufenden Spiel.
            if !isLevelClearing {
                updateFloatingHead(currentTime: currentTime, deltaTime: deltaTime)
                updateSpaceCats(currentTime: currentTime, deltaTime: deltaTime)
            }

            // Determine input states
            let isThrusting = activeKeys.contains(13) || activeKeys.contains(126)
            
            var rotationInput: CGFloat = 0.0
            if activeKeys.contains(0) || activeKeys.contains(123) {
                rotationInput += 1.0
            }
            if activeKeys.contains(2) || activeKeys.contains(124) {
                rotationInput -= 1.0
            }
            
            // Update the ship
            ship.update(deltaTime: deltaTime, isThrusting: isThrusting, rotationInput: rotationInput)
            ship.wrapAround(screenSize: size)

            // Power-up-Effekte mit Zeitbezug (Compress-Ablauf, Laserbeam-Strahl).
            updateTimedPowerUpEffects(currentTime: currentTime)

            // Update options follow interpolation
            let dt = CGFloat(deltaTime)
            for (index, option) in options.enumerated() {
                let targetPos = ship.getOptionTargetPosition(index: index, totalOptions: options.count)
                let t = 1.0 - pow(0.001, dt)
                option.position.x += (targetPos.x - option.position.x) * t
                option.position.y += (targetPos.y - option.position.y) * t
                option.zRotation = ship.zRotation
            }
            
            // Engine-Hum aktualisieren. Feuertaste halten = Dauerfeuer mit normaler Feuerrate
            // (fireLaser begrenzt selbst per Cooldown; mit Rapidfire wird der Cooldown kürzer).
            SoundManager.shared.setThrustActive(isThrusting)
            if (autoFire || isSpaceHeld) && !ship.isHidden {
                fireLaser()
            }
            
            // Unverwundbarkeit (z.B. nach Extra-Life-Revive) gilt für ALLE Todesarten,
            // also schon vor der Gravity-Well-Prüfung bestimmen.
            let isInvincible = currentTime < invincibilityEndTime

            // Apply Gravity Well attraction forces
            var wellsToCollapse: [GravityWell] = []
            for well in activeGravityWells {
                // Pull Ship
                if !ship.isHidden {
                    let pull = well.calculatePull(on: ship.position)
                    ship.velocity.x += pull.x * dt
                    ship.velocity.y += pull.y * dt

                    let dist = distanceBetween(well.position, ship.position)
                    if !isInvincible && dist <= well.eventHorizonRadius {
                        // Über damageShip(), damit ein Extra-Leben auch hier den Tod abfängt.
                        lastDeathCause = .gravityWell
                        damageShip()
                        // Treffer -> das Loch kollabiert sofort und zieht nicht weiter an
                        // (sonst bliebe man im Sog hängen, nachdem z.B. ein Schild verbraucht wurde).
                        wellsToCollapse.append(well)
                    }
                }
                
                // Pull Asteroids
                var remainingAsts: [Asteroid] = []
                for asteroid in activeAsteroids {
                    let pull = well.calculatePull(on: asteroid.position)
                    asteroid.velocity.x += pull.x * dt
                    asteroid.velocity.y += pull.y * dt
                    
                    let dist = distanceBetween(well.position, asteroid.position)
                    if dist <= well.eventHorizonRadius {
                        createExplosion(at: asteroid.position, sizeClass: .small)
                        asteroid.removeFromParent()
                    } else {
                        remainingAsts.append(asteroid)
                    }
                }
                self.activeAsteroids = remainingAsts
                
                // Pull UFOs
                var remainingUFOs: [UFO] = []
                for ufo in activeUFOs {
                    let pull = well.calculatePull(on: ufo.position)
                    ufo.velocity.x += pull.x * dt
                    ufo.velocity.y += pull.y * dt
                    
                    let dist = distanceBetween(well.position, ufo.position)
                    if dist <= well.eventHorizonRadius {
                        createShipExplosion(at: ufo.position)
                        ufo.removeFromParent()
                    } else {
                        remainingUFOs.append(ufo)
                    }
                }
                self.activeUFOs = remainingUFOs
            }

            // Vom Spieler getroffene Löcher kollabieren (Sog endet sofort) – kleiner Effekt zur Quittung.
            if !wellsToCollapse.isEmpty {
                for w in wellsToCollapse {
                    createExplosion(at: w.position, sizeClass: .small)
                    w.removeFromParent()
                }
                activeGravityWells.removeAll { w in wellsToCollapse.contains(where: { $0 === w }) }
            }

            // Collision detection: Ship vs. Asteroids
            if !ship.isHidden && !isInvincible {
                let shipPoly = ship.getWorldVertices()
                for asteroid in activeAsteroids {
                    let astPoly = asteroid.getWorldVertices()
                    if CollisionHelper.polygonsIntersect(shipPoly, astPoly) {
                        if asteroid.isWobblingType {
                            lastDeathCause = .wobblingAsteroid
                        } else {
                            switch asteroid.sizeClass {
                            case .large: lastDeathCause = .largeAsteroid
                            case .medium: lastDeathCause = .mediumAsteroid
                            case .small: lastDeathCause = .smallAsteroid
                            }
                        }
                        damageShip()
                        break
                    }
                }
            }
            
            // Collision detection: Ship vs. UFOs
            if !ship.isHidden && !isInvincible {
                let shipPoly = ship.getWorldVertices()
                for ufo in activeUFOs {
                    let ufoPoly = ufo.getWorldVertices()
                    if CollisionHelper.polygonsIntersect(shipPoly, ufoPoly) {
                        createShipExplosion(at: ufo.position)
                        ufo.removeFromParent()
                        activeUFOs = activeUFOs.filter { $0 != ufo }
                        lastDeathCause = .ufo
                        damageShip()
                        break
                    }
                }
            }

            // Collision detection: Ship vs. Kopf-Boss (Kontakt = Tod)
            if let head = activeHead, !ship.isHidden && !isInvincible {
                if distanceBetween(ship.position, head.position) <= head.collisionRadius {
                    lastDeathCause = .bossHead
                    damageShip()
                }
            }

            // Collision detection: Ship vs. Weltraumkatzen (Kontakt = Tod). Die Katze überlebt das
            // (Miniboss) – nur das Schiff nimmt Schaden. Kleiner Radius-Zuschlag für faires Rammen.
            if !ship.isHidden && !isInvincible {
                for cat in activeCats {
                    if distanceBetween(ship.position, cat.position) <= cat.collisionRadius + 8.0 {
                        lastDeathCause = .spaceCat
                        damageShip()
                        break
                    }
                }
            }

            // Collision detection: Ship vs. Power-ups – distanzbasiert (Abstand der Mittelpunkte),
            // NICHT über das Schiff-Polygon. Sonst sind Power-ups bei aktivem Compress (winziges
            // Schiff) praktisch nicht mehr einsammelbar und bleiben „hängen".
            if !ship.isHidden {
                // Großzügiger Sammelradius: Power-ups driften + pulsen; bei 30 ging man leicht über
                // den Rand, ohne einzusammeln. 40 = visuelles Überfliegen sammelt zuverlässig ein.
                let collectRadius: CGFloat = 40.0
                // WICHTIG: erst die einzusammelnden bestimmen, DANN einsammeln und gezielt aus dem
                // Array entfernen. Nicht „remainingPowerUps neu bauen und activePowerUps überschreiben":
                // collectPowerUp kann (Bombe -> detonateBomb -> spawnPowerUp) WÄHRENDDESSEN neue
                // Power-ups an activePowerUps anhängen; ein Überschreiben würde die verlieren — sie
                // blieben als verwaiste Nodes im Szenengraph (uneinsammelbar, laufen nie ab, überleben
                // jeden Clear). Identitäts-basiertes Entfernen bewahrt die neu gespawnten.
                let collected = activePowerUps.filter {
                    distanceBetween(ship.position, $0.position) <= collectRadius
                }
                for powerUp in collected {
                    SoundManager.shared.playPowerUp()
                    collectPowerUp(powerUp)
                    powerUp.removeFromParent()
                }
                if !collected.isEmpty {
                    activePowerUps.removeAll { p in collected.contains { $0 === p } }
                }
            }
            
            // Collision detection: Player Lasers vs. Asteroids
            var remainingLasers: [Laser] = []
            var hitAsteroids = Set<Asteroid>()
            var newAsteroids: [Asteroid] = []
            
            for laser in activeLasers {
                if laser.type != .normal {   // Gegner-Schüsse (UFO + Katze) treffen keine Asteroiden
                    remainingLasers.append(laser)
                    continue
                }

                var laserHit = false
                for asteroid in activeAsteroids {
                    if !hitAsteroids.contains(asteroid) && CollisionHelper.laserIntersectsAsteroid(laser, asteroid) {
                        laser.pierceCount += 1
                        if laser.pierceCount >= laser.pierceLimit {
                            laserHit = true
                        }
                        
                        processPlayerHitOnAsteroid(asteroid, hitPosition: laser.position,
                                                   hitAsteroids: &hitAsteroids, newAsteroids: &newAsteroids)

                        if laserHit {
                            break
                        }
                    }
                }
                
                if laserHit {
                    laser.removeFromParent()
                } else {
                    remainingLasers.append(laser)
                }
            }
            
            // Process hit asteroid filtering and splitting
            if !hitAsteroids.isEmpty {
                activeAsteroids = activeAsteroids.filter { asteroid in
                    if hitAsteroids.contains(asteroid) {
                        asteroid.removeFromParent()
                        return false
                    }
                    return true
                }
            }
            activeAsteroids.append(contentsOf: newAsteroids)
            
            // Collision detection: Asteroid vs Asteroid (Absorption)
            var asteroidsToRemoval = Set<Asteroid>()
            var collapsedImplodingAsteroids = Set<Asteroid>()
            
            for i in 0..<activeAsteroids.count {
                let astA = activeAsteroids[i]
                guard !asteroidsToRemoval.contains(astA) else { continue }
                
                for j in (i+1)..<activeAsteroids.count {
                    let astB = activeAsteroids[j]
                    guard !asteroidsToRemoval.contains(astB) else { continue }
                    
                    if astA.isImplodingType || astB.isImplodingType {
                        let polyA = astA.getWorldVertices()
                        let polyB = astB.getWorldVertices()
                        if CollisionHelper.polygonsIntersect(polyA, polyB) {
                            let absorber: Asteroid
                            let absorbed: Asteroid
                            
                            if astA.isImplodingType && astB.isImplodingType {
                                if astA.xScale >= astB.xScale {
                                    absorber = astA
                                    absorbed = astB
                                } else {
                                    absorber = astB
                                    absorbed = astA
                                }
                            } else if astA.isImplodingType {
                                absorber = astA
                                absorbed = astB
                            } else {
                                absorber = astB
                                absorbed = astA
                            }
                            
                            asteroidsToRemoval.insert(absorbed)
                            
                            let currentScale = absorber.xScale
                            let newScale = currentScale + 0.35
                            absorber.xScale = newScale
                            absorber.yScale = newScale
                            
                            createExplosion(at: absorbed.position, sizeClass: .small)
                            
                            if newScale >= 3.0 {
                                collapsedImplodingAsteroids.insert(absorber)
                                asteroidsToRemoval.insert(absorber)
                            }
                        }
                    }
                }
            }
            
            for ast in collapsedImplodingAsteroids {
                triggerImplosionCollapse(asteroid: ast)
            }
            
            if !asteroidsToRemoval.isEmpty {
                activeAsteroids = activeAsteroids.filter { ast in
                    if asteroidsToRemoval.contains(ast) {
                        ast.removeFromParent()
                        return false
                    }
                    return true
                }
            }
            
            // Collision detection: Player Lasers vs. UFOs
            var hitUFOs = Set<UFO>()
            var remainingLasers2: [Laser] = []
            
            for laser in remainingLasers {
                if laser.type != .normal {   // Gegner-Schüsse (UFO + Katze) treffen keine UFOs
                    remainingLasers2.append(laser)
                    continue
                }

                var laserHit = false
                let (start, end) = laser.getWorldSegment()

                for ufo in activeUFOs {
                    let ufoPoly = ufo.getWorldVertices()
                    let hit = CollisionHelper.isPointInPolygon(start, polygon: ufoPoly) || CollisionHelper.isPointInPolygon(end, polygon: ufoPoly)
                    
                    if !hitUFOs.contains(ufo) && hit {
                        laser.pierceCount += 1
                        if laser.pierceCount >= laser.pierceLimit {
                            laserHit = true
                        }
                        
                        hitUFOs.insert(ufo)
                        
                        self.score += ufo.pointValue
                        scoreLabel.text = "SCORE: \(String(format: "%05d", score))"
                        
                        // Drop power-up on UFO hit
                        if Double.random(in: 0...1) <= 0.20 {
                            spawnPowerUp(at: ufo.position)
                        }
                        
                        SoundManager.shared.playExplosion()
                        createShipExplosion(at: ufo.position)
                        shakeCamera(amplitude: 4.0, numberOfShakes: 5, durationPerShake: 0.025)
                        
                        if laserHit {
                            break
                        }
                    }
                }
                
                if laserHit {
                    laser.removeFromParent()
                } else {
                    remainingLasers2.append(laser)
                }
            }
            remainingLasers = remainingLasers2
            
            if !hitUFOs.isEmpty {
                activeUFOs = activeUFOs.filter { ufo in
                    if hitUFOs.contains(ufo) {
                        ufo.removeFromParent()
                        return false
                    }
                    return true
                }
            }

            // Collision detection: Player Lasers vs. Kopf-Boss (3 Treffer bis zerstört)
            if let head = activeHead {
                var lasersAfterHead: [Laser] = []
                var headAlive = true
                for laser in remainingLasers {
                    // Gegner-Schüsse (UFO + Katze) ignorieren; nach dem Tod des Bosses Rest behalten.
                    if !headAlive || laser.type != .normal {
                        lasersAfterHead.append(laser)
                        continue
                    }
                    let (start, end) = laser.getWorldSegment()
                    let hit = distanceBetween(start, head.position) <= head.collisionRadius
                           || distanceBetween(end, head.position) <= head.collisionRadius
                    if hit {
                        let destroyed = head.registerHit()
                        SoundManager.shared.playExplosion()
                        createShipExplosion(at: laser.position)
                        shakeCamera(amplitude: 5.0, numberOfShakes: 6, durationPerShake: 0.025)
                        // Schuss verbraucht (kein Durchschlag durch den Boss)
                        laser.removeFromParent()

                        if destroyed {
                            self.score += 2000
                            scoreLabel.text = "SCORE: \(String(format: "%05d", score))"
                            createShipExplosion(at: head.position)
                            shakeCamera(amplitude: 9.0, numberOfShakes: 10, durationPerShake: 0.03)
                            head.removeFromParent()
                            activeHead = nil
                            headAlive = false
                        }
                    } else {
                        lasersAfterHead.append(laser)
                    }
                }
                remainingLasers = lasersAfterHead
            }

            // Collision detection: Player Lasers vs. Weltraumkatzen (Miniboss mit HP)
            if !activeCats.isEmpty {
                var lasersAfterCats: [Laser] = []
                var deadCats = Set<SpaceCat>()
                for laser in remainingLasers {
                    if laser.type != .normal {   // nur Spielerschüsse treffen die Katzen
                        lasersAfterCats.append(laser)
                        continue
                    }
                    let (start, end) = laser.getWorldSegment()
                    var consumed = false
                    for cat in activeCats where !deadCats.contains(cat) {
                        let hit = distanceBetween(start, cat.position) <= cat.collisionRadius
                               || distanceBetween(end, cat.position) <= cat.collisionRadius
                        guard hit else { continue }
                        let destroyed = cat.registerHit()
                        SoundManager.shared.playExplosion()
                        createShipExplosion(at: laser.position)
                        shakeCamera(amplitude: 4.0, numberOfShakes: 5, durationPerShake: 0.025)
                        consumed = true   // Schuss verbraucht (kein Durchschlag)
                        if destroyed {
                            self.score += cat.pointValue
                            scoreLabel.text = "SCORE: \(String(format: "%05d", score))"
                            createShipExplosion(at: cat.position)
                            shakeCamera(amplitude: 6.0, numberOfShakes: 7, durationPerShake: 0.03)
                            // Miniboss: etwas großzügigere Beute als ein normales UFO.
                            if Double.random(in: 0...1) <= 0.5 {
                                spawnPowerUp(at: cat.position)
                            }
                            deadCats.insert(cat)
                        }
                        break
                    }
                    if consumed { laser.removeFromParent() } else { lasersAfterCats.append(laser) }
                }
                remainingLasers = lasersAfterCats
                if !deadCats.isEmpty {
                    activeCats = activeCats.filter { cat in
                        if deadCats.contains(cat) { cat.removeFromParent(); return false }
                        return true
                    }
                }
            }

            // Collision detection: Enemy Lasers vs. Ship (UFO-Schüsse UND Katzen-Augenlaser)
            if !ship.isHidden && !isInvincible {
                let shipPoly = ship.getWorldVertices()
                var remainingLasers3: [Laser] = []
                for laser in remainingLasers {
                    if laser.type != .normal {
                        let (start, end) = laser.getWorldSegment()
                        if CollisionHelper.isPointInPolygon(start, polygon: shipPoly) || CollisionHelper.isPointInPolygon(end, polygon: shipPoly) {
                            laser.removeFromParent()
                            lastDeathCause = (laser.type == .catEye) ? .spaceCatLaser : .ufoLaser
                            damageShip()
                            continue
                        }
                    }
                    remainingLasers3.append(laser)
                }
                remainingLasers = remainingLasers3
            }

            self.activeLasers = remainingLasers
            
        case .nameEntry, .gameOver, .quitConfirmation, .glossary, .highScores, .settings:
            break
        }
        
        // Update active asteroids (they move and wrap in all states)
        var remainingAsteroids: [Asteroid] = []
        for asteroid in activeAsteroids {
            asteroid.update(deltaTime: deltaTime)
            if gameMode == .madMeteoroids {
                applyFieldRotation(toAsteroid: asteroid)
            } else {
                asteroid.wrapAround(screenSize: size)
            }

            if gameState == .playing && asteroid.isWobblingType {
                if asteroid.timeInCurrentPhase >= 6.0 {
                    asteroid.timeInCurrentPhase = 0.0
                    if asteroid.wobblePhase == 0 {
                        asteroid.wobblePhase = 1
                        asteroid.growToNextSize(newSize: .medium)
                    } else if asteroid.wobblePhase == 1 {
                        asteroid.wobblePhase = 2
                        asteroid.growToNextSize(newSize: .large)
                    } else if asteroid.wobblePhase == 2 {
                        let spawned = detonateWobblingAsteroid(asteroid)
                        remainingAsteroids.append(contentsOf: spawned)
                        continue
                    }
                }
            }
            remainingAsteroids.append(asteroid)
        }
        self.activeAsteroids = remainingAsteroids
        
        // Update active lasers (expire or wrap)
        var remainingLasers: [Laser] = []
        for laser in activeLasers {
            let expired = laser.update(deltaTime: deltaTime)
            if expired {
                laser.removeFromParent()
            } else {
                laser.wrapAround(screenSize: size)
                remainingLasers.append(laser)
            }
        }
        self.activeLasers = remainingLasers
        
        // Update active UFOs
        var remainingUFOs: [UFO] = []
        for ufo in activeUFOs {
            // Sanfte Verfolgung nur auf das sichtbare Schiff (kein Homing auf ein „totes"/verstecktes).
            ufo.update(deltaTime: deltaTime, target: ship.isHidden ? nil : ship.position)

            // Shoot at player ship
            if !ship.isHidden {
                if let laser = ufo.shoot(target: ship.position, currentTime: currentTime) {
                    self.addChild(laser)
                    self.activeLasers.append(laser)
                    SoundManager.shared.playUfoSound()
                }
            }
            
            if ufo.isExited(screenSize: size) {
                ufo.removeFromParent()
            } else {
                remainingUFOs.append(ufo)
            }
        }
        self.activeUFOs = remainingUFOs
        
        // Update active Gravity Wells
        var remainingWells: [GravityWell] = []
        for well in activeGravityWells {
            let collapsed = well.update(deltaTime: deltaTime)
            if collapsed {
                well.removeFromParent()
            } else {
                if gameMode == .madMeteoroids {
                    // Gravity Wells sind stationär, kreisen aber im Mad-Modus mit dem Feld mit.
                    well.position = rotatedAroundOrigin(well.position, by: fieldDeltaThisFrame)
                }
                remainingWells.append(well)
            }
        }
        self.activeGravityWells = remainingWells
        
        // Update active PowerUps
        var remainingPowerUps: [PowerUp] = []
        for p in activePowerUps {
            let expired = p.update(deltaTime: deltaTime)
            if expired {
                p.removeFromParent()
            } else {
                if gameMode == .madMeteoroids {
                    p.position = rotatedAroundOrigin(p.position, by: fieldDeltaThisFrame)
                    p.velocity = rotatedAroundOrigin(p.velocity, by: fieldDeltaThisFrame)
                    p.position = circularWrapped(p.position, radius: madFieldRadius())
                } else {
                    p.wrapAround(screenSize: size)
                }
                remainingPowerUps.append(p)
            }
        }
        self.activePowerUps = remainingPowerUps
        
        // Process Invincibility blinks
        let isInvincible = currentTime < invincibilityEndTime
        if isInvincible {
            ship.alpha = sin(currentTime * 30.0) > 0.0 ? 0.3 : 0.8
        } else {
            ship.alpha = 1.0
        }
    }
    
    // MARK: - Damage / Shield logic
    
    private func damageShip() {
        if ship.isShieldActive {
            ship.shieldLevel -= 1   // eine Schild-Stufe absorbiert den Treffer
            SoundManager.shared.playExplosion()
            createShipExplosion(at: ship.position)
            invincibilityEndTime = ProcessInfo.processInfo.systemUptime + 1.5
            shakeCamera(amplitude: 4.5, numberOfShakes: 6, durationPerShake: 0.03)
        } else if extraLives > 0 {
            // Extra-Life-Power-up: kein Game Over – stattdessen in der Mitte wiederbeleben und
            // kurz unsterblich machen. Beim Revive gehen ALLE aktiven Power-ups verloren.
            extraLives -= 1
            updateLivesLabel()
            resetPowerUpsOnRevive()
            SoundManager.shared.playExplosion()
            createShipExplosion(at: ship.position)
            ship.position = .zero
            ship.velocity = .zero
            invincibilityEndTime = ProcessInfo.processInfo.systemUptime + extraLifeInvincibility
            shakeCamera(amplitude: 6.0, numberOfShakes: 7, durationPerShake: 0.035)
            showPowerUpNotification(text: "REVIVED!", color: SKColor(red: 1.0, green: 0.3, blue: 0.45, alpha: 1.0))
        } else {
            triggerGameOver()
        }
    }

    /// Aktualisiert die Extra-Leben-Anzeige (nur sichtbar, wenn welche vorhanden).
    private func updateLivesLabel() {
        if extraLives > 0 {
            livesLabel.text = "LIVES: \(extraLives)"
            livesLabel.isHidden = (gameState != .playing)
        } else {
            livesLabel.isHidden = true
        }
    }
    
    // MARK: - Camera Shake
    
    /// Triggers a subtle procedural screen shake on the camera.
    private func shakeCamera(amplitude: CGFloat = 3.0, numberOfShakes: Int = 5, durationPerShake: TimeInterval = 0.03) {
        cameraNode.removeAction(forKey: "cameraShake")
        
        var actions: [SKAction] = []
        for _ in 0..<numberOfShakes {
            let dx = CGFloat.random(in: -amplitude...amplitude)
            let dy = CGFloat.random(in: -amplitude...amplitude)
            let move = SKAction.moveBy(x: dx, y: dy, duration: durationPerShake)
            let moveBack = move.reversed()
            actions.append(move)
            actions.append(moveBack)
        }
        
        // Reset to exact center
        actions.append(SKAction.move(to: .zero, duration: 0.0))
        
        cameraNode.run(SKAction.sequence(actions), withKey: "cameraShake")
    }
    
    // MARK: - Entity Spawning & Game Flow Management
    
    /// Spawns a new procedurally generated asteroid far away from the ship's center.
    public func spawnAsteroid() {
        let sizeClass = Asteroid.AsteroidSize.allCases.randomElement() ?? .large
        
        let config = currentConfig()
        let totalWeight = config.normalWeight + config.implodingWeight + config.wobblingWeight
        let isImploding: Bool
        let isWobbling: Bool
        if totalWeight > 0 {
            let rand = Int.random(in: 0..<totalWeight)
            if rand < config.normalWeight {
                isImploding = false
                isWobbling = false
            } else if rand < config.normalWeight + config.implodingWeight {
                isImploding = true
                isWobbling = false
            } else {
                isImploding = false
                isWobbling = true
            }
        } else {
            isImploding = false
            isWobbling = false
        }
        
        let asteroid = Asteroid(sizeClass: sizeClass, isImplodingType: isImploding, isWobblingType: isWobbling)
        
        // Fallback for zero screen size setup bounds
        let width = size.width > 100 ? size.width : 1024.0
        let height = size.height > 100 ? size.height : 768.0
        
        let halfWidth = width / 2
        let halfHeight = height / 2
        let diagonal = sqrt(halfWidth * halfWidth + halfHeight * halfHeight)
        let buffer: CGFloat = 80.0
        let spawnRadius = diagonal + buffer
        
        var spawnPos = CGPoint.zero
        var attempts = 0
        let minSafeDistance: CGFloat = 250.0
        
        repeat {
            let angle = CGFloat.random(in: 0..<(2.0 * .pi))
            let distance = spawnRadius + CGFloat.random(in: 0...50)
            spawnPos = CGPoint(
                x: distance * cos(angle),
                y: distance * sin(angle)
            )
            attempts += 1
            
            // Check if proposed position is in front cone of ship (45 degrees)
            let dirToAst = atan2(spawnPos.y - ship.position.y, spawnPos.x - ship.position.x)
            var diff = dirToAst - ship.zRotation
            while diff > .pi { diff -= 2.0 * .pi }
            while diff < -.pi { diff += 2.0 * .pi }
            let inFrontCone = abs(diff) < (.pi / 4.0)
            
            if distanceBetween(spawnPos, ship.position) >= minSafeDistance && !inFrontCone {
                break
            }
        } while attempts < 50
        
        if attempts >= 50 {
            // Fallback: Choose a random angle outside the front cone relative to the ship (between 45 and 315 degrees)
            let safeAngleOffset = CGFloat.random(in: (.pi / 4.0)...(7.0 * .pi / 4.0))
            let theta = ship.zRotation + safeAngleOffset
            let dx = cos(theta)
            let dy = sin(theta)
            
            // Ray-circle intersection to find the point on the spawnRadius circle
            let px = ship.position.x
            let py = ship.position.y
            let b = px * dx + py * dy
            let c = px * px + py * py - spawnRadius * spawnRadius
            let disc = b * b - c
            if disc >= 0 {
                let t = -b + sqrt(disc)
                spawnPos = CGPoint(x: px + t * dx, y: py + t * dy)
            } else {
                // Extreme fallback
                spawnPos = CGPoint(x: -spawnRadius, y: 0)
            }
        }
        
        asteroid.position = spawnPos
        
        // Scale speed with level configuration.
        // Der Asteroid fliegt von außerhalb des Bildschirms herein und wird auf einen
        // zufälligen Punkt im INNEREN Spielfeld-Bereich gezielt. So ist garantiert, dass seine
        // Bahn das sichtbare Rechteck durchquert (Mittelpunkt tritt ein) — er bleibt nicht durch
        // einen zu steilen Winkel am Bild vorbei hängen (siehe Asteroid.hasEnteredScreen).
        let targetX = CGFloat.random(in: -halfWidth * 0.6...halfWidth * 0.6)
        let targetY = CGFloat.random(in: -halfHeight * 0.6...halfHeight * 0.6)
        let movementAngle = atan2(targetY - asteroid.position.y, targetX - asteroid.position.x)
        let speed = CGFloat.random(in: 40.0...100.0) * config.speedMultiplier
        asteroid.velocity = CGPoint(
            x: speed * cos(movementAngle),
            y: speed * sin(movementAngle)
        )
        
        self.addChild(asteroid)
        self.activeAsteroids.append(asteroid)
    }
    
    private func showPowerUpNotification(text: String, color: SKColor) {
        powerUpNotificationLabel.text = text
        powerUpNotificationLabel.fontColor = color
        
        if ship.position.y > 60.0 {
            powerUpNotificationLabel.position = CGPoint(x: 0, y: -150)
        } else {
            powerUpNotificationLabel.position = CGPoint(x: 0, y: 150)
        }
        
        powerUpNotificationLabel.isHidden = false
        powerUpNotificationLabel.removeAllActions()
        powerUpNotificationLabel.xScale = 1.0
        powerUpNotificationLabel.yScale = 1.0
        powerUpNotificationLabel.alpha = 0.0
        
        let fadeIn = SKAction.fadeIn(withDuration: 0.1)
        let wait = SKAction.wait(forDuration: 1.5)
        let fadeOut = SKAction.fadeOut(withDuration: 0.3)
        let hide = SKAction.run { [weak self] in
            self?.powerUpNotificationLabel.isHidden = true
        }
        powerUpNotificationLabel.run(SKAction.sequence([fadeIn, wait, fadeOut, hide]))
    }
    
    private func detonateWobblingAsteroid(_ ast: Asteroid) -> [Asteroid] {
        SoundManager.shared.playExplosion()
        createImplosionExplosion(at: ast.position)
        shakeCamera(amplitude: 8.0, numberOfShakes: 8, durationPerShake: 0.04)
        
        if !ship.isHidden && distanceBetween(ast.position, ship.position) < 150.0 {
            lastDeathCause = .wobblingAsteroid
            damageShip()
        }
        
        var spawned: [Asteroid] = []
        let directions = [0.0, .pi / 2.0, .pi, 3.0 * .pi / 2.0]
        for angle in directions {
            let smallAst = Asteroid(sizeClass: .small)
            smallAst.position = ast.position
            // Splitter entstehen am Ort des Eltern-Asteroiden (im Bild) und nehmen dessen
            // Eintritts-Status mit, damit sie sofort normal am Kanten-Umlauf teilnehmen.
            smallAst.hasEnteredScreen = ast.hasEnteredScreen
            let speed: CGFloat = 180.0
            smallAst.velocity = CGPoint(x: speed * cos(angle), y: speed * sin(angle))
            self.addChild(smallAst)
            spawned.append(smallAst)
        }
        
        ast.removeFromParent()
        return spawned
    }
    
    /// Spawns two split children when an asteroid breaks.
    private func createSplitChildren(for parent: Asteroid) -> [Asteroid] {
        let childSize: Asteroid.AsteroidSize
        switch parent.sizeClass {
        case .large: childSize = .medium
        case .medium: childSize = .small
        case .small: return []
        }
        
        var children: [Asteroid] = []
        for i in 0..<2 {
            let child = Asteroid(sizeClass: childSize)
            child.position = parent.position
            // Splitter erben den Eintritts-Status des Eltern-Asteroiden (siehe wrapAround).
            child.hasEnteredScreen = parent.hasEnteredScreen

            // Angle parent velocity +/- 30 degrees, speed up by 1.35x
            let baseAngle = atan2(parent.velocity.y, parent.velocity.x)
            let deviation = (i == 0 ? 0.52 : -0.52) + CGFloat.random(in: -0.08...0.08)
            let newAngle = baseAngle + deviation
            let newSpeed = sqrt(parent.velocity.x * parent.velocity.x + parent.velocity.y * parent.velocity.y) * 1.35
            
            child.velocity = CGPoint(
                x: newSpeed * cos(newAngle),
                y: newSpeed * sin(newAngle)
            )
            
            self.addChild(child)
            children.append(child)
        }
        return children
    }
    
    /// Spawns a floating Power-Up capsule (gewichtete Typ-Auswahl).
    private func spawnPowerUp(at pos: CGPoint) {
        let powerUp = PowerUp(type: randomPowerUpType(), position: pos)
        self.addChild(powerUp)
        self.activePowerUps.append(powerUp)
    }

    /// Wählt einen Power-up-Typ gewichtet aus (Extra Life selten, Triple etwas häufiger).
    private func randomPowerUpType() -> PowerUpType {
        // Extra Life wird in höheren Levels häufiger (mehr Reserven für die härteren Level):
        // L1 = 5, L5 = 13, L10 = 23.
        let extraLifeWeight = 5 + max(0, currentLevel - 1) * 2
        let weights: [(PowerUpType, Int)] = [
            (.shield, 12), (.triple, 14), (.rapid, 10), (.option, 10), (.bomb, 8),
            (.beam, 9), (.rear, 10), (.compress, 9), (.extraLife, extraLifeWeight)
        ]
        let total = weights.reduce(0) { $0 + $1.1 }
        var r = Int.random(in: 0..<total)
        for (type, w) in weights {
            if r < w { return type }
            r -= w
        }
        return .triple
    }
    
    /// Handles collection updates for powerups.
    private func collectPowerUp(_ powerUp: PowerUp) {
        let now = ProcessInfo.processInfo.systemUptime
        let text: String
        let color: SKColor
        
        switch powerUp.type {
        case .shield:
            // Additiv bis Stufe 3 (jede Stufe fängt einen Treffer ab); endlos bis Treffer/Revive.
            ship.shieldLevel = min(3, ship.shieldLevel + 1)
            text = "SHIELD LEVEL \(ship.shieldLevel)!"
            color = SKColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0)
        case .triple:
            // Endlos (additiv) bis zum Revive – kein Timer.
            tripleShotEndTime = .greatestFiniteMagnitude
            text = "TRIPLE LASER!"
            color = SKColor(red: 1.0, green: 0.2, blue: 0.0, alpha: 1.0)
        case .rapid:
            rapidFireEndTime = now + 12.0
            text = "RAPID FIRE ACTIVE!"
            color = SKColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0)
        case .option:
            text = "OPTION DRONE ACQUIRED!"
            color = SKColor(red: 0.8, green: 0.0, blue: 1.0, alpha: 1.0)
            if options.count < 2 {
                let drone = OptionDrone()
                drone.position = ship.position
                self.addChild(drone)
                options.append(drone)
                applyCompressScale()   // neue Drohne an evtl. aktive Compress-Größe anpassen
            }
        case .bomb:
            detonateBomb()
            text = "SCREEN BOMB DETONATED!"
            color = SKColor(red: 1.0, green: 0.0, blue: 0.2, alpha: 1.0)
        case .beam:
            beamEndTime = now + beamDuration
            text = "LASER BEAM! (HOLD FIRE)"
            color = SKColor(red: 0.3, green: 1.0, blue: 0.3, alpha: 1.0)
        case .rear:
            rearLaserEndTime = now + rearLaserDuration
            text = "REAR LASER!"
            color = SKColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)
        case .compress:
            // Zwei Stufen: 1 = klein, 2 = winzig (ein Pixel) – Schiff und Beiboote. Timer (24s).
            compressLevel = min(2, compressLevel + 1)
            compressEndTime = now + compressDuration
            applyCompressScale()
            text = compressLevel >= 2 ? "COMPRESSED x2!" : "COMPRESSED!"
            color = SKColor(red: 0.9, green: 0.9, blue: 0.95, alpha: 1.0)
        case .extraLife:
            extraLives += 1
            updateLivesLabel()
            text = "EXTRA LIFE!"
            color = SKColor(red: 1.0, green: 0.3, blue: 0.45, alpha: 1.0)
        }

        showPowerUpNotification(text: text, color: color)
    }

    /// Setzt Schiff UND Beiboote auf die zur aktuellen Compress-Stufe passende Größe.
    private func applyCompressScale() {
        let scale: CGFloat
        switch compressLevel {
        case 2:  scale = compressLevel2Scale
        case 1:  scale = compressScale
        default: scale = 1.0
        }
        ship.setScale(scale)
        for drone in options { drone.setScale(scale) }
    }

    /// Beim Revive (Extra Life) gehen ALLE aktiven Power-ups verloren – Timer, Schild, Beiboote,
    /// Compress. Das Schiff kehrt auf Normalgröße zurück.
    private func resetPowerUpsOnRevive() {
        tripleShotEndTime = 0.0
        rapidFireEndTime = 0.0
        beamEndTime = 0.0
        rearLaserEndTime = 0.0
        compressEndTime = 0.0
        compressLevel = 0
        beamNode.isHidden = true
        ship.shieldLevel = 0
        for drone in options { drone.removeFromParent() }
        options.removeAll()
        applyCompressScale()   // -> Normalgröße
    }

    /// Zündet die Screen Bomb: legt einen einzelnen Schuss-Treffer auf JEDES Objekt am Bildschirm
    /// (alle Asteroiden + UFOs) – über dieselbe Treffer-Logik wie ein Laser. Plus Schockwelle,
    /// Kamera-Wackeln und Bomben-Sound; gegnerische Laser werden gelöscht.
    private func detonateBomb() {
        SoundManager.shared.playBomb()
        shakeCamera(amplitude: 11.0, numberOfShakes: 11, durationPerShake: 0.035)
        
        // Detonation shockwave visual
        let shockwave = SKShapeNode(circleOfRadius: 10.0)
        shockwave.strokeColor = .white
        shockwave.fillColor = .clear
        shockwave.lineWidth = 3.0
        shockwave.position = ship.position
        self.addChild(shockwave)
        
        let expand = SKAction.scale(to: 60.0, duration: 0.55)
        let fade = SKAction.fadeOut(withDuration: 0.55)
        let group = SKAction.group([expand, fade])
        let remove = SKAction.removeFromParent()
        shockwave.run(SKAction.sequence([group, remove]))
        
        // Jeden Asteroiden GENAU EINMAL treffen – exakt so, als würde ein Laserschuss ihn treffen
        // (dieselbe processPlayerHitOnAsteroid-Logik wie bei der Laser-Kollision). Damit verhalten
        // sich alle Typen konsistent: normale splitten, IMPLODIERENDE wachsen (kollabieren erst beim
        // 4. Treffer), WOBBELNDE geben Punkte und verschwinden. Commit wie bei der Laser-Kollision:
        // verbrauchte Asteroiden raus, neue Splitter rein.
        var hitAsteroids = Set<Asteroid>()
        var newAsteroids: [Asteroid] = []
        for asteroid in activeAsteroids {
            processPlayerHitOnAsteroid(asteroid, hitPosition: asteroid.position,
                                       hitAsteroids: &hitAsteroids, newAsteroids: &newAsteroids)
        }
        if !hitAsteroids.isEmpty {
            activeAsteroids = activeAsteroids.filter { asteroid in
                if hitAsteroids.contains(asteroid) {
                    asteroid.removeFromParent()
                    return false
                }
                return true
            }
        }
        activeAsteroids.append(contentsOf: newAsteroids)

        // Ebenso jedes UFO einmal treffen – ein Schuss zerstört ein UFO sofort (Punkte,
        // mögliche Power-up-Beute, Explosion). Gleiche Wirkung wie ein Laser-Treffer.
        for ufo in activeUFOs {
            self.score += ufo.pointValue
            if Double.random(in: 0...1) <= 0.20 {
                spawnPowerUp(at: ufo.position)
            }
            createShipExplosion(at: ufo.position)
            ufo.removeFromParent()
        }
        activeUFOs.removeAll()

        // Weltraumkatzen: ein Bomben-Treffer = ein direkter Schuss (eine Stufe Schaden), nicht
        // zwangsläufig tödlich (Katzen haben mehrere HP). Zerstörte geben Punkte + mögliche Beute.
        var survivingCats: [SpaceCat] = []
        for cat in activeCats {
            let destroyed = cat.registerHit()
            createShipExplosion(at: cat.position)
            if destroyed {
                self.score += cat.pointValue
                if Double.random(in: 0...1) <= 0.5 {
                    spawnPowerUp(at: cat.position)
                }
                cat.removeFromParent()
            } else {
                survivingCats.append(cat)
            }
        }
        activeCats = survivingCats

        scoreLabel.text = "SCORE: \(String(format: "%05d", score))"

        // Clear enemy lasers (UFO-Schüsse UND Katzen-Augenlaser)
        var remainingLasers: [Laser] = []
        for laser in activeLasers {
            if laser.type != .normal {
                laser.removeFromParent()
            } else {
                remainingLasers.append(laser)
            }
        }
        self.activeLasers = remainingLasers
    }

    /// Verarbeitet einen Spieler-Treffer auf einen Asteroiden (Implodierend wächst/kollabiert,
    /// Wobbling gibt Punkte, Normal splittet) inkl. Score, Power-up-Drop und Effekten.
    /// Wird von Laser-Treffern UND vom Laserbeam genutzt. Trägt verbrauchte Asteroiden in
    /// `hitAsteroids` und entstehende Splitter in `newAsteroids` ein (Commit erfolgt beim Aufrufer).
    private func processPlayerHitOnAsteroid(_ asteroid: Asteroid, hitPosition: CGPoint,
                                            hitAsteroids: inout Set<Asteroid>,
                                            newAsteroids: inout [Asteroid]) {
        let config = currentConfig()
        if asteroid.isImplodingType {
            asteroid.hitCount += 1
            let newScale = 1.0 + 0.4 * CGFloat(asteroid.hitCount)
            asteroid.xScale = newScale
            asteroid.yScale = newScale

            createExplosion(at: hitPosition, sizeClass: .small)

            if asteroid.hitCount >= 4 {
                triggerImplosionCollapse(asteroid: asteroid)
                hitAsteroids.insert(asteroid)
            }
        } else if asteroid.isWobblingType {
            hitAsteroids.insert(asteroid)
            self.score += 200
            scoreLabel.text = "SCORE: \(String(format: "%05d", score))"

            if Double.random(in: 0...1) <= config.powerUpChance * powerUpDropScale {
                spawnPowerUp(at: asteroid.position)
            }

            SoundManager.shared.playExplosion()
            createExplosion(at: asteroid.position, sizeClass: asteroid.sizeClass)
            shakeCamera(amplitude: 3.5, numberOfShakes: 4, durationPerShake: 0.02)
        } else {
            hitAsteroids.insert(asteroid)

            let points: Int
            switch asteroid.sizeClass {
            case .large:
                points = 20
                newAsteroids.append(contentsOf: createSplitChildren(for: asteroid))
            case .medium:
                points = 50
                newAsteroids.append(contentsOf: createSplitChildren(for: asteroid))
            case .small:
                points = 100
            }

            self.score += points
            scoreLabel.text = "SCORE: \(String(format: "%05d", score))"

            if Double.random(in: 0...1) <= config.powerUpChance * powerUpDropScale {
                spawnPowerUp(at: asteroid.position)
            }

            SoundManager.shared.playExplosion()
            createExplosion(at: asteroid.position, sizeClass: asteroid.sizeClass)
            shakeCamera(amplitude: asteroid.sizeClass == .large ? 3.0 : (asteroid.sizeClass == .medium ? 2.0 : 1.0), numberOfShakes: 4, durationPerShake: 0.02)
        }
    }

    /// Wickelt zeitbasierte Power-up-Effekte pro Frame ab: Compress nach Ablauf zurücksetzen und
    /// den Laserbeam betreiben, solange das Power-up läuft UND Space gehalten wird.
    private func updateTimedPowerUpEffects(currentTime: TimeInterval) {
        let now = ProcessInfo.processInfo.systemUptime

        // Compress: nach Ablauf Schiff (und Beiboote) wieder auf Originalgröße.
        if compressEndTime > 0 && now >= compressEndTime {
            compressEndTime = 0
            compressLevel = 0
            applyCompressScale()
        }

        // Laserbeam: während der Power-up-Dauer, solange gefeuert wird (Auto-Feuer oder Taste).
        if now < beamEndTime && (autoFire || isSpaceHeld) && !ship.isHidden {
            fireBeam(currentTime: currentTime)
        } else {
            beamNode.isHidden = true
        }
    }

    /// Baut den Laserbeam dieses Frames auf: eine Polylinie ab der Schiffsnase in Blickrichtung,
    /// halbe Bildschirmbreite lang, an den Bildschirmkanten toroidal umgebrochen (ragt also auf der
    /// gegenüberliegenden Seite wieder herein). Zerstört Asteroiden entlang des Strahls.
    private func fireBeam(currentTime: TimeInterval) {
        let halfW = (size.width > 100 ? size.width : 1024.0) / 2
        let halfH = (size.height > 100 ? size.height : 768.0) / 2
        let angle = ship.zRotation
        let dx = cos(angle)
        let dy = sin(angle)
        let beamLength = halfW * 2.0 * 0.5 // halbe Bildschirmbreite
        let step: CGFloat = 7.0
        let count = max(1, Int(beamLength / step))

        let tipX = ship.position.x + 18.0 * dx
        let tipY = ship.position.y + 18.0 * dy

        // Stützpunkte entlang der Richtung, jeweils toroidal in [-half, half] gewrappt.
        var points: [CGPoint] = []
        points.reserveCapacity(count + 1)
        for i in 0...count {
            let d = CGFloat(i) * step
            let wx = wrapCoordinate(tipX + dx * d, half: halfW)
            let wy = wrapCoordinate(tipY + dy * d, half: halfH)
            points.append(CGPoint(x: wx, y: wy))
        }

        // Visual aufbauen; bei einem Wrap-Sprung den Stift neu ansetzen.
        let path = CGMutablePath()
        path.move(to: points[0])
        for i in 1..<points.count {
            let prev = points[i - 1]
            let cur = points[i]
            if abs(cur.x - prev.x) > halfW || abs(cur.y - prev.y) > halfH {
                path.move(to: cur)
            } else {
                path.addLine(to: cur)
            }
        }
        beamNode.path = path
        beamNode.isHidden = false

        // Kollision: Asteroiden zerstören, die einen Strahl-Stützpunkt enthalten.
        var hitAsteroids = Set<Asteroid>()
        var newAsteroids: [Asteroid] = []
        for asteroid in activeAsteroids {
            if hitAsteroids.contains(asteroid) { continue }
            let poly = asteroid.getWorldVertices()
            var hit = false
            for p in points where CollisionHelper.isPointInPolygon(p, polygon: poly) {
                hit = true
                break
            }
            if hit {
                processPlayerHitOnAsteroid(asteroid, hitPosition: asteroid.position,
                                           hitAsteroids: &hitAsteroids, newAsteroids: &newAsteroids)
            }
        }
        if !hitAsteroids.isEmpty {
            activeAsteroids = activeAsteroids.filter { asteroid in
                if hitAsteroids.contains(asteroid) {
                    asteroid.removeFromParent()
                    return false
                }
                return true
            }
        }
        activeAsteroids.append(contentsOf: newAsteroids)

        // Der Strahl trifft auch die anderen Gegner – sonst kann man UFOs, Katzen und den Boss mit
        // dem Beam nicht erledigen (genau dieser Bug fiel beim Spielen auf). UFOs sterben sofort
        // (1 Treffer), Mehr-HP-Gegner (Katze/Boss) werden GEDROSSELT getroffen (lastBeamHitTime),
        // sonst würden sie beim Dauer-Strahl pro Frame Schaden nehmen und sofort zerschmelzen.
        let beamHitInterval: TimeInterval = 0.12
        var scoreChanged = false

        // UFOs: sofort zerstören (wie ein Laser-Treffer).
        var hitUFOs: [UFO] = []
        for ufo in activeUFOs {
            let poly = ufo.getWorldVertices()
            if points.contains(where: { CollisionHelper.isPointInPolygon($0, polygon: poly) }) {
                hitUFOs.append(ufo)
            }
        }
        for ufo in hitUFOs {
            self.score += ufo.pointValue
            scoreChanged = true
            if Double.random(in: 0...1) <= 0.20 { spawnPowerUp(at: ufo.position) }
            SoundManager.shared.playExplosion()
            createShipExplosion(at: ufo.position)
            ufo.removeFromParent()
        }
        if !hitUFOs.isEmpty { activeUFOs.removeAll { hitUFOs.contains($0) } }

        // Weltraumkatzen: gedrosselter Treffer pro Strahl-Kontakt.
        var deadCats: [SpaceCat] = []
        for cat in activeCats {
            let near = points.contains { distanceBetween($0, cat.position) <= cat.collisionRadius }
            guard near, currentTime - cat.lastBeamHitTime >= beamHitInterval else { continue }
            cat.lastBeamHitTime = currentTime
            let destroyed = cat.registerHit()
            createShipExplosion(at: cat.position)
            if destroyed {
                self.score += cat.pointValue
                scoreChanged = true
                if Double.random(in: 0...1) <= 0.5 { spawnPowerUp(at: cat.position) }
                deadCats.append(cat)
            }
        }
        if !deadCats.isEmpty {
            activeCats.removeAll { deadCats.contains($0) }
            deadCats.forEach { $0.removeFromParent() }
        }

        // Kopf-Boss: ebenfalls gedrosselt.
        if let head = activeHead {
            let near = points.contains { distanceBetween($0, head.position) <= head.collisionRadius }
            if near && currentTime - head.lastBeamHitTime >= beamHitInterval {
                head.lastBeamHitTime = currentTime
                let destroyed = head.registerHit()
                createShipExplosion(at: head.position)
                shakeCamera(amplitude: 5.0, numberOfShakes: 6, durationPerShake: 0.025)
                if destroyed {
                    self.score += 2000
                    scoreChanged = true
                    createShipExplosion(at: head.position)
                    shakeCamera(amplitude: 9.0, numberOfShakes: 10, durationPerShake: 0.03)
                    head.removeFromParent()
                    activeHead = nil
                }
            }
        }

        if scoreChanged { scoreLabel.text = "SCORE: \(String(format: "%05d", score))" }
    }

    /// Wrappt eine Koordinate toroidal in den Bereich [-half, half].
    private func wrapCoordinate(_ value: CGFloat, half: CGFloat) -> CGFloat {
        let full = half * 2.0
        var v = (value + half).truncatingRemainder(dividingBy: full)
        if v < 0 { v += full }
        return v - half
    }

    private func distanceBetween(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        return sqrt((p1.x - p2.x) * (p1.x - p2.x) + (p1.y - p2.y) * (p1.y - p2.y))
    }
    
    /// Triggers the Game Over state.
    private func triggerGameOver() {
        ship.isHidden = true
        ship.velocity = .zero
        ship.shieldLevel = 0
        
        // Stop key states and engine sound hum
        activeKeys.removeAll()
        SoundManager.shared.setThrustActive(false)
        SoundManager.shared.setChargingActive(false)
        
        // Play explosion sound effect
        SoundManager.shared.playExplosion()
        createShipExplosion(at: ship.position)
        
        // Trigger large camera shake
        shakeCamera(amplitude: 8.0, numberOfShakes: 8, durationPerShake: 0.04)
        
        // Check for high score
        if isNewHighScore(score: score) {
            transitionTo(.nameEntry)
        } else {
            transitionTo(.gameOver)
        }
    }
    
    /// Resets the game state and starts a fresh play session.
    public func restartGame() {
        transitionTo(.playing)
    }

    /// Startet ein frisches Spiel. Ohne `seed` wird einer ausgewürfelt; mit `seed` wird er
    /// übernommen — das ist der Einstiegspunkt für reproduzierbare Läufe (Replay/Tests).
    public func startNewGame(seed: UInt64? = nil) {
        pendingSeed = seed
        // Über den State-Wechsel auf .playing läuft der Fresh-Game-Pfad (setzt currentSeed/rng).
        // Aus dem laufenden Spiel heraus zuerst zurücksetzen, damit der else-Zweig greift.
        gameState = .startScreen
        transitionTo(.playing)
    }
    
    /// Transitions between game states, configuring visible overlay nodes and sound.
    public func transitionTo(_ newState: GameState) {
        let previousState = self.gameState
        self.gameState = newState
        
        // Hide all labels first
        titleLabel.isHidden = true
        startPromptLabel.isHidden = true
        instructionsLabel.isHidden = true
        scoreLabel.isHidden = true
        hiScoreLabel.isHidden = true
        nameEntryPromptLabel.isHidden = true
        nameEntryInputLabel.isHidden = true
        gameOverLabel.isHidden = true
        finalScoreLabel.isHidden = true
        restartLabel.isHidden = true
        highScoresTitleLabel.isHidden = true
        for label in highScoreLineLabels {
            label.isHidden = true
        }
        timerLabel.isHidden = true
        levelLabel.isHidden = true
        livesLabel.isHidden = true
        beamNode.isHidden = true
        levelSelectionLabel.isHidden = true
        modeSelectionLabel.isHidden = true
        settingsTitleLabel.isHidden = true
        settingsMusicLabel.isHidden = true
        settingsSfxLabel.isHidden = true
        settingsAutoFireLabel.isHidden = true
        settingsHintLabel.isHidden = true
        levelClearedLabel.isHidden = true
        prepareNextLevelLabel.isHidden = true
        
        glossaryContainer.isHidden = true
        glossaryStaticContainer.isHidden = true
        glossaryPromptLabel.isHidden = true
        quitPromptLabel.isHidden = true
        quitSubPromptLabel.isHidden = true
        
        // Stop sound engine hum
        SoundManager.shared.setThrustActive(false)
        SoundManager.shared.setChargingActive(false)
        SoundManager.shared.stopAllHeadSounds()
        headWasSpawning = false
        
        switch newState {
        case .startScreen:
            ship.isHidden = true
            ship.position = .zero
            ship.velocity = .zero
            ship.zRotation = 0.0
            ship.shieldLevel = 0
            
            titleLabel.isHidden = false
            startPromptLabel.isHidden = false
            instructionsLabel.isHidden = false
            // Highscore-Liste nur am Startbildschirm zeigen, wenn nicht ausgelagert (macOS).
            if showsHighScoresOnStartScreen {
                highScoresTitleLabel.isHidden = false
                updateHighScoreLabels()
                for label in highScoreLineLabels {
                    label.isHidden = false
                }
            }

            updateLevelSelectionLabel()
            levelSelectionLabel.isHidden = false

            updateModeSelectionLabel()
            modeSelectionLabel.isHidden = false

            // Musik-/SFX-Anzeige liegt jetzt in den Einstellungen (Startscreen bleibt ruhig).

            // Blink "PRESS SPACE TO START"
            startPromptLabel.removeAction(forKey: "blink")
            let fadeOut = SKAction.fadeOut(withDuration: 0.5)
            let fadeIn = SKAction.fadeIn(withDuration: 0.5)
            let blink = SKAction.sequence([fadeOut, fadeIn])
            startPromptLabel.run(SKAction.repeatForever(blink), withKey: "blink")
            
            // Show & Blink "PRESS I FOR GLOSSARY"
            glossaryPromptLabel.isHidden = false
            glossaryPromptLabel.removeAction(forKey: "blink")
            let glossaryFadeOut = SKAction.fadeOut(withDuration: 0.6)
            let glossaryFadeIn = SKAction.fadeIn(withDuration: 0.6)
            let glossaryBlink = SKAction.sequence([glossaryFadeOut, glossaryFadeIn])
            glossaryPromptLabel.run(SKAction.repeatForever(glossaryBlink), withKey: "blink")
            
            // iOS-Breitformat: kompaktes Startlayout (Titel sichtbar, Tastatur-Hinweise aus).
            if isCompactLayout { applyCompactStartScreenLayout() }

            // Clean active entities
            clearGameEntities()

            // Keep at least 3 asteroids drifting peacefully in the background
            while activeAsteroids.count < 3 {
                spawnAsteroid()
            }

        case .playing:
            if previousState == .quitConfirmation {
                // Resume game
                scoreLabel.isHidden = false
                hiScoreLabel.isHidden = false
                timerLabel.isHidden = false
                levelLabel.isHidden = false
                
                if isLevelClearing {
                    levelClearedLabel.isHidden = false
                    prepareNextLevelLabel.isHidden = false
                }
                
                ship.isHidden = false
                activeKeys.removeAll()
            } else {
                // Fresh game session

                // Seed für diesen Lauf festlegen: injizierten Seed übernehmen (Replay/Test) oder
                // einmalig einen neuen aus dem System-RNG würfeln. Danach speist sich ALLE
                // Spiel-Logik aus `rng` (deterministisch reproduzierbar bei gleichem Seed).
                currentSeed = pendingSeed ?? UInt64.random(in: UInt64.min...UInt64.max)
                pendingSeed = nil
                rng = GameRandom(seed: currentSeed)

                gameMode = selectedMode
                currentLevel = selectedStartLevel
                levelTimeRemaining = (currentLevel >= 10) ? 999999.0 : 60.0
                isLevelClearing = false
                playTime = 0.0
                isSpaceHeld = false
                invincibilityEndTime = 0.0
                tripleShotEndTime = 0.0
                rapidFireEndTime = 0.0
                beamEndTime = 0.0
                rearLaserEndTime = 0.0
                compressEndTime = 0.0
                compressLevel = 0
                extraLives = 0
                beamNode.isHidden = true
                updateLivesLabel()

                // Kopf-Boss pro Spiel neu auswürfeln/zurücksetzen.
                bossFirstTargetLevel = Int.random(in: 5...7)
                bossFirstDone = false
                bossLevel10Done = false
                nextBossTimeLevel10 = 0.0

                // Weltraumkatzen-Timer pro Spiel zurücksetzen.
                catTimerArmed = false
                nextCatTime = 0.0

                // Remove previous session objects
                clearGameEntities()

                // Reset ship
                ship.position = .zero
                ship.velocity = .zero
                ship.zRotation = 0.0
                ship.setScale(1.0)
                ship.isHidden = false
                ship.shieldLevel = 0
                ship.chargeLevel = 0.0
                
                // Reset scoring
                score = 0
                scoreLabel.text = "SCORE: 00000"
                
                let currentHi = highScores.first?.score ?? 0
                hiScoreLabel.text = "HI-SCORE: \(String(format: "%05d", currentHi))"
                
                scoreLabel.isHidden = false
                hiScoreLabel.isHidden = false
                
                if currentLevel >= 10 {
                    timerLabel.text = "TIME: SURVIVAL"
                } else {
                    timerLabel.text = "TIME: 01:00"
                }
                levelLabel.text = "LEVEL: \(currentLevel)"
                timerLabel.isHidden = false
                levelLabel.isHidden = false
                
                // Spawn initial asteroids
                let initialCount = max(3, currentConfig().maxAsteroids / 2)
                for _ in 0..<initialCount {
                    spawnAsteroid()
                }

                // Mad-Modus: Rotations-Scheduler beim nächsten Frame aufsetzen (dort liegt die
                // absolute Spielzeit vor) und das Sternenfeld über die Scheibe verteilen.
                fieldRotationPending = true
                scratchActive = false
                if gameMode == .madMeteoroids {
                    scatterStarsAcrossField()
                }
            }
            updateLivesLabel()

        case .nameEntry:
            ship.isHidden = true
            ship.velocity = .zero
            ship.shieldLevel = 0
            
            typedInitials = ""
            updateNameEntryInputLabel()
            
            nameEntryPromptLabel.isHidden = false
            nameEntryInputLabel.isHidden = false
            
        case .gameOver:
            ship.isHidden = true
            ship.velocity = .zero
            ship.shieldLevel = 0
            
            gameOverLabel.isHidden = false
            finalScoreLabel.text = "YOUR SCORE: \(score)"
            finalScoreLabel.isHidden = false
            restartLabel.isHidden = false
            highScoresTitleLabel.isHidden = false
            updateHighScoreLabels()
            for label in highScoreLineLabels {
                label.isHidden = false
            }
            if isCompactLayout {
                // iOS-Breitformat: alle Game-Over-Labels kompakt stapeln, Tastatur-Hinweis aus
                // (die Touch-Buttons REPLAY/ZURÜCK unten übernehmen das).
                applyCompactGameOverLayout()
            } else {
                // Desktop: "PRESS R TO REPLAY"-Hinweis blinken lassen.
                restartLabel.removeAction(forKey: "blink")
                let fadeOut = SKAction.fadeOut(withDuration: 0.5)
                let fadeIn = SKAction.fadeIn(withDuration: 0.5)
                let blink = SKAction.sequence([fadeOut, fadeIn])
                restartLabel.run(SKAction.repeatForever(blink), withKey: "blink")
            }
            
        case .quitConfirmation:
            quitPromptLabel.isHidden = false
            quitSubPromptLabel.isHidden = false
            
        case .glossary:
            ship.isHidden = true
            ship.velocity = .zero
            ship.shieldLevel = 0
            
            clearGameEntities()
            buildGlossary()
            glossaryContainer.position.y = glossaryScrollBottom
            glossaryContainer.isHidden = false
            glossaryStaticContainer.isHidden = false

        case .highScores:
            // Eigene Highscore-Ansicht (iOS): Liste mittig, Zurück über das Touch-Overlay.
            ship.isHidden = true
            ship.velocity = .zero
            ship.shieldLevel = 0

            clearGameEntities()

            highScoresTitleLabel.isHidden = false
            updateHighScoreLabels()
            for label in highScoreLineLabels {
                label.isHidden = false
            }
            if isCompactLayout { applyCompactHighScoresLayout() }

        case .settings:
            // Einstellungen: Schiff/Spielfeld weg, die Umschalt-Zeilen zeigen.
            ship.isHidden = true
            ship.velocity = .zero
            ship.shieldLevel = 0
            clearGameEntities()
            updateSettingsLabels()
            settingsTitleLabel.isHidden = false
            settingsMusicLabel.isHidden = false
            settingsSfxLabel.isHidden = false
            settingsAutoFireLabel.isHidden = false
            settingsHintLabel.isHidden = false
        }
    }

    /// iOS-Breitformat: positioniert die Startbildschirm-Labels passend zur aktuellen Bildhöhe
    /// und blendet die tastatur-zentrierten Hinweise aus (die Touch-Buttons übernehmen das).
    /// Idempotent – wird auch bei Größenänderung (didChangeSize) erneut aufgerufen.
    private func applyCompactStartScreenLayout() {
        let topY = size.height / 2
        titleLabel.fontSize = 40
        titleLabel.position = CGPoint(x: 0, y: topY - 44)
        modeSelectionLabel.position = CGPoint(x: 0, y: 24)
        levelSelectionLabel.position = CGPoint(x: 0, y: -24)
        startPromptLabel.isHidden = true
        instructionsLabel.isHidden = true
        glossaryPromptLabel.isHidden = true
    }

    /// iOS-Breitformat: Highscore-Liste kompakt unter einem Titel oben anordnen (eigene
    /// `.highScores`-Ansicht). Setzt die Schriftgrößen explizit zurück, falls zuvor das
    /// kompaktere Game-Over-Layout (kleinere Titel-Schrift) aktiv war – dieselben Label-Objekte.
    private func applyCompactHighScoresLayout() {
        let topY = size.height / 2
        highScoresTitleLabel.verticalAlignmentMode = .baseline
        highScoresTitleLabel.fontSize = 24
        highScoresTitleLabel.position = CGPoint(x: 0, y: topY - 50)
        let firstLineY = topY - 95
        for (i, label) in highScoreLineLabels.enumerated() {
            label.verticalAlignmentMode = .baseline
            label.fontSize = 16
            label.position = CGPoint(x: 0, y: firstLineY - CGFloat(i) * 28)
        }
    }

    /// iOS-Breitformat: kompakte Game-Over-Anordnung. Stapelt GAME OVER, Punktzahl, Highscore-Titel
    /// und -Liste platzsparend von oben nach unten – damit nichts überlappt (im Querformat ist
    /// wenig Höhe da). Blendet den Tastatur-Hinweis aus; die Touch-Buttons REPLAY/ZURÜCK am unteren
    /// Rand übernehmen diese Funktion. macOS nutzt unverändert das feste 4:3-Layout.
    private func applyCompactGameOverLayout() {
        let topY = size.height / 2
        // Alle Labels mittig ausrichten (verticalAlignmentMode .center): Bei der Default-Baseline
        // wächst der Text über die Position hinaus nach oben – dadurch ragte „GAME OVER" oben raus.
        // Mit .center ist die y-Position der Mittelpunkt, das Stapeln wird vorhersagbar.
        gameOverLabel.verticalAlignmentMode = .center
        gameOverLabel.fontSize = 32
        gameOverLabel.position = CGPoint(x: 0, y: topY - 30)
        finalScoreLabel.verticalAlignmentMode = .center
        finalScoreLabel.fontSize = 16
        finalScoreLabel.position = CGPoint(x: 0, y: topY - 62)
        highScoresTitleLabel.verticalAlignmentMode = .center
        highScoresTitleLabel.fontSize = 18
        highScoresTitleLabel.position = CGPoint(x: 0, y: topY - 92)
        let firstLineY = topY - 120
        for (i, label) in highScoreLineLabels.enumerated() {
            label.verticalAlignmentMode = .center
            label.fontSize = 15
            label.position = CGPoint(x: 0, y: firstLineY - CGFloat(i) * 24)
        }
        // Tastatur-Hinweis ("PRESS R …") ausblenden – auf iOS gibt es nur die Touch-Buttons.
        restartLabel.isHidden = true
    }

    /// iOS-Breitformat: aktualisiert das kompakte Menü-Layout nach einer Größenänderung.
    /// Wird aus der bestehenden didChangeSize-Override aufgerufen. Auf macOS (isCompactLayout
    /// = false) ein No-op – das 4:3-Layout bleibt unverändert.
    private func refreshCompactLayoutForCurrentState() {
        guard isCompactLayout else { return }
        switch gameState {
        case .startScreen: applyCompactStartScreenLayout()
        case .highScores: applyCompactHighScoresLayout()
        case .gameOver: applyCompactGameOverLayout()
        default: break
        }
    }
    
    private func updateLevelSelectionLabel() {
        let isCompleted = selectedStartLevel < maxLevelReached
        let starStr = isCompleted ? " ★" : ""
        // Auf Touch-Geräten übernehmen die Buttons die Auswahl -> Tastatur-Hinweis weglassen.
        let hint = isCompactLayout ? "" : "  (◀/▶ TO SELECT)"
        levelSelectionLabel.text = "STARTING LEVEL: \(selectedStartLevel)\(starStr)\(hint)"
    }

    private func updateModeSelectionLabel() {
        let modeName = (selectedMode == .madMeteoroids) ? "MAD METEOROIDS" : "ANCIENT ASTEROIDS"
        let hint = isCompactLayout ? "" : "  (▲/▼ TO SELECT)"
        modeSelectionLabel.text = "MODE: \(modeName)\(hint)"
    }

    /// Aktualisiert die drei Umschalt-Zeilen der Einstellungen mit dem aktuellen Stand.
    private func updateSettingsLabels() {
        settingsMusicLabel.text = "MUSIC: \(MusicPlayer.shared.isEnabled ? "ON" : "OFF")"
        settingsSfxLabel.text = "SFX STYLE: \(SoundManager.shared.useSampledSFX ? "SAMPLE" : "PROCEDURAL")"
        settingsAutoFireLabel.text = "AUTO-FIRE: \(autoFire ? "ON" : "OFF")"
        settingsHintLabel.text = isCompactLayout ? "TAP TO TOGGLE   X: BACK"
                                                 : "M: MUSIC   N: SFX   F: AUTO-FIRE   ESC: BACK"
    }
    
    private func shouldSpawnImploding() -> Bool {
        let config = configForLevel(currentLevel)
        let totalWeight = config.normalWeight + config.implodingWeight
        guard totalWeight > 0 else { return false }
        let rand = Int.random(in: 0..<totalWeight)
        return rand >= config.normalWeight
    }
    
    private func clearGameEntitiesKeepOptions() {
        for ast in activeAsteroids {
            ast.removeFromParent()
        }
        activeAsteroids.removeAll()
        
        for las in activeLasers {
            las.removeFromParent()
        }
        activeLasers.removeAll()
        
        for ufo in activeUFOs {
            ufo.removeFromParent()
        }
        activeUFOs.removeAll()
        
        for well in activeGravityWells {
            well.removeFromParent()
        }
        activeGravityWells.removeAll()

        activeHead?.removeFromParent()
        activeHead = nil
        SoundManager.shared.stopAllHeadSounds()
        headWasSpawning = false

        for cat in activeCats { cat.removeFromParent() }
        activeCats.removeAll()
    }

    private func triggerImplosionCollapse(asteroid: Asteroid) {
        SoundManager.shared.playImplosion()
        
        let collapseWell = GravityWell(strength: 1280000.0, lifetime: 4.0)
        collapseWell.position = asteroid.position
        self.addChild(collapseWell)
        self.activeGravityWells.append(collapseWell)
        
        createImplosionExplosion(at: asteroid.position)
        shakeCamera(amplitude: 6.0, numberOfShakes: 8, durationPerShake: 0.03)
        
        self.score += 250
        scoreLabel.text = "SCORE: \(String(format: "%05d", score))"
    }
    
    private func createImplosionExplosion(at pos: CGPoint) {
        let emitter = SKEmitterNode()
        emitter.particleTexture = makeExplosionParticleTexture()
        let count = 50
        emitter.numParticlesToEmit = count
        emitter.particleBirthRate = CGFloat(count) / 0.1
        emitter.particleLifetime = 0.8
        emitter.particleLifetimeRange = 0.2
        emitter.particleSpeed = 160.0
        emitter.particleSpeedRange = 60.0
        emitter.emissionAngle = 0.0
        emitter.emissionAngleRange = 2.0 * .pi
        
        emitter.particleScale = 1.2
        emitter.particleScaleRange = 0.4
        emitter.particleScaleSpeed = -1.2
        emitter.particleAlpha = 1.0
        emitter.particleAlphaSpeed = -1.3
        
        let colorSequence = SKKeyframeSequence(
            keyframeValues: [
                SKColor(red: 1.0, green: 0.3, blue: 0.8, alpha: 1.0),
                SKColor(red: 0.6, green: 0.1, blue: 1.0, alpha: 1.0),
                SKColor.darkGray,
                SKColor.clear
            ],
            times: [0.0, 0.4, 0.8, 1.0] as [NSNumber]
        )
        emitter.particleColorSequence = colorSequence
        emitter.particleColorBlendFactor = 1.0
        
        emitter.position = pos
        self.addChild(emitter)
        
        let wait = SKAction.wait(forDuration: 1.2)
        let remove = SKAction.removeFromParent()
        emitter.run(SKAction.sequence([wait, remove]))
    }
    
    // MARK: - Kopf-Boss

    /// Löst den Kopf-Boss bei Bedarf aus und schreitet ihn voran. Auftreten: zufällig einmal in
    /// Level 5–7, erneut in Level 10, danach in Level 10 alle 4–7 Minuten (es gibt kein weiteres Level).
    private func updateFloatingHead(currentTime: TimeInterval, deltaTime: TimeInterval) {
        // Auslösen (immer nur ein Kopf gleichzeitig). Nicht spawnen, solange eine Weltraumkatze
        // im Bild ist – Boss und Miniboss sollen sich nie überlagern. Verworfene Auslöser gehen
        // nicht verloren: Die Bedingung greift im nächsten Frame erneut, sobald die Katze weg ist.
        if activeHead == nil && activeCats.isEmpty && isSpawningEnabled {
            var spawn = false
            if !bossFirstDone && currentLevel >= bossFirstTargetLevel && currentLevel <= 7 {
                spawn = true
                bossFirstDone = true
            } else if currentLevel >= 10 {
                if !bossLevel10Done {
                    spawn = true
                    bossLevel10Done = true
                    nextBossTimeLevel10 = currentTime + Double.random(in: 240.0...420.0)
                } else if currentTime >= nextBossTimeLevel10 {
                    spawn = true
                    nextBossTimeLevel10 = currentTime + Double.random(in: 240.0...420.0)
                }
            }
            if spawn {
                let head = FloatingHead(screenSize: size)
                self.addChild(head)
                self.activeHead = head
            }
        }

        // Voranschreiten + UFO-Armada ausspeien.
        guard let head = activeHead else {
            if headWasSpawning { SoundManager.shared.stopBossHead() }
            headWasSpawning = false
            SoundManager.shared.stopAllHeadSounds()
            return
        }
        // Spieler-Schüsse als Ausweich-Bedrohungen übergeben (nur eigene, nicht die der Gegner).
        let threats: [(position: CGPoint, velocity: CGPoint)] = activeLasers
            .filter { $0.type == .normal }
            .map { ($0.position, $0.velocity) }
        let emit = head.update(deltaTime: deltaTime, shipPosition: ship.position, laserThreats: threats)
        if emit > 0 {
            let mouth = head.mouthWorldPosition
            for _ in 0..<emit {
                spawnArmadaUFO(at: mouth)
            }
        }
        if head.isFinished {
            head.removeFromParent()
            activeHead = nil
        }

        // Boss-Stimme während Mund-auf/Spawn: im Sample-Modus das lange Mooo-Sample (einmal, mit Fade),
        // sonst die prozedurale Stimme (kontinuierlich, openness-gesteuert).
        let spawningNow = (activeHead?.phase == .spawning)
        if SoundManager.shared.useSampledSFX {
            if spawningNow && !headWasSpawning {
                SoundManager.shared.playBossHead()       // Start beim Mund-Öffnen
            } else if !spawningNow && headWasSpawning {
                SoundManager.shared.stopBossHead()        // Spawn vorbei -> Sample stoppen
            }
            SoundManager.shared.setHeadVoice(active: false, openness: 0)
        } else {
            if let head = activeHead, head.phase == .spawning {
                SoundManager.shared.setHeadVoice(active: true, openness: Double(head.mouthOpenness))
            } else {
                SoundManager.shared.setHeadVoice(active: false, openness: 0)
            }
        }
        headWasSpawning = spawningNow
    }

    /// Erzeugt ein einzelnes Armada-UFO am Mund-Mittelpunkt (Mix groß/klein) – umgeht bewusst das
    /// normale 2er-Limit für reguläre UFO-Spawns.
    private func spawnArmadaUFO(at position: CGPoint) {
        let isSmall = Double.random(in: 0...1) < 0.4
        let ufo = UFO(isSmall: isSmall, startOnLeft: Bool.random(), screenSize: size)
        ufo.position = position
        self.addChild(ufo)
        self.activeUFOs.append(ufo)
    }

    /// Löst Weltraumkatzen aus und schreitet ihre KI voran. Eine Katze taucht ab `catFirstLevel` und
    /// nur dann auf, wenn gerade kein Kopf-Boss im Bild ist (sie sollen sich nicht überlagern).
    private func updateSpaceCats(currentTime: TimeInterval, deltaTime: TimeInterval) {
        // Auslösen (zeitgesteuert, gedeckelt).
        if isSpawningEnabled && activeHead == nil && currentLevel >= catFirstLevel
            && activeCats.count < maxActiveCats {
            if !catTimerArmed {
                catTimerArmed = true
                nextCatTime = currentTime + Double.random(in: 12.0...25.0)   // erster Auftritt
            } else if currentTime >= nextCatTime {
                spawnSpaceCat()
                nextCatTime = currentTime + Double.random(in: 35.0...60.0)   // Abstand danach
            }
        }

        guard !activeCats.isEmpty else { return }

        // Deckungsobjekte (große/mittlere Asteroiden) und Spielerschüsse einmal aufbereiten.
        let cover: [(position: CGPoint, radius: CGFloat)] = activeAsteroids
            .filter { $0.sizeClass != .small }
            .map { ($0.position, $0.sizeClass.rawValue) }
        let threats: [(position: CGPoint, velocity: CGPoint)] = activeLasers
            .filter { $0.type == .normal }
            .map { ($0.position, $0.velocity) }

        var survivors: [SpaceCat] = []
        for cat in activeCats {
            // Nur auf ein sichtbares Schiff feuern; canFire hält sonst den Ziel-Countdown an,
            // damit kein Angriffsversuch während Spielertod/Respawn verfällt.
            let shot = cat.update(deltaTime: deltaTime, shipPosition: ship.position,
                                  shipVelocity: ship.isHidden ? .zero : ship.velocity,
                                  coverObjects: cover, laserThreats: threats,
                                  canFire: !ship.isHidden)
            if let shot = shot {
                fireCatTwinLaser(shot)
                SoundManager.shared.playUfoSound()
            }
            if cat.isFinished {
                cat.removeFromParent()
            } else {
                survivors.append(cat)
            }
        }
        activeCats = survivors
    }

    /// Baut aus einem Doppelschuss zwei parallele `.catEye`-Laser (halbe Spielerschuss-Geschwindigkeit,
    /// längere Lebensdauer, damit sie aus Schuss-Distanz auch ankommen).
    private func fireCatTwinLaser(_ shot: SpaceCat.TwinLaserShot) {
        // Mündungsblitz am Auge (Mittelpunkt der beiden Ursprünge): verankert sichtbar, dass die
        // Schüsse aus dem Auge kommen. Bei der kleinen, schnellen Katze ist das sonst kaum erkennbar
        // (der Ursprung liegt korrekt am Auge, wirkt aber leicht wie „aus dem Körper").
        if shot.origins.count == 2 {
            let eye = CGPoint(x: (shot.origins[0].x + shot.origins[1].x) / 2.0,
                              y: (shot.origins[0].y + shot.origins[1].y) / 2.0)
            showCatMuzzleFlash(at: eye)
        }
        for origin in shot.origins {
            // Lebensdauer großzügig (3.0 s ≈ 900 px Reichweite bei 300 px/s), damit die Schüsse
            // das Ziel auch aus größerer Distanz noch erreichen, bevor sie ablaufen.
            let laser = Laser(position: origin, angle: shot.angle, type: .catEye,
                              speed: SpaceCat.laserSpeed, lifetime: 3.0)
            self.addChild(laser)
            self.activeLasers.append(laser)
        }
    }

    /// Kurzer oranger Mündungsblitz (glühendes Katzenauge) am Schuss-Ursprung.
    private func showCatMuzzleFlash(at pos: CGPoint) {
        let flash = SKShapeNode(circleOfRadius: 5.0)
        flash.position = pos
        flash.fillColor = SKColor(red: 1.0, green: 0.6, blue: 0.15, alpha: 0.9)
        flash.strokeColor = .clear
        flash.zPosition = 6
        addChild(flash)
        flash.run(.sequence([
            .group([.scale(to: 2.2, duration: 0.18), .fadeOut(withDuration: 0.18)]),
            .removeFromParent()
        ]))
    }

    private func spawnSpaceCat() {
        let cat = SpaceCat(screenSize: size, startOnLeft: Bool.random())
        self.addChild(cat)
        self.activeCats.append(cat)
    }

    private func clearGameEntities() {
        for ast in activeAsteroids {
            ast.removeFromParent()
        }
        activeAsteroids.removeAll()
        
        for las in activeLasers {
            las.removeFromParent()
        }
        activeLasers.removeAll()
        
        for ufo in activeUFOs {
            ufo.removeFromParent()
        }
        activeUFOs.removeAll()
        
        for well in activeGravityWells {
            well.removeFromParent()
        }
        activeGravityWells.removeAll()
        
        for p in activePowerUps {
            p.removeFromParent()
        }
        activePowerUps.removeAll()
        
        for drone in options {
            drone.removeFromParent()
        }
        options.removeAll()

        activeHead?.removeFromParent()
        activeHead = nil
        SoundManager.shared.stopAllHeadSounds()
        headWasSpawning = false

        for cat in activeCats { cat.removeFromParent() }
        activeCats.removeAll()
    }

    // MARK: - UI Configuration
    
    private func setupUIElements() {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        
        // Power-Up Notification HUD Alert
        powerUpNotificationLabel.fontSize = 24
        powerUpNotificationLabel.horizontalAlignmentMode = .center
        powerUpNotificationLabel.verticalAlignmentMode = .center
        powerUpNotificationLabel.zPosition = 100
        powerUpNotificationLabel.isHidden = true
        self.addChild(powerUpNotificationLabel)
        
        // Title screen
        titleLabel.text = "EXPLOIDS"
        titleLabel.fontName = RetroFont.pixel
        titleLabel.fontSize = 46
        titleLabel.fontColor = .cyan
        titleLabel.verticalAlignmentMode = .center
        titleLabel.position = CGPoint(x: 0, y: 250)
        titleLabel.zPosition = 100
        titleLabel.isHidden = true
        self.addChild(titleLabel)
        
        startPromptLabel.text = "PRESS SPACE TO START"
        startPromptLabel.fontSize = 20
        startPromptLabel.fontColor = .white
        startPromptLabel.position = CGPoint(x: 0, y: 170)
        startPromptLabel.zPosition = 100
        startPromptLabel.isHidden = true
        self.addChild(startPromptLabel)
        
        instructionsLabel.text = "W/▲: THRUST   A/D/◀/▶: ROTATE   SPACE: FIRE (HOLD = AUTO)   I: GLOSSARY"
        instructionsLabel.fontSize = 14
        instructionsLabel.fontColor = .lightGray
        instructionsLabel.position = CGPoint(x: 0, y: -270)
        instructionsLabel.zPosition = 100
        instructionsLabel.isHidden = true
        self.addChild(instructionsLabel)
        
        // HUD
        scoreLabel.fontSize = 20
        scoreLabel.fontColor = .cyan
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.position = CGPoint(x: -halfWidth + 20, y: halfHeight - 40)
        scoreLabel.zPosition = 100
        scoreLabel.isHidden = true
        self.addChild(scoreLabel)
        
        hiScoreLabel.fontSize = 20
        hiScoreLabel.fontColor = SKColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1.0)
        hiScoreLabel.horizontalAlignmentMode = .right
        hiScoreLabel.position = CGPoint(x: halfWidth - 20, y: halfHeight - 40)
        hiScoreLabel.zPosition = 100
        hiScoreLabel.isHidden = true
        self.addChild(hiScoreLabel)
        
        // Timer HUD
        timerLabel.fontSize = 20
        timerLabel.fontColor = .white
        timerLabel.horizontalAlignmentMode = .center
        timerLabel.position = CGPoint(x: 0, y: halfHeight - 40)
        timerLabel.zPosition = 100
        timerLabel.isHidden = true
        self.addChild(timerLabel)
        
        // Level HUD
        levelLabel.fontSize = 16
        levelLabel.fontColor = .cyan
        levelLabel.horizontalAlignmentMode = .left
        levelLabel.position = CGPoint(x: -halfWidth + 20, y: halfHeight - 65)
        levelLabel.zPosition = 100
        levelLabel.isHidden = true
        self.addChild(levelLabel)

        // Lives HUD (extra lives from the Extra-Life power-up)
        livesLabel.fontSize = 16
        livesLabel.fontColor = SKColor(red: 1.0, green: 0.3, blue: 0.45, alpha: 1.0)
        livesLabel.horizontalAlignmentMode = .left
        livesLabel.position = CGPoint(x: -halfWidth + 20, y: halfHeight - 90)
        livesLabel.zPosition = 100
        livesLabel.isHidden = true
        self.addChild(livesLabel)

        // Laserbeam-Visual (Polylinie, pro Frame neu aufgebaut; additives Leuchten)
        beamNode.strokeColor = SKColor(red: 0.4, green: 1.0, blue: 0.4, alpha: 0.95)
        beamNode.lineWidth = 7.0
        beamNode.lineCap = .round
        beamNode.blendMode = .add
        beamNode.zPosition = 50
        beamNode.isHidden = true
        self.addChild(beamNode)

        // Level Selection (Start Screen)
        levelSelectionLabel.fontSize = 20
        levelSelectionLabel.fontColor = SKColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1.0)
        levelSelectionLabel.horizontalAlignmentMode = .center
        levelSelectionLabel.position = CGPoint(x: 0, y: 78)
        levelSelectionLabel.zPosition = 100
        levelSelectionLabel.isHidden = true
        self.addChild(levelSelectionLabel)

        // Mode Selection (Start Screen)
        modeSelectionLabel.fontSize = 20
        modeSelectionLabel.fontColor = SKColor(red: 0.4, green: 1.0, blue: 0.6, alpha: 1.0)
        modeSelectionLabel.horizontalAlignmentMode = .center
        modeSelectionLabel.position = CGPoint(x: 0, y: 120)
        modeSelectionLabel.zPosition = 100
        modeSelectionLabel.isHidden = true
        self.addChild(modeSelectionLabel)

        // Einstellungen-Ansicht
        settingsTitleLabel.text = "SETTINGS"
        settingsTitleLabel.fontName = RetroFont.pixel
        settingsTitleLabel.fontSize = 32
        settingsTitleLabel.fontColor = SKColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1.0)
        settingsTitleLabel.position = CGPoint(x: 0, y: 120)
        settingsTitleLabel.zPosition = 100
        settingsTitleLabel.isHidden = true
        self.addChild(settingsTitleLabel)

        let settingsRows: [(SKLabelNode, CGFloat)] = [
            (settingsMusicLabel, 50), (settingsSfxLabel, 10), (settingsAutoFireLabel, -30)
        ]
        for (label, y) in settingsRows {
            label.fontSize = 22
            label.fontColor = .white
            label.horizontalAlignmentMode = .center
            label.position = CGPoint(x: 0, y: y)
            label.zPosition = 100
            label.isHidden = true
            self.addChild(label)
        }

        settingsHintLabel.fontSize = 16
        settingsHintLabel.fontColor = .lightGray
        settingsHintLabel.horizontalAlignmentMode = .center
        settingsHintLabel.position = CGPoint(x: 0, y: -110)
        settingsHintLabel.zPosition = 100
        settingsHintLabel.isHidden = true
        self.addChild(settingsHintLabel)
        updateSettingsLabels()

        // Level Cleared Overlay
        levelClearedLabel.fontSize = 40
        levelClearedLabel.fontColor = .green
        levelClearedLabel.horizontalAlignmentMode = .center
        levelClearedLabel.position = CGPoint(x: 0, y: 50)
        levelClearedLabel.zPosition = 100
        levelClearedLabel.isHidden = true
        self.addChild(levelClearedLabel)
        
        prepareNextLevelLabel.fontSize = 20
        prepareNextLevelLabel.fontColor = .white
        prepareNextLevelLabel.horizontalAlignmentMode = .center
        prepareNextLevelLabel.position = CGPoint(x: 0, y: 0)
        prepareNextLevelLabel.zPosition = 100
        prepareNextLevelLabel.isHidden = true
        self.addChild(prepareNextLevelLabel)
        
        // Name Entry
        nameEntryPromptLabel.text = "NEW HIGH SCORE!"
        nameEntryPromptLabel.fontSize = 36
        nameEntryPromptLabel.fontColor = SKColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1.0)
        nameEntryPromptLabel.position = CGPoint(x: 0, y: 100)
        nameEntryPromptLabel.zPosition = 100
        nameEntryPromptLabel.isHidden = true
        self.addChild(nameEntryPromptLabel)
        
        nameEntryInputLabel.fontSize = 24
        nameEntryInputLabel.fontColor = .white
        nameEntryInputLabel.position = CGPoint(x: 0, y: 30)
        nameEntryInputLabel.zPosition = 100
        nameEntryInputLabel.isHidden = true
        self.addChild(nameEntryInputLabel)
        
        // Game Over
        gameOverLabel.text = "GAME OVER"
        gameOverLabel.fontName = RetroFont.pixel
        gameOverLabel.fontSize = 40
        gameOverLabel.fontColor = .red
        gameOverLabel.position = CGPoint(x: 0, y: 180)
        gameOverLabel.zPosition = 100
        gameOverLabel.isHidden = true
        self.addChild(gameOverLabel)
        
        finalScoreLabel.fontSize = 20
        finalScoreLabel.fontColor = .white
        finalScoreLabel.position = CGPoint(x: 0, y: 120)
        finalScoreLabel.zPosition = 100
        finalScoreLabel.isHidden = true
        self.addChild(finalScoreLabel)
        
        restartLabel.text = "PRESS R TO REPLAY   ESC FOR TITLE"
        restartLabel.fontSize = 20
        restartLabel.fontColor = .white
        restartLabel.position = CGPoint(x: 0, y: -180)
        restartLabel.zPosition = 100
        restartLabel.isHidden = true
        self.addChild(restartLabel)
        
        // High scores
        highScoresTitleLabel.text = "HIGH SCORES"
        highScoresTitleLabel.fontSize = 24
        highScoresTitleLabel.fontColor = SKColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1.0)
        highScoresTitleLabel.position = CGPoint(x: 0, y: 35)
        highScoresTitleLabel.zPosition = 100
        highScoresTitleLabel.isHidden = true
        self.addChild(highScoresTitleLabel)

        for i in 0..<5 {
            let label = SKLabelNode(fontNamed: "Courier")
            label.fontSize = 20
            label.fontColor = .white
            label.position = CGPoint(x: 0, y: CGFloat(-8 - i * 30))
            label.zPosition = 100
            label.isHidden = true
            self.addChild(label)
            highScoreLineLabels.append(label)
        }
        
        // Quit confirmation labels
        quitPromptLabel.text = "QUIT GAME?"
        quitPromptLabel.fontSize = 40
        quitPromptLabel.fontColor = .red
        quitPromptLabel.position = CGPoint(x: 0, y: 50)
        quitPromptLabel.zPosition = 100
        quitPromptLabel.isHidden = true
        self.addChild(quitPromptLabel)
        
        quitSubPromptLabel.text = "PRESS Y TO CONFIRM / ESC TO CANCEL"
        quitSubPromptLabel.fontSize = 20
        quitSubPromptLabel.fontColor = .white
        quitSubPromptLabel.position = CGPoint(x: 0, y: -10)
        quitSubPromptLabel.zPosition = 100
        quitSubPromptLabel.isHidden = true
        self.addChild(quitSubPromptLabel)
        
        // Glossary container
        glossaryContainer.isHidden = true
        self.addChild(glossaryContainer)
        
        glossaryStaticContainer.isHidden = true
        self.addChild(glossaryStaticContainer)
        
        // Glossary prompt label on start screen
        glossaryPromptLabel.text = "PRESS I FOR GLOSSARY"
        glossaryPromptLabel.fontSize = 18
        glossaryPromptLabel.fontColor = .cyan
        glossaryPromptLabel.position = CGPoint(x: 0, y: -340)
        glossaryPromptLabel.zPosition = 100
        glossaryPromptLabel.isHidden = true
        self.addChild(glossaryPromptLabel)
    }
    
    private func updateHighScoreLabels() {
        for (index, label) in highScoreLineLabels.enumerated() {
            if index < highScores.count {
                let entry = highScores[index]
                let initials = entry.initials.padding(toLength: 3, withPad: " ", startingAt: 0)
                let baseText = "\(index + 1). \(initials)   \(entry.score)"
                if let dm = entry.deathMessage {
                    label.text = "\(baseText) - \(dm)"
                } else {
                    label.text = baseText
                }
            } else {
                label.text = "\(index + 1). ---       0"
            }
        }
    }
    
    private func updateNameEntryInputLabel() {
        var displayStr = "ENTER INITIALS: "
        for i in 0..<3 {
            if i < typedInitials.count {
                let idx = typedInitials.index(typedInitials.startIndex, offsetBy: i)
                displayStr += "\(typedInitials[idx]) "
            } else {
                displayStr += "_ "
            }
        }
        nameEntryInputLabel.text = displayStr.trimmingCharacters(in: .whitespaces)
    }
    
    public override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        scoreLabel.position = CGPoint(x: -halfWidth + 20, y: halfHeight - 40)
        hiScoreLabel.position = CGPoint(x: halfWidth - 20, y: halfHeight - 40)
        // iOS-Breitformat: kompaktes Menü-Layout nach Größenänderung neu setzen.
        refreshCompactLayoutForCurrentState()
    }
    
    // MARK: - High Score Storage
    
    /// Loads high scores from local storage. Made public for test framework reloading.
    public func loadHighScores() {
        maxLevelReached = UserDefaults.standard.integer(forKey: "exploids_max_level_reached")
        if maxLevelReached < 1 {
            maxLevelReached = 1
        }
        
        guard let data = UserDefaults.standard.data(forKey: "exploids_high_scores") else {
            // Default high scores. Mit Todesmeldung, damit sie genauso formatiert sind wie eigene
            // Einträge (Format-Stil siehe recordHighScore).
            self.highScores = [
                HighScore(initials: "DM ", score: 10000, date: Date(), deathMessage: "Crushed in a black hole on Level 9"),
                HighScore(initials: "JAB", score: 7500, date: Date(), deathMessage: "Vaporized by UFO laser on Level 7"),
                HighScore(initials: "HAL", score: 5000, date: Date(), deathMessage: "Blown to bits by wobbling bomb on Level 6"),
                HighScore(initials: "MAC", score: 2500, date: Date(), deathMessage: "Rammed by an alien UFO on Level 4"),
                HighScore(initials: "C64", score: 1000, date: Date(), deathMessage: "Hull breach (large asteroid) on Level 2")
            ]
            return
        }
        
        do {
            self.highScores = try JSONDecoder().decode([HighScore].self, from: data)
        } catch {
            print("Failed to decode high scores: \(error)")
            self.highScores = []
        }
    }
    
    private func saveHighScores() {
        do {
            let data = try JSONEncoder().encode(self.highScores)
            UserDefaults.standard.set(data, forKey: "exploids_high_scores")
        } catch {
            print("Failed to encode high scores: \(error)")
        }
    }
    
    public func isNewHighScore(score: Int) -> Bool {
        if highScores.count < 5 { return true }
        return score > (highScores.last?.score ?? 0)
    }
    
    private func recordHighScore(initials: String, score: Int) {
        let message: String
        switch lastDeathCause {
        case .largeAsteroid:
            message = "Hull breach (large asteroid) on Level \(currentLevel)"
        case .mediumAsteroid:
            message = "Hull breach (medium asteroid) on Level \(currentLevel)"
        case .smallAsteroid:
            message = "Hull breach (small asteroid) on Level \(currentLevel)"
        case .wobblingAsteroid:
            message = "Blown to bits by wobbling bomb on Level \(currentLevel)"
        case .ufo:
            message = "Rammed by an alien UFO on Level \(currentLevel)"
        case .ufoLaser:
            message = "Vaporized by UFO laser on Level \(currentLevel)"
        case .gravityWell:
            message = "Crushed in a black hole on Level \(currentLevel)"
        case .bossHead:
            message = "Devoured by the floating idol on Level \(currentLevel)"
        case .spaceCat:
            message = "Pounced by a space cat on Level \(currentLevel)"
        case .spaceCatLaser:
            message = "Zapped by space cat eye-beams on Level \(currentLevel)"
        }
        
        let newEntry = HighScore(initials: initials, score: score, date: Date(), deathMessage: message)
        highScores.append(newEntry)
        highScores.sort { $0.score > $1.score }
        if highScores.count > 5 {
            highScores = Array(highScores.prefix(5))
        }
        saveHighScores()
    }
    
    // MARK: - Mad Meteoroids Field Rotation

    /// Dreht einen Punkt um den Ursprung (Bildschirmmitte) um den Winkel `a` (Radiant).
    private func rotatedAroundOrigin(_ p: CGPoint, by a: CGFloat) -> CGPoint {
        if a == 0 { return p }
        let c = cos(a)
        let s = sin(a)
        return CGPoint(x: p.x * c - p.y * s, y: p.x * s + p.y * c)
    }

    /// Radius des kreisförmigen Spielfelds im Mad-Modus. Objekte jenseits dieses Radius werden auf
    /// die diametral gegenüberliegende Seite umgesetzt (rotations-invariantes Wrapping).
    private func madFieldRadius() -> CGFloat {
        let halfWidth = (size.width > 100 ? size.width : 1024.0) / 2
        let halfHeight = (size.height > 100 ? size.height : 768.0) / 2
        return sqrt(halfWidth * halfWidth + halfHeight * halfHeight) + 100.0
    }

    /// Setzt einen Punkt, der den Feldradius verlassen hat, auf die gegenüberliegende Seite knapp
    /// innerhalb des Radius (kreisförmiges Wrapping). Punkte innerhalb bleiben unverändert.
    private func circularWrapped(_ p: CGPoint, radius r: CGFloat) -> CGPoint {
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
    private func configureFieldRotationForLevel(currentTime: TimeInterval) {
        scratchActive = false
        scratchElapsed = 0.0

        guard gameMode == .madMeteoroids else {
            fieldAngularVelocity = 0.0
            nextDirectionChangeTime = .greatestFiniteMagnitude
            return
        }

        let speed = fieldSpeedRadPerSec(forLevel: currentLevel)
        fieldRotationDirection = Bool.random() ? 1.0 : -1.0
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
    private func updateFieldRotation(deltaTime: TimeInterval, currentTime: TimeInterval) {
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
                if Double.random(in: 0...1) < MadRotation.scratchChance {
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
    private func applyFieldRotation(toAsteroid ast: Asteroid) {
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

    /// Verteilt die Sterne gleichmäßig über die kreisförmige Spielfeld-Scheibe. Nötig beim Start
    /// des Mad-Modus, damit das rotierende Sternenfeld keine leeren Ecken zeigt.
    private func scatterStarsAcrossField() {
        let r = madFieldRadius()
        for star in stars {
            let angle = CGFloat.random(in: 0..<(2.0 * .pi))
            // sqrt für flächengleiche Verteilung in der Scheibe (sonst Häufung in der Mitte).
            let radius = r * sqrt(CGFloat.random(in: 0...1))
            star.position = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
        }
    }

    // MARK: - Starfield Helpers

    private func setupStarfield() {
        let layers: [(count: Int, size: CGFloat, color: SKColor, parallax: CGFloat)] = [
            (count: 40, size: 1.0, color: SKColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 1.0), parallax: 0.02),
            (count: 25, size: 2.0, color: SKColor(red: 0.4, green: 0.45, blue: 0.55, alpha: 1.0), parallax: 0.05),
            (count: 15, size: 3.0, color: SKColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0), parallax: 0.1)
        ]
        
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        
        for layer in layers {
            for _ in 0..<layer.count {
                let star = StarNode(color: layer.color, size: CGSize(width: layer.size, height: layer.size))
                star.parallaxFactor = layer.parallax
                let x = CGFloat.random(in: -halfWidth...halfWidth)
                let y = CGFloat.random(in: -halfHeight...halfHeight)
                star.position = CGPoint(x: x, y: y)
                star.zPosition = -10.0
                self.addChild(star)
                self.stars.append(star)
            }
        }
    }
    
    private func updateStars(deltaTime: TimeInterval) {
        let dt = CGFloat(deltaTime)
        let shipVel: CGPoint
        
        if gameState == .playing {
            shipVel = ship.velocity
        } else {
            // Gentle background drift on menu/death screens
            shipVel = CGPoint(x: 10.0, y: -5.0)
        }
        
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        
        let madFieldActive = fieldDeltaThisFrame != 0
        let fieldRadius = madFieldActive ? madFieldRadius() : 0

        for star in stars {
            star.position.x -= shipVel.x * star.parallaxFactor * dt
            star.position.y -= shipVel.y * star.parallaxFactor * dt

            if madFieldActive {
                // Mad-Modus: Stern um die Bildmitte mitdrehen und kreisförmig wrappen.
                star.position = rotatedAroundOrigin(star.position, by: fieldDeltaThisFrame)
                star.position = circularWrapped(star.position, radius: fieldRadius)
                continue
            }

            if star.position.x < -halfWidth {
                star.position.x += size.width
            } else if star.position.x > halfWidth {
                star.position.x -= size.width
            }

            if star.position.y < -halfHeight {
                star.position.y += size.height
            } else if star.position.y > halfHeight {
                star.position.y -= size.height
            }
        }
    }
    
    // MARK: - Visual Particle Explosions
    
    /// Spawns a procedural retro explosion burst using an emitter.
    private func createExplosion(at position: CGPoint, sizeClass: Asteroid.AsteroidSize) {
        let emitter = SKEmitterNode()
        emitter.particleTexture = makeExplosionParticleTexture()
        
        let particleCount: Int
        let speed: CGFloat
        switch sizeClass {
        case .large:
            particleCount = 40
            speed = 140.0
        case .medium:
            particleCount = 25
            speed = 190.0
        case .small:
            particleCount = 14
            speed = 240.0
        }
        
        emitter.numParticlesToEmit = particleCount
        emitter.particleBirthRate = CGFloat(particleCount) / 0.1
        emitter.particleLifetime = 0.65
        emitter.particleLifetimeRange = 0.25
        emitter.particleSpeed = speed
        emitter.particleSpeedRange = speed * 0.45
        emitter.emissionAngle = 0.0
        emitter.emissionAngleRange = 2.0 * .pi // full circle
        
        emitter.particleScale = 1.0
        emitter.particleScaleRange = 0.4
        emitter.particleScaleSpeed = -1.5
        emitter.particleAlpha = 1.0
        emitter.particleAlphaSpeed = -1.6
        
        let colorSequence = SKKeyframeSequence(
            keyframeValues: [SKColor.white, SKColor.lightGray, SKColor.darkGray, SKColor.clear],
            times: [0.0, 0.35, 0.75, 1.0] as [NSNumber]
        )
        emitter.particleColorSequence = colorSequence
        emitter.particleColorBlendFactor = 1.0
        
        emitter.position = position
        self.addChild(emitter)
        
        let wait = SKAction.wait(forDuration: 1.0)
        let remove = SKAction.removeFromParent()
        emitter.run(SKAction.sequence([wait, remove]))
    }
    
    /// Spawns a large cyan procedural particle explosion on ship/UFO destruction.
    private func createShipExplosion(at position: CGPoint) {
        let emitter = SKEmitterNode()
        emitter.particleTexture = makeExplosionParticleTexture()
        
        let particleCount = 60
        emitter.numParticlesToEmit = particleCount
        emitter.particleBirthRate = CGFloat(particleCount) / 0.1
        emitter.particleLifetime = 1.1
        emitter.particleLifetimeRange = 0.3
        emitter.particleSpeed = 210.0
        emitter.particleSpeedRange = 90.0
        emitter.emissionAngle = 0.0
        emitter.emissionAngleRange = 2.0 * .pi
        
        emitter.particleScale = 1.2
        emitter.particleScaleRange = 0.5
        emitter.particleScaleSpeed = -1.0
        emitter.particleAlpha = 1.0
        emitter.particleAlphaSpeed = -0.85
        
        let colorSequence = SKKeyframeSequence(
            keyframeValues: [SKColor.cyan, SKColor.blue, SKColor.darkGray, SKColor.clear],
            times: [0.0, 0.4, 0.8, 1.0] as [NSNumber]
        )
        emitter.particleColorSequence = colorSequence
        emitter.particleColorBlendFactor = 1.0
        
        emitter.position = position
        self.addChild(emitter)
        
        let wait = SKAction.wait(forDuration: 1.8)
        let remove = SKAction.removeFromParent()
        emitter.run(SKAction.sequence([wait, remove]))
    }
    
    private func makeExplosionParticleTexture() -> SKTexture {
        let size = CGSize(width: 3.5, height: 3.5)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil,
                                width: Int(size.width),
                                height: Int(size.height),
                                bitsPerComponent: 8,
                                bytesPerRow: 0,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(SKColor.white.cgColor)
        context.fillEllipse(in: CGRect(origin: .zero, size: size))
        let cgImage = context.makeImage()!
        return SKTexture(cgImage: cgImage)
    }
    
    // MARK: - Input Simulation Helpers
    
    /// Simulates pressing a key down (useful for headless testing and the iOS touch/controller layer).
    public func simulateKeyDown(keyCode: UInt16) {
        handleKeyDown(keyCode: keyCode, characters: nil, charactersIgnoringModifiers: nil, isCommandDown: false)
    }

    /// Simulates releasing a key (useful for headless testing and the iOS touch/controller layer).
    public func simulateKeyUp(keyCode: UInt16) {
        handleKeyUp(keyCode: keyCode)
    }

    /// Simulates typing a letter (useful for initials entry testing).
    public func simulateTypeCharacter(_ char: String) {
        handleKeyDown(keyCode: 0, characters: char, charactersIgnoringModifiers: char, isCommandDown: false)
    }

    /// For testing: erzeugt sofort einen Kopf-Boss, hängt ihn ein und gibt ihn zurück.
    @discardableResult
    public func spawnFloatingHeadForTesting() -> FloatingHead {
        let head = FloatingHead(screenSize: size)
        self.addChild(head)
        self.activeHead = head
        return head
    }

    /// For testing: erzeugt sofort eine Weltraumkatze, hängt sie ein und gibt sie zurück.
    @discardableResult
    public func spawnSpaceCatForTesting(startOnLeft: Bool = true) -> SpaceCat {
        let cat = SpaceCat(screenSize: size, startOnLeft: startOnLeft)
        self.addChild(cat)
        self.activeCats.append(cat)
        return cat
    }
    
    /// For testing: directly adds an asteroid.
    public func addAsteroidForTesting(_ asteroid: Asteroid) {
        self.addChild(asteroid)
        self.activeAsteroids.append(asteroid)
    }

    /// For testing: selects the game mode used by the next fresh game session.
    public func setGameModeForTesting(_ mode: GameMode) {
        self.selectedMode = mode
    }

    /// For testing: the effective spawn config for the current mode and level.
    public func currentConfigForTesting() -> LevelSpawnConfig {
        return currentConfig()
    }
    
    /// For testing: directly adds a laser.
    public func addLaserForTesting(_ laser: Laser) {
        self.addChild(laser)
        self.activeLasers.append(laser)
    }
    
    /// For testing: directly adds a power-up.
    public func addPowerUpForTesting(_ powerUp: PowerUp) {
        self.addChild(powerUp)
        self.activePowerUps.append(powerUp)
    }

    /// For testing: fügt ein UFO an einer Position hinzu (z.B. um Bomben-Treffer zu provozieren).
    @discardableResult
    public func addUFOForTesting(at position: CGPoint) -> UFO {
        let ufo = UFO(isSmall: false, startOnLeft: true, screenSize: size)
        ufo.position = position
        self.addChild(ufo)
        self.activeUFOs.append(ufo)
        return ufo
    }

    /// For testing: Anzahl der PowerUp-Knoten im Szenengraph (zur Erkennung verwaister Nodes).
    public var powerUpNodeCountInSceneForTesting: Int {
        return self.children.compactMap { $0 as? PowerUp }.count
    }

    /// For testing: prüft, dass für JEDEN Entity-Typ die Anzahl der Knoten im Szenengraph exakt der
    /// Länge des zugehörigen Tracking-Arrays entspricht. Schlägt fehl, sobald ein Objekt im
    /// Szenengraph hängt, das nicht (mehr) getrackt wird (verwaister Node), oder umgekehrt. Das ist
    /// die zentrale „nichts bleibt unzerstörbar/uneinsammelbar hängen"-Invariante.
    public var entityTrackingConsistentForTesting: Bool {
        func count<T>(_ type: T.Type) -> Int { children.compactMap { $0 as? T }.count }
        return count(Asteroid.self) == activeAsteroids.count
            && count(UFO.self)      == activeUFOs.count
            && count(SpaceCat.self) == activeCats.count
            && count(PowerUp.self)  == activePowerUps.count
            && count(Laser.self)    == activeLasers.count
    }
    
    /// For testing: returns the triple shot end time.
    public var tripleShotEndTimeForTesting: TimeInterval {
        return tripleShotEndTime
    }
    
    /// For testing: returns the rapid fire end time.
    public var rapidFireEndTimeForTesting: TimeInterval {
        return rapidFireEndTime
    }
    
    /// For testing: returns the glossary container Y position.
    public var glossaryContainerYForTesting: CGFloat {
        return glossaryContainer.position.y
    }
    
    /// For testing: sets the active powerups end times.
    public func setPowerUpTimersForTesting(triple: TimeInterval, rapid: TimeInterval) {
        self.tripleShotEndTime = triple
        self.rapidFireEndTime = rapid
    }
    
    /// For testing: directly adds score.
    public func addScoreForTesting(_ amount: Int) {
        self.score += amount
    }
    
    /// For testing: sets the level time remaining.
    public func setLevelTimeRemainingForTesting(_ time: TimeInterval) {
        self.levelTimeRemaining = time
    }
    
    /// For testing: clears all active asteroids and lasers.
    public func clearAllEntitiesForTesting() {
        clearGameEntities()
    }
    
    /// For testing: directly spawns a power-up.
    public func spawnPowerUpForTesting(type: PowerUpType, position: CGPoint) {
        let p = PowerUp(type: type, position: position)
        self.addChild(p)
        self.activePowerUps.append(p)
    }

    /// For testing: directly applies a power-up's effect (as if collected).
    public func collectPowerUpForTesting(type: PowerUpType) {
        collectPowerUp(PowerUp(type: type, position: .zero))
    }

    /// For testing: applies one fatal hit to the ship (shield/extra-life/game-over path).
    public func damageShipForTesting() {
        damageShip()
    }

    /// For testing: fires the player's primary weapon once.
    public func fireLaserForTesting() {
        fireLaser()
    }

    /// For testing: runs one frame of the laser beam (bypasses the hold-to-fire gating).
    public func fireBeamForTesting(currentTime: TimeInterval = 0.0) {
        fireBeam(currentTime: currentTime)
    }

    /// For testing: number of stored extra lives.
    public var extraLivesForTesting: Int { extraLives }
    
    /// For testing: directly spawns a UFO.
    public func spawnUFOForTesting(isSmall: Bool, startOnLeft: Bool) {
        let u = UFO(isSmall: isSmall, startOnLeft: startOnLeft, screenSize: size)
        self.addChild(u)
        self.activeUFOs.append(u)
    }
    
    /// For testing: directly spawns a Gravity Well.
    public func spawnGravityWellForTesting(position: CGPoint) {
        let well = GravityWell()
        well.position = position
        self.addChild(well)
        self.activeGravityWells.append(well)
    }
    
    // MARK: - Glossary
    
    private func addGlossaryItem(
        graphic: SKNode,
        title: String,
        titleColor: SKColor,
        description: String,
        yPosition: CGFloat
    ) {
        let itemContainer = SKNode()
        itemContainer.position = CGPoint(x: 0, y: yPosition)
        
        graphic.position = CGPoint(x: -280, y: 0)
        itemContainer.addChild(graphic)
        
        if !(graphic is GravityWell) {
            let rotateAction = SKAction.repeatForever(SKAction.rotate(byAngle: .pi, duration: 4.0))
            graphic.run(rotateAction)
        } else {
            let rotateAction = SKAction.repeatForever(SKAction.rotate(byAngle: -.pi, duration: 6.0))
            graphic.run(rotateAction)
        }
        
        let titleNode = SKLabelNode(fontNamed: "Courier-Bold")
        titleNode.text = title
        titleNode.fontSize = 18
        titleNode.fontColor = titleColor
        titleNode.horizontalAlignmentMode = .left
        titleNode.position = CGPoint(x: -200, y: 10)
        itemContainer.addChild(titleNode)
        
        let descNode = SKLabelNode(fontNamed: "Courier")
        descNode.text = description
        descNode.fontSize = 14
        descNode.fontColor = .lightGray
        descNode.horizontalAlignmentMode = .left
        descNode.position = CGPoint(x: -200, y: -15)
        itemContainer.addChild(descNode)
        
        glossaryContainer.addChild(itemContainer)
    }
    
    private func buildGlossary() {
        glossaryContainer.removeAllChildren()
        glossaryStaticContainer.removeAllChildren()
        
        // Statischer Titel/Footer liegen ÜBER der durchscrollenden Liste, mit einem schwarzen
        // Streifen darunter, damit der scrollende Text dahinter sauber verschwindet.
        glossaryStaticContainer.zPosition = 200

        // Add static Title (mit dunklem Hintergrundstreifen)
        let titleStrip = SKShapeNode(rect: CGRect(x: -1000, y: 258, width: 2000, height: 70))
        titleStrip.fillColor = .black
        titleStrip.strokeColor = .clear
        titleStrip.zPosition = 0
        glossaryStaticContainer.addChild(titleStrip)

        let titleNode = SKLabelNode(fontNamed: "Courier-Bold")
        titleNode.text = "GLOSSARY"
        titleNode.fontSize = 32
        titleNode.fontColor = .cyan
        titleNode.position = CGPoint(x: 0, y: 280)
        titleNode.zPosition = 1
        glossaryStaticContainer.addChild(titleNode)

        // Add static footer instruction (ebenfalls mit dunklem Streifen)
        let footerStrip = SKShapeNode(rect: CGRect(x: -1000, y: -326, width: 2000, height: 42))
        footerStrip.fillColor = .black
        footerStrip.strokeColor = .clear
        footerStrip.zPosition = 0
        glossaryStaticContainer.addChild(footerStrip)

        let footerNode = SKLabelNode(fontNamed: "Courier")
        footerNode.text = "W/S/▲/▼ TO SCROLL  •  ESC/I TO RETURN TO TITLE"
        footerNode.fontSize = 16
        footerNode.fontColor = .white
        footerNode.position = CGPoint(x: 0, y: -310)
        footerNode.zPosition = 1
        glossaryStaticContainer.addChild(footerNode)
        
        // Blink the footer instruction
        let fadeOut = SKAction.fadeOut(withDuration: 0.8)
        let fadeIn = SKAction.fadeIn(withDuration: 0.8)
        let blink = SKAction.sequence([fadeOut, fadeIn])
        footerNode.run(SKAction.repeatForever(blink))
        
        // Item 1: Player Ship
        let shipNode = Ship()
        shipNode.xScale = 1.3
        shipNode.yScale = 1.3
        shipNode.isHidden = false
        addGlossaryItem(
            graphic: shipNode,
            title: "PLAYER SHIP",
            titleColor: .cyan,
            description: "Your vector fighter. Rotate: A/D/◀/▶, Thrust: W/▲, Fire: SPACE.",
            yPosition: 150
        )
        
        // Item 2: Option Drone
        let droneNode = OptionDrone()
        droneNode.xScale = 2.0
        droneNode.yScale = 2.0
        addGlossaryItem(
            graphic: droneNode,
            title: "OPTION DRONE",
            titleColor: SKColor(red: 0.8, green: 0.0, blue: 1.0, alpha: 1.0),
            description: "Collect 'O' power-up. Follows you and fires helper lasers.",
            yPosition: 50
        )
        
        // Item 3: Normal Asteroid
        let normalAst = Asteroid(sizeClass: .large, isImplodingType: false, isWobblingType: false)
        normalAst.position = .zero
        addGlossaryItem(
            graphic: normalAst,
            title: "NORMAL ASTEROID",
            titleColor: .lightGray,
            description: "Classic space rock. Splits into smaller parts when shot.",
            yPosition: -50
        )
        
        // Item 4: Imploding Asteroid
        let implodingAst = Asteroid(sizeClass: .large, isImplodingType: true, isWobblingType: false)
        implodingAst.position = .zero
        addGlossaryItem(
            graphic: implodingAst,
            title: "IMPLODING ASTEROID",
            titleColor: SKColor(red: 1.0, green: 0.3, blue: 0.8, alpha: 1.0),
            description: "Absorbs shots and grows, then collapses into a gravity well.",
            yPosition: -150
        )
        
        // Item 5: Wobbling Asteroid
        let wobblingAst = Asteroid(sizeClass: .large, isImplodingType: false, isWobblingType: true)
        wobblingAst.position = .zero
        addGlossaryItem(
            graphic: wobblingAst,
            title: "WOBBLING ASTEROID",
            titleColor: SKColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1.0),
            description: "Unstable rock. Grows over time and explodes into debris.",
            yPosition: -250
        )
        
        // Item 6: Large UFO
        let ufoLarge = UFO(isSmall: false, startOnLeft: true, screenSize: .zero)
        ufoLarge.position = .zero
        ufoLarge.velocity = .zero
        addGlossaryItem(
            graphic: ufoLarge,
            title: "LARGE UFO",
            titleColor: SKColor(red: 0.2, green: 1.0, blue: 0.2, alpha: 1.0),
            description: "Drifts across the screen, firing random lasers. Worth 200 pts.",
            yPosition: -350
        )
        
        // Item 7: Small UFO
        let ufoSmall = UFO(isSmall: true, startOnLeft: true, screenSize: .zero)
        ufoSmall.position = .zero
        ufoSmall.velocity = .zero
        addGlossaryItem(
            graphic: ufoSmall,
            title: "SMALL UFO",
            titleColor: SKColor(red: 1.0, green: 0.3, blue: 0.8, alpha: 1.0),
            description: "Fast, lethal saucer that snipes targets. Worth 500 pts.",
            yPosition: -450
        )
        
        // Item 8: Gravity Well
        let wellNode = GravityWell()
        wellNode.position = .zero
        addGlossaryItem(
            graphic: wellNode,
            title: "GRAVITY WELL",
            titleColor: .white,
            description: "A high-pull black hole. Event horizon destroys anything!",
            yPosition: -550
        )
        
        // Items 9+: Power-Ups einzeln untereinander, jeweils mit Kapsel-Grafik, Beschreibung
        // und (wo sinnvoll) einem Tipp.
        let powerUpEntries: [(type: PowerUpType, title: String, color: SKColor, desc: String)] = [
            (.shield, "SHIELD [S]", SKColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0),
             "Stacks up to 3 layers; each one absorbs a fatal hit. Stays until used."),
            (.triple, "TRIPLE LASER [W]", SKColor(red: 1.0, green: 0.2, blue: 0.0, alpha: 1.0),
             "Three-way spread shot. Great against swarms."),
            (.rapid, "RAPID FIRE [R]", SKColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0),
             "Machine-gun fire rate while you hold fire."),
            (.option, "OPTION DRONE [O]", SKColor(red: 0.8, green: 0.0, blue: 1.0, alpha: 1.0),
             "A wingman that fires with you. Stack up to two."),
            (.bomb, "SCREEN BOMB [B]", SKColor(red: 1.0, green: 0.0, blue: 0.2, alpha: 1.0),
             "Hits every object on screen once, just like a direct shot."),
            (.beam, "LASER BEAM [L]", SKColor(red: 0.3, green: 1.0, blue: 0.3, alpha: 1.0),
             "Hold fire for a sweeping beam. Spin to win!"),
            (.rear, "REAR LASER [T]", SKColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0),
             "Adds a shot out your tail. Watch your back."),
            (.compress, "COMPRESS [C]", SKColor(red: 0.9, green: 0.9, blue: 0.95, alpha: 1.0),
             "Shrinks you (and drones). Two stages – level 2 is a single pixel. Timed."),
            (.extraLife, "EXTRA LIFE [+]", SKColor(red: 1.0, green: 0.3, blue: 0.45, alpha: 1.0),
             "If killed, revives you centered, briefly invincible.")
        ]

        var py: CGFloat = -650
        for entry in powerUpEntries {
            let capsule = PowerUp(type: entry.type, position: .zero)
            capsule.xScale = 1.2
            capsule.yScale = 1.2
            addGlossaryItem(
                graphic: capsule,
                title: entry.title,
                titleColor: entry.color,
                description: entry.desc,
                yPosition: py
            )
            py -= 100
        }
        // Unterster Eintrag (für die Scroll-Schleife).
        glossaryContentBottom = py + 100
    }
}

/// A node representing a background star.
private final class StarNode: SKSpriteNode {
    var parallaxFactor: CGFloat = 0.0
}

/// A helper node representing an R-Type Option drone.
private final class OptionDrone: SKShapeNode {
    override init() {
        super.init()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 5, y: 0))
        path.addLine(to: CGPoint(x: -3, y: 3))
        path.addLine(to: CGPoint(x: -2, y: 0))
        path.addLine(to: CGPoint(x: -3, y: -3))
        path.closeSubpath()
        self.path = path
        self.strokeColor = SKColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0)
        self.fillColor = SKColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.1)
        self.lineWidth = 1.5
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
