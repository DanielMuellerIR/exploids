import AVFoundation
import Foundation

/// A procedural retro synthesizer for generating game sound effects and engine hum.
/// Handles audio graph configuration, overlapping sound effects, and continuous engine/charging hum.
public final class SoundManager: @unchecked Sendable {
    
    /// The shared singleton instance.
    public static let shared = SoundManager()
    
    // MARK: - Properties
    
    private let audioEngine = AVAudioEngine()
    private var sfxNode: AVAudioSourceNode?
    private var engineNode: AVAudioSourceNode?
    
    private let sampleRate: Double = 44100.0
    
    // SFX Mixer State
    private let sfxLock = NSLock()
    private var activeSounds: [ActiveSound] = []

    // MARK: - Sample-basierte SFX (optionaler Modus, umschaltbar zur Laufzeit)

    /// Umschalter: false = prozedurale Synth-Effekte (Default, bisheriges Verhalten),
    /// true = abgespielte generierte Samples aus dem Bundle (SFX/). Pro Effekt können mehrere
    /// Varianten vorliegen – die werden reihum abgespielt, damit es weniger eintönig klingt.
    public var useSampledSFX: Bool = false

    private let sampleLock = NSLock()
    /// Vorgeladene Sample-Puffer je Effektname (z.B. "laser" -> [variante0, variante1]).
    private var sampleBuffers: [String: [AVAudioPCMBuffer]] = [:]
    /// Pool von Player-Knoten für überlappende Wiedergabe (Round-Robin).
    private var samplePlayers: [AVAudioPlayerNode] = []
    private var samplePlayerIndex = 0
    /// Zähler je Effekt für das reihum-Abspielen der Varianten.
    private var sampleVariantIndex: [String: Int] = [:]
    private var samplesLoaded = false
    
    // Engine & Charging Hum State
    private let engineLock = NSLock()
    private var isThrustActive: Bool = false
    private var isChargingActive: Bool = false
    private var currentChargeProgress: Double = 0.0
    
    // Engine Hum Synthesis State (only mutated on the audio render thread)
    private var enginePhase: Double = 0.0
    private var engineLfoPhase: Double = 0.0
    private var engineVolLfoPhase: Double = 0.0
    private var engineCurrentFrequency: Double = 50.0
    private var engineCurrentVolume: Double = 0.0
    
    // Charge Hum Synthesis State (only mutated on the audio render thread)
    private var chargePhase: Double = 0.0
    
    /// Mute state of the synthesizer. If true, audio engine setup/start is skipped and no sounds are generated.
    public var isMuted: Bool = CommandLine.arguments.contains("--no-sound") {
        didSet {
            if isMuted {
                stop()
            }
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        #if os(iOS)
        // iOS meldet über diese Notification, dass sich die Audio-Konfiguration geändert hat
        // (z.B. wenn sich beim Kaltstart die Audio-Route/Session erst einpendelt oder Kopfhörer
        // ein-/ausgesteckt werden). Dabei STOPPT die AVAudioEngine sich selbst – ohne Neustart
        // bleibt der Ton sonst im kaputten/verzerrten Zustand. Wir starten daher neu und lassen
        // den MusicPlayer seinen Knoten neu einplanen (dessen Planung geht beim Stopp verloren).
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
        #endif
        // Automatically set up and start the audio engine
        start()
    }

    #if os(iOS)
    /// Wird aufgerufen, nachdem die Engine neu gestartet wurde (Konfigurationswechsel) – damit der
    /// MusicPlayer seinen Musik-Knoten neu einplanen kann. Wird vom MusicPlayer gesetzt.
    public var onEngineReset: (@Sendable () -> Void)?

    /// Reagiert auf AVAudioEngineConfigurationChange: Engine neu starten und Abnehmer benachrichtigen.
    private func handleConfigurationChange() {
        guard !isMuted else { return }
        do {
            if !audioEngine.isRunning {
                try audioEngine.start()
            }
        } catch {
            print("SoundManager: Neustart nach ConfigurationChange fehlgeschlagen: \(error.localizedDescription)")
        }
        onEngineReset?()
    }
    #endif
    
    // MARK: - Public API
    
    /// Starts the audio engine if it is not already running.
    public func start() {
        guard !isMuted else { return }
        guard !audioEngine.isRunning else { return }

        #if os(iOS)
        // Ohne aktive AVAudioSession bleibt die AVAudioEngine auf iOS stumm.
        AudioSessionConfig.activate()
        #endif

        do {
            if sfxNode == nil || engineNode == nil {
                setupAudioGraph()
            }
            try audioEngine.start()
            print("SoundManager: AVAudioEngine started successfully.")
        } catch {
            print("SoundManager: Failed to start AVAudioEngine: \(error.localizedDescription)")
        }
    }
    
    /// Stops the audio engine.
    public func stop() {
        audioEngine.stop()
        print("SoundManager: AVAudioEngine stopped.")
    }
    
    /// Plays a retro laser sound effect.
    public func playLaser() {
        playSound(.laser)
    }
    
    /// Plays a retro explosion sound effect.
    public func playExplosion() {
        playSound(.explosion)
    }
    
    /// Plays a glistening retro power-up collection sound.
    public func playPowerUp() {
        playSound(.powerUp)
    }
    
    /// Plays a deep screen-clearing bomb detonation sound.
    public func playBomb() {
        playSound(.bomb)
    }
    
    /// Plays a heavy energy blast sound for the Wave Cannon.
    public func playChargeShot() {
        playSound(.chargeShot)
    }
    
    /// Plays a wavy UFO scanning sound.
    public func playUfoSound() {
        playSound(.ufo)
    }
    
    /// Plays a retro level completion fanfare.
    public func playLevelComplete() {
        playSound(.levelComplete)
    }
    
    /// Plays a deep black hole implosion suction sound.
    public func playImplosion() {
        playSound(.implosion)
    }
    
    /// Sets whether the thrust active state is true or false, ramping the engine hum.
    public func setThrustActive(_ active: Bool) {
        guard !isMuted else { return }
        if active && !audioEngine.isRunning {
            start()
        }
        
        engineLock.lock()
        isThrustActive = active
        engineLock.unlock()
    }
    
    /// Sets the real-time charging state and progression to synthesize the Wave Cannon charge tone.
    public func setChargingActive(_ active: Bool, progress: Double = 0.0) {
        guard !isMuted else { return }
        if active && !audioEngine.isRunning {
            start()
        }
        
        engineLock.lock()
        isChargingActive = active
        currentChargeProgress = progress
        engineLock.unlock()
    }
    
    // MARK: - Private Setup
    
    private func setupAudioGraph() {
        if let sfx = sfxNode {
            audioEngine.detach(sfx)
        }
        if let engine = engineNode {
            audioEngine.detach(engine)
        }
        
        guard let audioFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            print("SoundManager: Failed to create AVAudioFormat.")
            return
        }
        
        // SFX Source Node
        let sfxNode = AVAudioSourceNode { [weak self] (isSilence, timestamp, frameCount, outputData) -> OSStatus in
            guard let self = self else { return noErr }
            
            self.sfxLock.lock()
            defer { self.sfxLock.unlock() }
            
            let abl = UnsafeMutableAudioBufferListPointer(outputData)
            
            for buffer in abl {
                if let mData = buffer.mData {
                    memset(mData, 0, Int(buffer.mDataByteSize))
                }
            }
            
            if self.activeSounds.isEmpty {
                isSilence.pointee = true
                return noErr
            }
            
            isSilence.pointee = false
            let localSampleRate = self.sampleRate
            
            for frame in 0..<Int(frameCount) {
                var sum: Double = 0.0
                var i = 0
                while i < self.activeSounds.count {
                    let sound = self.activeSounds[i]
                    if let sample = sound.nextSample(sampleRate: localSampleRate) {
                        sum += sample
                        i += 1
                    } else {
                        self.activeSounds.remove(at: i)
                    }
                }
                
                let finalSample = Float(max(-1.0, min(1.0, sum)))
                for buffer in abl {
                    if let ptr = buffer.mData?.assumingMemoryBound(to: Float.self) {
                        ptr[frame] = finalSample
                    }
                }
            }
            
            return noErr
        }
        
        // Engine + Charge Hum Source Node
        let engineNode = AVAudioSourceNode { [weak self] (isSilence, timestamp, frameCount, outputData) -> OSStatus in
            guard let self = self else { return noErr }
            
            self.engineLock.lock()
            let thrustActive = self.isThrustActive
            let charging = self.isChargingActive
            let chargeProg = self.currentChargeProgress
            self.engineLock.unlock()
            
            let targetFreq: Double = thrustActive ? 120.0 : 50.0
            let targetVol: Double = thrustActive ? 0.35 : 0.0
            
            let abl = UnsafeMutableAudioBufferListPointer(outputData)
            let localSampleRate = self.sampleRate
            
            for buffer in abl {
                if let mData = buffer.mData {
                    memset(mData, 0, Int(buffer.mDataByteSize))
                }
            }
            
            if self.engineCurrentVolume < 0.001 && !thrustActive && !charging {
                isSilence.pointee = true
                self.engineCurrentVolume = 0.0
                return noErr
            }
            
            isSilence.pointee = false
            
            for frame in 0..<Int(frameCount) {
                // 1. Synthesize Engine Hum
                let freqRampFactor = thrustActive ? 0.0005 : 0.001
                self.engineCurrentFrequency += (targetFreq - self.engineCurrentFrequency) * freqRampFactor
                
                let volRampFactor = thrustActive ? 0.0002 : 0.001
                self.engineCurrentVolume += (targetVol - self.engineCurrentVolume) * volRampFactor
                
                let lfoFreq = 6.0
                let lfoDepth = 3.0
                self.engineLfoPhase += 2.0 * .pi * lfoFreq / localSampleRate
                if self.engineLfoPhase >= 2.0 * .pi {
                    self.engineLfoPhase -= 2.0 * .pi
                }
                let lfoValue = sin(self.engineLfoPhase)
                let modulatedFreq = self.engineCurrentFrequency + lfoValue * lfoDepth
                
                let volLfoFreq = 8.5
                let volLfoDepth = 0.05
                self.engineVolLfoPhase += 2.0 * .pi * volLfoFreq / localSampleRate
                if self.engineVolLfoPhase >= 2.0 * .pi {
                    self.engineVolLfoPhase -= 2.0 * .pi
                }
                let volLfoValue = 1.0 + sin(self.engineVolLfoPhase) * volLfoDepth
                let finalVolume = self.engineCurrentVolume * volLfoValue
                
                let fraction = self.enginePhase / (2.0 * .pi)
                let norm = fraction - floor(fraction)
                let triangle = 4.0 * abs(norm - 0.5) - 1.0
                let square = (self.enginePhase.truncatingRemainder(dividingBy: 2.0 * .pi) < .pi) ? 1.0 : -1.0
                let mixedWave = 0.7 * triangle + 0.3 * square
                let noise = Double.random(in: -0.05...0.05)
                
                var sampleValue = (mixedWave + noise) * finalVolume
                
                // 2. Synthesize Charge Hum (if charging)
                if charging {
                    let chargeFreq = 250.0 + 850.0 * chargeProg
                    let chargeLfo = sin(self.chargePhase * 0.04) * 8.0
                    let finalChargeFreq = chargeFreq + chargeLfo
                    
                    let sineWave = sin(self.chargePhase)
                    let pulseFrac = self.chargePhase / (2.0 * .pi)
                    let pulse = (pulseFrac - floor(pulseFrac) < 0.25) ? 0.3 : -0.3
                    
                    let combinedChargeWave = 0.8 * sineWave + 0.2 * pulse
                    
                    let pulseVol = 0.75 + 0.25 * sin(self.chargePhase * 0.08)
                    let chargeVolume = 0.25 * chargeProg * pulseVol
                    
                    sampleValue += combinedChargeWave * chargeVolume
                    
                    self.chargePhase += 2.0 * .pi * finalChargeFreq / localSampleRate
                    if self.chargePhase >= 2.0 * .pi {
                        self.chargePhase -= 2.0 * .pi
                    }
                }
                
                let finalSample = Float(max(-1.0, min(1.0, sampleValue)))
                for buffer in abl {
                    if let ptr = buffer.mData?.assumingMemoryBound(to: Float.self) {
                        ptr[frame] = finalSample
                    }
                }
                
                self.enginePhase += 2.0 * .pi * modulatedFreq / localSampleRate
                if self.enginePhase >= 2.0 * .pi {
                    self.enginePhase -= 2.0 * .pi
                }
            }
            
            return noErr
        }
        
        audioEngine.attach(sfxNode)
        audioEngine.attach(engineNode)
        
        let mixer = audioEngine.mainMixerNode
        audioEngine.connect(sfxNode, to: mixer, format: audioFormat)
        audioEngine.connect(engineNode, to: mixer, format: audioFormat)
        
        self.sfxNode = sfxNode
        self.engineNode = engineNode
        
        sfxLock.lock()
        activeSounds.reserveCapacity(32)
        sfxLock.unlock()
    }
    
    private func playSound(_ type: ActiveSound.SoundType) {
        guard !isMuted else { return }
        if !audioEngine.isRunning {
            start()
        }

        // Sample-Modus: erst versuchen, ein generiertes Sample abzuspielen. Klappt das nicht
        // (kein Sample vorhanden), fällt es unten auf den prozeduralen Synth zurück.
        if useSampledSFX {
            loadSamplesIfNeeded()
            if playSampled(name(for: type)) { return }
        }

        sfxLock.lock()
        defer { self.sfxLock.unlock() }

        guard activeSounds.count < 16 else { return }
        activeSounds.append(ActiveSound(type: type, sampleRate: sampleRate))
    }

    // MARK: - Sample-basierte SFX: Laden & Abspielen

    /// Effektname (Dateipräfix im SFX-Bundle) zu einem Sound-Typ.
    private func name(for type: ActiveSound.SoundType) -> String {
        switch type {
        case .laser:         return "laser"
        case .explosion:     return "explosion"
        case .powerUp:       return "powerup"
        case .bomb:          return "bomb"
        case .chargeShot:    return "chargeshot"
        case .ufo:           return "ufo"
        case .levelComplete: return "levelcomplete"
        case .implosion:     return "implosion"
        }
    }

    /// Lädt einmalig alle Samples aus dem Bundle (SFX/<name>_<n>.m4a) und legt den Player-Pool an.
    /// Idempotent. Alle Puffer werden auf das kanonische Engine-Format (mono, sampleRate) konvertiert,
    /// damit sie problemlos auf demselben Mixer laufen.
    private func loadSamplesIfNeeded() {
        sampleLock.lock()
        defer { sampleLock.unlock() }
        guard !samplesLoaded else { return }
        samplesLoaded = true

        // Stereo/sampleRate – passt zum Format der generierten .m4a-Dateien, daher ist beim Laden
        // keine Format-Konvertierung nötig (Puffer werden direkt verwendet).
        guard let canonical = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
        let names = ["laser", "explosion", "powerup", "bomb", "chargeshot", "ufo", "levelcomplete", "implosion"]
        for n in names {
            var variants: [AVAudioPCMBuffer] = []
            var idx = 0
            while let url = Bundle.module.url(forResource: "\(n)_\(idx)", withExtension: "m4a", subdirectory: "SFX") {
                if let buf = SoundManager.loadBuffer(url: url, expected: canonical) {
                    variants.append(buf)
                }
                idx += 1
            }
            if !variants.isEmpty { sampleBuffers[n] = variants }
        }

        // Pool aus Player-Knoten für überlappende Wiedergabe (mehr als die meisten Spielszenen brauchen).
        for _ in 0..<8 {
            let node = AVAudioPlayerNode()
            audioEngine.attach(node)
            audioEngine.connect(node, to: audioEngine.mainMixerNode, format: canonical)
            samplePlayers.append(node)
        }
    }

    /// Spielt ein Sample des Effekts ab (reihum die nächste Variante, Round-Robin über den Player-Pool).
    /// Gibt false zurück, wenn kein Sample vorliegt -> Aufrufer nutzt dann den prozeduralen Synth.
    private func playSampled(_ effectName: String) -> Bool {
        sampleLock.lock()
        guard let variants = sampleBuffers[effectName], !variants.isEmpty, !samplePlayers.isEmpty else {
            sampleLock.unlock()
            return false
        }
        let vi = (sampleVariantIndex[effectName] ?? 0)
        sampleVariantIndex[effectName] = vi + 1
        let buffer = variants[vi % variants.count]
        let node = samplePlayers[samplePlayerIndex % samplePlayers.count]
        samplePlayerIndex += 1
        sampleLock.unlock()

        // .interrupts: belegt der Knoten gerade noch etwas, wird es ersetzt (bei 8 Knoten selten).
        node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !node.isPlaying { node.play() }
        return true
    }

    /// Lädt eine Audiodatei in einen Puffer. Erwartet das Zielformat (Stereo/sampleRate) – die
    /// generierten SFX liegen genau so vor, daher ist keine Konvertierung nötig. Weicht eine Datei
    /// doch ab, wird sie übersprungen (statt mit falschem Format auf dem Mixer zu landen).
    private static func loadBuffer(url: URL, expected format: AVAudioFormat) -> AVAudioPCMBuffer? {
        do {
            let file = try AVAudioFile(forReading: url)
            guard file.processingFormat == format else {
                print("SoundManager: Sample-Format unerwartet (\(url.lastPathComponent)) – übersprungen")
                return nil
            }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                                frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
            try file.read(into: buffer)
            return buffer
        } catch {
            print("SoundManager: Sample konnte nicht geladen werden (\(url.lastPathComponent)): \(error.localizedDescription)")
            return nil
        }
    }

    #if os(iOS)
    // MARK: - Musik über die gemeinsame Engine (nur iOS)
    //
    // Auf iOS darf die Musik NICHT über einen separaten AVAudioPlayer laufen, während diese
    // AVAudioEngine (SFX) aktiv ist: zwei unabhängige Audio-Render-Pfade auf dieselbe Hardware
    // erzeugen hörbare Verzerrungen (Musik wird unkenntlich). Deshalb hängt die Musik als
    // zusätzlicher Player-Knoten an genau dieser Engine – ein einziger Render-Pfad. Auf macOS
    // gibt es dieses Problem nicht; dort bleibt der MusicPlayer beim AVAudioPlayer.

    /// Erzeugt einen an den Mixer angeschlossenen Player-Knoten für die Musik und gibt ihn zurück.
    /// Stellt sicher, dass Engine + AudioSession laufen. Liefert nil, wenn stummgeschaltet oder die
    /// Engine nicht startet. Der Aufrufer (MusicPlayer) plant die Tracks selbst ein und ruft play().
    public func makeMusicNode(format: AVAudioFormat) -> AVAudioPlayerNode? {
        guard !isMuted else { return nil }
        start()  // Engine + AVAudioSession sicherstellen
        guard audioEngine.isRunning else { return nil }
        let node = AVAudioPlayerNode()
        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEngine.mainMixerNode, format: format)
        return node
    }
    #endif
}

// MARK: - ActiveSound Helper Class

/// Represents a single active playing sound effect.
final class ActiveSound: @unchecked Sendable {
    enum SoundType: Sendable {
        case laser
        case explosion
        case powerUp
        case bomb
        case chargeShot
        case ufo
        case levelComplete
        case implosion
    }
    
    let type: SoundType
    private(set) var currentFrame: Int = 0
    let totalFrames: Int
    private var phase: Double = 0.0
    private var lastSample: Double = 0.0
    
    init(type: SoundType, sampleRate: Double) {
        self.type = type
        switch type {
        case .laser:
            self.totalFrames = Int(0.15 * sampleRate)
        case .explosion:
            self.totalFrames = Int(0.5 * sampleRate)
        case .powerUp:
            self.totalFrames = Int(0.42 * sampleRate)
        case .bomb:
            self.totalFrames = Int(1.1 * sampleRate)
        case .chargeShot:
            self.totalFrames = Int(0.38 * sampleRate)
        case .ufo:
            self.totalFrames = Int(0.28 * sampleRate)
        case .levelComplete:
            self.totalFrames = Int(0.75 * sampleRate)
        case .implosion:
            self.totalFrames = Int(0.95 * sampleRate)
        }
    }
    
    /// Generates the next sample frame for the sound effect.
    func nextSample(sampleRate: Double) -> Double? {
        guard currentFrame < totalFrames else { return nil }
        
        let progress = Double(currentFrame) / Double(totalFrames)
        var sampleValue: Double = 0.0
        
        switch type {
        case .laser:
            let startFreq = 800.0
            let endFreq = 150.0
            let currentFreq = startFreq + (endFreq - startFreq) * progress
            let volume = 1.0 - progress
            
            let fraction = phase / (2.0 * .pi)
            let norm = fraction - floor(fraction)
            let triangle = 4.0 * abs(norm - 0.5) - 1.0
            
            sampleValue = triangle * volume * 0.25
            
            phase += 2.0 * .pi * currentFreq / sampleRate
            if phase >= 2.0 * .pi {
                phase -= 2.0 * .pi
            }
            
        case .explosion:
            let volume = (1.0 - progress) * (1.0 - progress)
            let startCutoff = 800.0
            let endCutoff = 80.0
            let cutoff = startCutoff + (endCutoff - startCutoff) * progress
            let alpha = min(1.0, max(0.0, 2.0 * .pi * cutoff / sampleRate))
            
            let noise = Double.random(in: -1.0...1.0)
            let filtered = lastSample + alpha * (noise - lastSample)
            lastSample = filtered
            
            sampleValue = filtered * volume * 0.3
            
        case .powerUp:
            let notes = [280.0, 420.0, 560.0, 840.0]
            let noteIndex = Int(progress * 4.0)
            let currentFreq = notes[min(3, noteIndex)]
            let volume = 1.0 - progress
            
            let fraction = phase / (2.0 * .pi)
            let square = (fraction - floor(fraction) < 0.5) ? 0.8 : -0.8
            
            sampleValue = square * volume * 0.15
            
            phase += 2.0 * .pi * currentFreq / sampleRate
            if phase >= 2.0 * .pi {
                phase -= 2.0 * .pi
            }
            
        case .bomb:
            let volume = (1.0 - progress) * (1.0 - progress)
            let startCutoff = 160.0
            let endCutoff = 15.0
            let cutoff = startCutoff + (endCutoff - startCutoff) * progress
            let alpha = min(1.0, max(0.0, 2.0 * .pi * cutoff / sampleRate))
            
            let noise = Double.random(in: -1.0...1.0)
            let filtered = lastSample + alpha * (noise - lastSample)
            lastSample = filtered
            
            sampleValue = filtered * volume * 0.6
            
        case .chargeShot:
            let startFreq = 1100.0
            let endFreq = 80.0
            let currentFreq = startFreq + (endFreq - startFreq) * progress
            let volume = 1.0 - progress
            
            let fraction = phase / (2.0 * .pi)
            let triangle = 4.0 * abs((fraction - floor(fraction)) - 0.5) - 1.0
            let square = (phase.truncatingRemainder(dividingBy: 2.0 * .pi) < .pi) ? 0.7 : -0.7
            let mixed = 0.5 * triangle + 0.5 * square
            
            sampleValue = mixed * volume * 0.32
            
            phase += 2.0 * .pi * currentFreq / sampleRate
            if phase >= 2.0 * .pi {
                phase -= 2.0 * .pi
            }
            
        case .ufo:
            let baseFreq = 580.0
            let vibrato = sin(progress * 12.0 * 2.0 * .pi) * 120.0
            let currentFreq = baseFreq + vibrato
            let volume = 0.22 * (1.0 - progress)
            
            let fraction = phase / (2.0 * .pi)
            let square = (fraction - floor(fraction) < 0.5) ? 0.9 : -0.9
            
            sampleValue = square * volume * 0.15
            
            phase += 2.0 * .pi * currentFreq / sampleRate
            if phase >= 2.0 * .pi {
                phase -= 2.0 * .pi
            }
            
        case .levelComplete:
            // Ascending major arpeggio sequence followed by C major chord
            let notes = [261.6, 329.6, 392.0, 523.3, 659.3, 784.0]
            let count = Double(notes.count)
            let noteIdx = Int(progress * 1.5 * count)
            
            let currentFreq: Double
            if noteIdx < notes.count {
                currentFreq = notes[noteIdx]
            } else {
                let chordFreqs = [523.3, 659.3, 784.0]
                currentFreq = chordFreqs[currentFrame % 3]
            }
            
            let volume = 1.0 - progress
            let fraction = phase / (2.0 * .pi)
            let triangle = 4.0 * abs((fraction - floor(fraction)) - 0.5) - 1.0
            
            sampleValue = triangle * volume * 0.20
            
            phase += 2.0 * .pi * currentFreq / sampleRate
            if phase >= 2.0 * .pi {
                phase -= 2.0 * .pi
            }
            
        case .implosion:
            // Sweeping downward pitch low frequency singularity suction
            let startFreq = 260.0
            let endFreq = 18.0
            let currentFreq = startFreq + (endFreq - startFreq) * progress
            let volume = (1.0 - progress) * (1.0 - progress)
            
            let alpha = min(1.0, max(0.0, 2.0 * .pi * currentFreq / sampleRate))
            let noise = Double.random(in: -1.0...1.0)
            let filtered = lastSample + alpha * (noise - lastSample)
            lastSample = filtered
            
            // Suction swirl sweep effect
            let swirl = 1.0 + 0.35 * sin(progress * 22.0 * 2.0 * .pi)
            sampleValue = filtered * volume * swirl * 0.5
        }
        
        currentFrame += 1
        return sampleValue
    }
}
