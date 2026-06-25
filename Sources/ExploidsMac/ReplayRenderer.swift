import Foundation
import SpriteKit
import Metal
import ImageIO
import UniformTypeIdentifiers
import GameCore

/// Headless-Renderer: erzeugt aus einer `Replay`-Aufnahme deterministisch eine animierte GIF-Datei –
/// ganz ohne sichtbares Fenster (passt zur Headless-/Agent-Linie des Projekts). Genutzt vom
/// CLI-Flag `--render-replay` (siehe Main.swift).
///
/// Ablauf je Schritt: `scene.advanceOneStep()` treibt genau einen festen Simulationsschritt voran
/// (speist die aufgezeichneten Eingaben ein), `SKRenderer.update(atTime:)` tickt die visuellen
/// SKActions auf dieselbe Sim-Zeit, und `SKRenderer.render(...)` zeichnet den Zustand in eine
/// Offscreen-Metal-Textur, die als `CGImage` gelesen und per ImageIO zu einem GIF kodiert wird.
/// (Läuft im CLI-Pfad ohnehin auf dem Main-Thread; bewusst ohne `@MainActor`, damit der Aufruf aus
/// der nonisolated `Main.main()` wie die übrigen SpriteKit-Aufrufe nur Concurrency-Warnungen erzeugt.)
enum ReplayRenderer {

    /// Render-Optionen mit vernünftigen Defaults für ein Promo-GIF.
    struct Options {
        /// Auflösung des GIFs (quadratisch passt zur Szene; Default kompakt für ein Web-GIF).
        var width: Int = 480
        var height: Int = 360
        /// Nur jeden N-ten Simulationsschritt ins GIF aufnehmen. `nil` = automatisch so wählen, dass
        /// das GIF in Echtzeit läuft (Sim-Rate / fps, z. B. 120/30 → jeder 4.). Explizit setzen, um
        /// Zeitlupe/Zeitraffer zu erzwingen.
        var frameStride: Int? = nil
        /// Bilder pro Sekunde im GIF (Abspieltempo). 30 wirkt flüssig.
        var fps: Int = 30
        /// HUD/Overlay (Score, Timer, „REPLAY") ausblenden für ein sauberes Promo-GIF.
        var hideHUD: Bool = true
        /// Maximale Anzahl gerenderter Frames (Sicherheitsdeckel gegen riesige GIFs). 0 = unbegrenzt.
        var maxFrames: Int = 900
        /// Erst ab diesem Simulationsframe rendern (vorherige Frames werden nur simuliert, nicht
        /// aufgenommen). Damit lässt sich ein Ausschnitt aus der Mitte/dem Ende eines langen Laufs greifen.
        var startFrame: Int = 0
        /// Auto-Feuer-Zustand erzwingen (für alte Aufnahmen ohne gespeichertes Feld). `nil` = den
        /// in der Aufnahme gespeicherten Wert nutzen.
        var autoFireOverride: Bool? = nil
    }

    enum RenderError: Error, CustomStringConvertible {
        case noMetalDevice
        case textureCreationFailed
        case gifDestinationFailed
        case noFramesRendered

        var description: String {
            switch self {
            case .noMetalDevice: return "Kein Metal-Gerät verfügbar (Offscreen-Rendering nicht möglich)."
            case .textureCreationFailed: return "Offscreen-Textur konnte nicht erstellt werden."
            case .gifDestinationFailed: return "GIF-Ziel konnte nicht erstellt werden."
            case .noFramesRendered: return "Es wurden keine Frames gerendert (leere Aufnahme?)."
            }
        }
    }

    /// Rendert die Aufnahme in eine GIF-Datei.
    static func renderToGIF(_ replay: Replay, outputURL: URL, options: Options = Options()) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError.noMetalDevice }
        guard let commandQueue = device.makeCommandQueue() else { throw RenderError.noMetalDevice }

        let width = options.width
        let height = options.height

        // Szene aufsetzen (didMove-Setup über eine Offscreen-SKView auslösen) und Replay starten.
        let scene = GameScene(size: CGSize(width: width, height: height))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        view.presentScene(scene)
        if options.hideHUD { scene.setHUDHiddenForRender(true) }
        scene.replayAutoFireOverride = options.autoFireOverride
        guard scene.startReplay(replay) else { throw RenderError.noFramesRendered }

        // Offscreen-Renderer + Ziel-Textur (Apple Silicon: .shared erlaubt direktes getBytes).
        let renderer = SKRenderer(device: device)
        renderer.scene = scene

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: texDesc) else {
            throw RenderError.textureCreationFailed
        }

        let viewport = CGRect(x: 0, y: 0, width: width, height: height)
        var images: [CGImage] = []

        // Simulation hier explizit Schritt für Schritt treiben (advanceOneStep); der normale
        // Echtzeit-Akkumulator in update(_:) bleibt damit außen vor. `renderer.update(atTime:)` tickt
        // nur noch die visuellen SKActions auf dieselbe Sim-Zeit. Je `stride` ein Bild aufnehmen.
        scene.externalStepDriving = true
        let stride = max(1, options.frameStride ?? (GameScene.simStepsPerSecond / max(1, options.fps)))
        var simFrame = 0
        var simTime: TimeInterval = 0.0
        while scene.advanceOneStep() {            // ein fester Sim-Schritt; false = Aufnahme zu Ende
            simTime += GameScene.simStep
            renderer.update(atTime: simTime)       // SKActions/visuelle Effekte auf simTime ticken

            // Schritte vor dem gewünschten Startpunkt nur simulieren, nicht aufnehmen (Ausschnitt-Wahl).
            if simFrame < options.startFrame {
                simFrame += 1
                continue
            }

            if (simFrame - options.startFrame) % stride == 0 {
                if let img = renderFrame(renderer: renderer, commandQueue: commandQueue,
                                         texture: texture, viewport: viewport) {
                    images.append(img)
                }
                if options.maxFrames > 0 && images.count >= options.maxFrames { break }
            }
            simFrame += 1
        }

        guard !images.isEmpty else { throw RenderError.noFramesRendered }
        try encodeGIF(images: images, fps: options.fps, to: outputURL)
    }

    /// Rendert den aktuellen Szenenzustand in die Textur und liest ihn als `CGImage` zurück.
    private static func renderFrame(renderer: SKRenderer, commandQueue: MTLCommandQueue,
                                    texture: MTLTexture, viewport: CGRect) -> CGImage? {
        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = texture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        passDesc.colorAttachments[0].storeAction = .store

        guard let cmdBuf = commandQueue.makeCommandBuffer() else { return nil }
        renderer.render(withViewport: viewport, commandBuffer: cmdBuf, renderPassDescriptor: passDesc)
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        return cgImage(from: texture)
    }

    /// Liest eine BGRA8-`.shared`-Textur in ein `CGImage` (Y nicht gespiegelt – SpriteKit rendert
    /// bereits in Bildschirm-Orientierung).
    private static func cgImage(from texture: MTLTexture) -> CGImage? {
        let w = texture.width, h = texture.height
        let rowBytes = w * 4
        var data = [UInt8](repeating: 0, count: rowBytes * h)
        texture.getBytes(&data, bytesPerRow: rowBytes,
                         from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // BGRA8 = byteOrder32Little + premultipliedFirst (Alpha vorne).
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: rowBytes, space: colorSpace,
                                  bitmapInfo: bitmapInfo.rawValue) else { return nil }
        return ctx.makeImage()
    }

    /// Kodiert die Frames als animiertes GIF (Endlosschleife) per ImageIO.
    private static func encodeGIF(images: [CGImage], fps: Int, to url: URL) throws {
        let gifType = UTType.gif.identifier as CFString
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, gifType, images.count, nil) else {
            throw RenderError.gifDestinationFailed
        }
        let fileProps = [kCGImagePropertyGIFDictionary as String:
                            [kCGImagePropertyGIFLoopCount as String: 0]]    // 0 = Endlosschleife
        CGImageDestinationSetProperties(dest, fileProps as CFDictionary)

        let delay = 1.0 / Double(max(1, fps))
        let frameProps = [kCGImagePropertyGIFDictionary as String:
                            [kCGImagePropertyGIFDelayTime as String: delay]]
        for img in images {
            CGImageDestinationAddImage(dest, img, frameProps as CFDictionary)
        }
        if !CGImageDestinationFinalize(dest) {
            throw RenderError.gifDestinationFailed
        }
    }
}
