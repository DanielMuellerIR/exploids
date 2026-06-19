import SpriteKit

/// Predefined projectile types for exploids.
public enum LaserType: Sendable {
    case normal
    case charge1
    case chargeMax
    case enemy
}

/// A subclass of `SKShapeNode` representing a high-velocity laser projectile.
public final class Laser: SKShapeNode {
    
    // MARK: - Properties
    
    /// The laser's velocity vector in points per second.
    public var velocity: CGPoint = .zero
    
    /// The total duration the laser can exist before expiring.
    public let lifetime: TimeInterval
    
    /// The classification of this laser.
    public let type: LaserType
    
    /// The maximum number of asteroids this laser can pierce before being destroyed.
    public var pierceLimit: Int = 1
    
    /// The number of asteroids this laser has already pierced.
    public var pierceCount: Int = 0
    
    /// The elapsed time since the laser was fired.
    private var elapsedTime: TimeInterval = 0.0
    
    // MARK: - Initializers
    
    /// Initializes a new laser projectile.
    public init(position: CGPoint, angle: CGFloat, type: LaserType = .normal, speed: CGFloat = 600.0, lifetime: TimeInterval = 1.2) {
        self.type = type
        self.lifetime = lifetime
        super.init()
        
        self.position = position
        self.zRotation = angle
        
        // Define physics properties based on type
        switch type {
        case .normal, .enemy:
            self.pierceLimit = 1
        case .charge1:
            self.pierceLimit = 2
        case .chargeMax:
            self.pierceLimit = 9999
        }
        
        let actualSpeed: CGFloat
        switch type {
        case .normal:
            actualSpeed = speed
        case .charge1:
            actualSpeed = speed * 1.15
        case .chargeMax:
            actualSpeed = speed * 1.3
        case .enemy:
            actualSpeed = speed * 0.65
        }
        
        self.velocity = CGPoint(
            x: actualSpeed * cos(angle),
            y: actualSpeed * sin(angle)
        )
        
        setupLaser()
    }
    
    /// Convenience initializer for backwards compatibility with Stage 3 tests.
    public convenience init(position: CGPoint, angle: CGFloat, speed: CGFloat, lifetime: TimeInterval) {
        self.init(position: position, angle: angle, type: .normal, speed: speed, lifetime: lifetime)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        self.type = .normal
        self.lifetime = 1.2
        super.init(coder: aDecoder)
        setupLaser()
    }
    
    // MARK: - Setup Helpers
    
    private func setupLaser() {
        let linePath = CGMutablePath()
        
        switch type {
        case .normal:
            // High-res yellow/amber line segment
            linePath.move(to: CGPoint(x: -6, y: 0))
            linePath.addLine(to: CGPoint(x: 6, y: 0))
            self.path = linePath
            self.strokeColor = SKColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1.0)
            self.lineWidth = 2.0
            
        case .charge1:
            // Glowing cyan wide line segment
            linePath.move(to: CGPoint(x: -12, y: 0))
            linePath.addLine(to: CGPoint(x: 12, y: 0))
            self.path = linePath
            self.strokeColor = SKColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0)
            self.lineWidth = 4.0
            
        case .chargeMax:
            // Heavy bright orange/red double-thick segment
            linePath.move(to: CGPoint(x: -20, y: 0))
            linePath.addLine(to: CGPoint(x: 20, y: 0))
            self.path = linePath
            self.strokeColor = SKColor(red: 1.0, green: 0.35, blue: 0.0, alpha: 1.0)
            self.lineWidth = 8.0
            
        case .enemy:
            // Red warning line segment
            linePath.move(to: CGPoint(x: -5, y: 0))
            linePath.addLine(to: CGPoint(x: 5, y: 0))
            self.path = linePath
            self.strokeColor = SKColor(red: 1.0, green: 0.15, blue: 0.15, alpha: 1.0)
            self.lineWidth = 2.0
        }
        
        self.fillColor = .clear
        self.lineCap = .round
    }
    
    // MARK: - Update
    
    /// Updates the laser's position and lifetime.
    public func update(deltaTime: TimeInterval) -> Bool {
        let dt = CGFloat(deltaTime)
        
        position.x += velocity.x * dt
        position.y += velocity.y * dt
        
        elapsedTime += deltaTime
        return elapsedTime >= lifetime
    }
    
    /// Returns the world-space start and end points of the laser segment.
    public func getWorldSegment() -> (CGPoint, CGPoint) {
        let cosTheta = cos(zRotation)
        let sinTheta = sin(zRotation)
        
        let halfLength: CGFloat
        switch type {
        case .normal: halfLength = 6.0
        case .charge1: halfLength = 12.0
        case .chargeMax: halfLength = 20.0
        case .enemy: halfLength = 5.0
        }
        
        let start = CGPoint(
            x: position.x - halfLength * cosTheta,
            y: position.y - halfLength * sinTheta
        )
        let end = CGPoint(
            x: position.x + halfLength * cosTheta,
            y: position.y + halfLength * sinTheta
        )
        return (start, end)
    }
    
    /// Wraps the laser around screen boundaries.
    public func wrapAround(screenSize: CGSize) {
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
