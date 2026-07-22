// GameScene+TestHooks.swift — die …ForTesting-Hooks und Eingabe-Simulation (simulateKey…)
// für Headless-Tests, Replays und die iOS-Touch-Schicht.
// Reiner Datei-Split aus GameScene.swift — kein Verhalten geändert.

import Foundation
import SpriteKit

extension GameScene {
    // MARK: - Input Simulation Helpers

    /// Verbindet die Szene vor `presentScene` mit einer isolierten UserDefaults-
    /// Suite. Dadurch lesen und schreiben Tests niemals echte Spielerwerte.
    public func useUserDefaultsForTesting(_ defaults: UserDefaults) {
        precondition(view == nil, "Test-UserDefaults muessen vor presentScene gesetzt werden")
        highScoreStore = HighScoreStore(userDefaults: defaults)
    }
    
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

    /// Für Tests/Replay: startet ein frisches Spiel mit festgelegtem Seed, Start-Level und Modus.
    /// Setzt die Auswahl-Felder und ruft `startNewGame(seed:)` – damit ist ein deterministischer
    /// Lauf vollständig per Code reproduzierbar (Grundlage der Determinismus-Probe).
    public func startNewGameForTesting(seed: UInt64, startLevel: Int = 1, mode: GameMode = .ancientAsteroids) {
        self.selectedStartLevel = startLevel
        self.selectedMode = mode
        startNewGame(seed: seed)
    }

    /// Für Tests/Balancing: startet einen Demo-Lauf mit fester Persona + Seed unter Autopilot-
    /// Steuerung (klassischer Modus, Startlevel der Persona). Danach die Simulation über
    /// `advanceOneStep()` treiben und beobachten, wie lange `gameState == .playing` bleibt.
    public func startAutopilotDemoForTesting(persona: AutopilotPersona, seed: UInt64) {
        rememberUserSelectionBeforeDemo()
        autopilotPersona = persona
        autopilotRng = GameRandom(seed: seed ^ 0xA0710_5EED)
        selectedMode = .ancientAsteroids
        selectedStartLevel = persona.startLevel
        autoFire = true
        attractPhase = .demoPlaying
        attractTimer = 0
        startNewGame(seed: seed)
    }

    /// Für Tests: die aktuell aktive Autopilot-Persona (nil = kein Autopilot).
    public var autopilotPersonaNameForTesting: String? { autopilotPersona?.name }

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

    /// For testing: sets the accumulated play time (drives `difficultyFactor`). Lets a formula test
    /// skip simulating minutes of real frames.
    public func setPlayTimeForTesting(_ time: TimeInterval) {
        self.playTime = time
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

    /// For testing: gibt dem Schiff viele Extra-Leben, damit ein langer Lauf (Bosse, Level-Übergänge)
    /// nicht vorzeitig endet. Rein für Determinismus-Tests; das Wiederbeleben ist deterministisch.
    public func setExtraLivesForTesting(_ n: Int) { extraLives = n }

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
}
