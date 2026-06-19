import SpriteKit
import AppKit

/// A subclass of `SKShapeNode` representing a retro vector alien flying saucer (UFO) enemy.
public final class UFO: SKShapeNode {
    
    // MARK: - Properties
    
    /// Whether this is a small (dangerous, sniping) UFO or a large (random shooting) UFO.
    public let isSmall: Bool
    
    /// The UFO's velocity vector.
    public var velocity: CGPoint = .zero
    
    /// Base points awarded when destroyed.
    public var pointValue: Int {
        return isSmall ? 500 : 200
    }
    
    // Wavy sinusoidal movement parameters
    private var wavyTime: TimeInterval = 0.0
    private let wavyAmplitude: CGFloat = 80.0
    private let wavyFrequency: CGFloat = 3.5
    
    // Local outline vertices (unscaled)
    public let baseVertices: [CGPoint] = [
        CGPoint(x: -18, y: -3),
        CGPoint(x: -10, y: 3),
        CGPoint(x: -6, y: 8),
        CGPoint(x: 6, y: 8),
        CGPoint(x: 10, y: 3),
        CGPoint(x: 18, y: -3),
        CGPoint(x: 10, y: -3),
        CGPoint(x: 6, y: -7),
        CGPoint(x: -6, y: -7),
        CGPoint(x: -10, y: -3)
    ]
    
    // Actual vertices scaled for this instance
    public var vertices: [CGPoint] = []
    
    // Firing cooldown parameters
    private var lastFireTime: TimeInterval = 0.0
    public let fireCooldown: TimeInterval
    
    // MARK: - Initializer
    
    /// Initializes a new UFO enemy.
    /// - Parameters:
    ///   - isSmall: True if the UFO is small and aims at the player, false if it is large and shoots randomly.
    ///   - startOnLeft: True if it enters from the left edge of the screen, false if it enters from the right.
    ///   - screenSize: The screen dimensions to determine bounds and spawn heights.
    public init(isSmall: Bool, startOnLeft: Bool, screenSize: CGSize) {
        self.isSmall = isSmall
        self.fireCooldown = isSmall ? 1.5 : 2.2
        super.init()
        
        // Setup scaling and vertices
        let scale: CGFloat = isSmall ? 0.6 : 1.2
        self.vertices = baseVertices.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
        
        // Setup shape path
        let ufoPath = CGMutablePath()
        if let first = vertices.first {
            ufoPath.move(to: first)
            for pt in vertices.dropFirst() {
                ufoPath.addLine(to: pt)
            }
            ufoPath.closeSubpath()
            
            // Draw secondary cockpit dome line
            ufoPath.move(to: CGPoint(x: -10 * scale, y: 3 * scale))
            ufoPath.addLine(to: CGPoint(x: 10 * scale, y: 3 * scale))
        }
        self.path = ufoPath
        
        // Colors: Large is green, Small is hot pink/orange
        if isSmall {
            self.strokeColor = SKColor(red: 1.0, green: 0.3, blue: 0.8, alpha: 1.0)
            self.fillColor = SKColor(red: 1.0, green: 0.3, blue: 0.8, alpha: 0.15)
        } else {
            self.strokeColor = SKColor(red: 0.2, green: 1.0, blue: 0.2, alpha: 1.0)
            self.fillColor = SKColor(red: 0.2, green: 1.0, blue: 0.2, alpha: 0.15)
        }
        self.lineWidth = 1.8
        self.lineJoin = .miter
        
        // Initialize position completely off-screen
        let halfWidth = screenSize.width / 2
        let startX = startOnLeft ? -halfWidth - 50.0 : halfWidth + 50.0
        let startY = CGFloat.random(in: -screenSize.height * 0.25...screenSize.height * 0.25)
        self.position = CGPoint(x: startX, y: startY)
        
        // Initialize velocity (horizontal constant, wavy vertical)
        let speedX = isSmall ? CGFloat(150.0) : CGFloat(90.0)
        self.velocity = CGPoint(
            x: startOnLeft ? speedX : -speedX,
            y: 0.0
        )
    }
    
    public required init?(coder aDecoder: NSCoder) {
        self.isSmall = false
        self.fireCooldown = 2.0
        super.init(coder: aDecoder)
    }
    
    // MARK: - Updates
    
    /// Updates position and wavy trajectory.
    public func update(deltaTime: TimeInterval) {
        let dt = CGFloat(deltaTime)
        
        wavyTime += deltaTime
        // Apply sinusoidal fluctuation to vertical velocity
        velocity.y = wavyAmplitude * sin(CGFloat(wavyTime) * wavyFrequency)
        
        position.x += velocity.x * dt
        position.y += velocity.y * dt
    }
    
    /// Determines if the UFO has completely exited screen bounds.
    public func isExited(screenSize: CGSize) -> Bool {
        let threshold = screenSize.width / 2 + 60.0
        return abs(position.x) > threshold
    }
    
    /// Shoots a warning laser directed towards a target position or randomly.
    public func shoot(target: CGPoint, currentTime: TimeInterval) -> Laser? {
        guard currentTime - lastFireTime >= fireCooldown else { return nil }
        lastFireTime = currentTime
        
        let angle: CGFloat
        if isSmall {
            // Snipes at player ship with minor random error
            let baseAngle = atan2(target.y - position.y, target.x - position.x)
            angle = baseAngle + CGFloat.random(in: -0.12...0.12)
        } else {
            // Large saucer fires in a completely random direction
            angle = CGFloat.random(in: 0..<(2.0 * .pi))
        }
        
        // Spawn laser slightly offset from center
        let spawnPos = CGPoint(
            x: position.x + 15 * cos(angle),
            y: position.y + 15 * sin(angle)
        )
        
        return Laser(position: spawnPos, angle: angle, type: .enemy)
    }
    
    /// Returns world-space coordinates of the UFO vertices.
    public func getWorldVertices() -> [CGPoint] {
        return vertices.map { pt in
            CGPoint(x: position.x + pt.x, y: position.y + pt.y)
        }
    }
}
