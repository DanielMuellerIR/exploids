import AppKit
import SpriteKit
import Foundation
import GameCore

/// The application delegate responsible for managing the application's lifecycle,
/// drawing the programmatic Dock icon, and setting up the native macOS menu bar.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var aboutWindow: NSWindow?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Create and display the game window
        let gameWindow = GameWindow()
        gameWindow.makeKeyAndOrderFront(nil)
        self.window = gameWindow
        
        // 1. Programmatically draw and assign a high-res retro Dock icon
        setProgrammaticDockIcon()
        
        // 2. Configure a native macOS menu bar with About Exploids window
        setupMenuBar()
        
        // Bring the app to the foreground
        NSApp.activate(ignoringOtherApps: true)

        // Hintergrundmusik starten (läuft durchgehend über alle Screens; mit „M" umschaltbar).
        MusicPlayer.shared.start()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Terminate the app when the game window is closed
        return true
    }
    
    // MARK: - Programmatic Dock Icon Setup
    
    private func setProgrammaticDockIcon() {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size, flipped: false) { rect in
            // Black background canvas
            let bgPath = NSBezierPath(rect: rect)
            NSColor.black.set()
            bgPath.fill()
            
            // Draw subtle vector grid background lines
            NSColor(white: 0.16, alpha: 1.0).setStroke()
            let gridPath = NSBezierPath()
            gridPath.lineWidth = 2.0
            for i in 1...7 {
                let x = CGFloat(i) * (512.0 / 8.0)
                gridPath.move(to: CGPoint(x: x, y: 0))
                gridPath.line(to: CGPoint(x: x, y: 512))
                
                let y = CGFloat(i) * (512.0 / 8.0)
                gridPath.move(to: CGPoint(x: 0, y: y))
                gridPath.line(to: CGPoint(x: 512, y: y))
            }
            gridPath.stroke()
            
            let center = CGPoint(x: 256, y: 256)
            
            // Draw large glowing cyan ship triangle outline
            let shipPath = NSBezierPath()
            shipPath.move(to: CGPoint(x: center.x + 130, y: center.y))
            shipPath.line(to: CGPoint(x: center.x - 90, y: center.y + 80))
            shipPath.line(to: CGPoint(x: center.x - 60, y: center.y))
            shipPath.line(to: CGPoint(x: center.x - 90, y: center.y - 80))
            shipPath.close()
            shipPath.lineWidth = 14
            NSColor.cyan.setStroke()
            shipPath.stroke()
            
            // Draw ship thruster orange/red flame outline
            let flamePath = NSBezierPath()
            flamePath.move(to: CGPoint(x: center.x - 60, y: center.y))
            flamePath.line(to: CGPoint(x: center.x - 140, y: center.y + 35))
            flamePath.line(to: CGPoint(x: center.x - 200, y: center.y))
            flamePath.line(to: CGPoint(x: center.x - 140, y: center.y - 35))
            flamePath.close()
            flamePath.lineWidth = 8
            NSColor.orange.setStroke()
            flamePath.stroke()
            
            return true
        }
        NSApp.applicationIconImage = image
    }
    
    // MARK: - Native macOS Menu Bar Configuration
    
    private func setupMenuBar() {
        let mainMenu = NSMenu()
        
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        
        let appSubmenu = NSMenu()
        appMenuItem.submenu = appSubmenu
        
        // About Item
        let aboutItem = NSMenuItem(title: "About Exploids", action: #selector(showAboutWindow), keyEquivalent: "")
        aboutItem.target = self
        appSubmenu.addItem(aboutItem)
        
        appSubmenu.addItem(NSMenuItem.separator())
        
        // Quit Item
        let quitItem = NSMenuItem(title: "Quit Exploids", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        appSubmenu.addItem(quitItem)
        
        NSApp.mainMenu = mainMenu
    }
    
    // MARK: - About Screen Window
    
    @objc private func showAboutWindow() {
        if let existing = aboutWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Exploids"
        window.center()
        window.appearance = NSAppearance(named: .darkAqua)
        
        // Semi-translucent visual effect HUD backdrop
        let visualEffectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 520, height: 380))
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 380))
        
        // Retro C64 Courier Header
        let titleLabel = NSTextField(labelWithString: "EXPLOIDS")
        titleLabel.font = NSFont(name: "Courier-Bold", size: 40)
        titleLabel.textColor = .cyan
        titleLabel.frame = NSRect(x: 20, y: 300, width: 480, height: 50)
        titleLabel.alignment = .center
        container.addSubview(titleLabel)
        
        let versionLabel = NSTextField(labelWithString: "Version 0.6.1 - retro vectors")
        versionLabel.font = NSFont(name: "Courier", size: 14)
        versionLabel.textColor = .orange
        versionLabel.frame = NSRect(x: 20, y: 270, width: 480, height: 20)
        versionLabel.alignment = .center
        container.addSubview(versionLabel)
        
        let descText = """
        Exploids is a high-resolution vector space shooter inspired by the Commodore 64 vector aesthetics and running at modern buttery-smooth frame rates.
        
        USED TECHNOLOGY & ARCHITECTURE:
        - Language: Swift 6 (strict concurrency compliance)
        - Windowing & OS integration: macOS native AppKit
        - Graphics engine: SpriteKit (100% asset-free vector outlines)
        - Audio engine: AVFoundation (real-time procedural DSP synthesis)
        
        FEATURES & IMPLEMENTATION DETAILS:
        - Real-time 3D polyhedron vertices rotated and projected on 2D
        - Procedural particles and multi-stage physics camera shakes
        - Dual follow Option drones, protective Shields, screen-clear Bombs
        - Inverse-squared-distance Gravity Singularities (Black Holes)
        - Alphanumeric high scores leaderboard persisted in UserDefaults
        """
        
        let descLabel = NSTextView(frame: NSRect(x: 30, y: 20, width: 460, height: 230))
        descLabel.string = descText
        descLabel.font = NSFont(name: "Courier", size: 12)
        descLabel.textColor = .white
        descLabel.drawsBackground = false
        descLabel.isEditable = false
        descLabel.isSelectable = false
        container.addSubview(descLabel)
        
        visualEffectView.addSubview(container)
        window.contentView = visualEffectView
        
        // Window close helper delegate
        class WindowDelegate: NSObject, NSWindowDelegate {
            weak var appDelegate: AppDelegate?
            init(appDelegate: AppDelegate) {
                self.appDelegate = appDelegate
            }
            func windowWillClose(_ notification: Notification) {
                appDelegate?.aboutWindow = nil
            }
        }
        
        let delegate = WindowDelegate(appDelegate: self)
        window.delegate = delegate
        objc_setAssociatedObject(window, "delegate_holder", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        window.makeKeyAndOrderFront(nil)
        self.aboutWindow = window
    }
}

/// The entry point of the game application.
@main
struct Main {
    static func main() {
        let arguments = CommandLine.arguments
        
        // 1. Check for --version or -v
        if arguments.contains("--version") || arguments.contains("-v") {
            print("Exploids version 0.6.1")
            exit(0)
        }
        
        // 2. Check for --help
        if arguments.contains("--help") || arguments.contains("-h") {
            print("""
            Exploids - Native macOS Retro-HighRes Asteroids
            
            Usage:
            -  exploids [options]
            
            Options:
              --no-sound    Mute all game sounds and disable audio engine startup.
              --test-mode   Run a headless game simulation for 10 frames and print telemetry, then exit.
              --version, -v Show application version.
              --help, -h    Show this help message.
            """)
            exit(0)
        }
        
        // 2. Check for --no-sound
        if arguments.contains("--no-sound") {
            SoundManager.shared.isMuted = true
        }
        
        // 3. Check for --test-mode
        if arguments.contains("--test-mode") {
            let view = SKView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
            let scene = GameScene(size: CGSize(width: 1024, height: 768))
            view.presentScene(scene)
            
            print("Starting headless simulation...")
            scene.simulateKeyDown(keyCode: 13) // W key (Thrust)
            scene.simulateKeyDown(keyCode: 0)  // A key (Rotate CCW)
            
            let frameTime: TimeInterval = 1.0 / 60.0
            var currentTime: TimeInterval = 0.0
            
            scene.update(currentTime)
            
            for frame in 1...10 {
                currentTime += frameTime
                scene.update(currentTime)
                
                let pos = scene.ship.position
                let vel = scene.ship.velocity
                let rot = scene.ship.zRotation
                print("Frame \(frame): Pos=(\(String(format: "%.2f", pos.x)), \(String(format: "%.2f", pos.y))), Vel=(\(String(format: "%.2f", vel.x)), \(String(format: "%.2f", vel.y))), Rot=\(String(format: "%.4f", rot)) rad")
            }
            exit(0)
        }
        
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        
        // Setting activation policy to .regular allows menu focus and dock visibility
        app.setActivationPolicy(.regular)
        
        // Start the Cocoa run loop
        app.run()
    }
}
