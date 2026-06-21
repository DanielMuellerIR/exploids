import AppKit
import SpriteKit
import GameCore

/// A custom NSWindow subclass that hosts the SpriteKit rendering view.
public final class GameWindow: NSWindow {
    
    public init() {
        let contentRect = NSRect(x: 0, y: 0, width: 1024, height: 768)
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        
        self.title = "Exploids"
        self.center()
        self.minSize = NSSize(width: 800, height: 600)
        
        // Apply modern macOS dark aqua appearance to the window
        self.appearance = NSAppearance(named: .darkAqua)
        
        // Initialize SKView to enable SpriteKit rendering
        let skView = SKView(frame: contentRect)
        skView.autoresizingMask = [.width, .height]
        
        // Show diagnostic overlays for development verification
        skView.showsFPS = true
        skView.showsNodeCount = true
        
        // Set up the GameScene as the content
        let scene = GameScene(size: contentRect.size)
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .black
        // Cmd+Q über die Scene an AppKit weiterreichen: GameCore ist plattformunabhängig und kennt
        // NSApplication nicht mehr; die macOS-Shell legt hier das Beenden-Verhalten fest.
        scene.onQuit = { NSApplication.shared.terminate(nil) }
        skView.presentScene(scene)
        
        // Set the window's contentView to the SpriteKit view
        self.contentView = skView

        // Die SKView als First Responder verankern, damit Tastatur-Events zuverlässig die Scene
        // erreichen (auch nachdem das Fenster den Fokus verloren und wieder erhalten hat).
        self.initialFirstResponder = skView
        self.makeFirstResponder(skView)
    }
}
