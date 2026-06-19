import SpriteKit

/// A subclass of `SKShapeNode` representing the player's retro spaceship.
public final class Ship: SKShapeNode {
    
    // MARK: - Properties
    
    /// The ship's current velocity vector in points per second.
    public var velocity: CGPoint = .zero
    
    /// The maximum velocity speed clamp.
    public var maxVelocity: CGFloat = 350.0
    
    /// The thrust acceleration force in points per second squared.
    public var thrustAcceleration: CGFloat = 450.0
    
    /// The rotation speed in radians per second.
    public var rotationSpeed: CGFloat = 4.0
    
    /// The rate at which velocity decays per second (linear friction).
    /// A value of 0.85 means the velocity decays by 15% every second.
    public var frictionDecayRate: CGFloat = 0.85
    
    /// The local vertices defining the ship's outline shape.
    public let vertices: [CGPoint] = [
        CGPoint(x: 18, y: 0),
        CGPoint(x: -12, y: 10),
        CGPoint(x: -8, y: 0),
        CGPoint(x: -12, y: -10)
    ]
    
    /// The flame node visual effect at the rear of the ship.
    private let flameNode = SKShapeNode()
    
    /// The emitter node for particle-based thruster fire.
    private var thrusterEmitter: SKEmitterNode?
    
    // Shield Visual Elements
    private let shieldNode = SKShapeNode()
    
    /// Activates/deactivates the protective energy shield.
    public var isShieldActive: Bool = false {
        didSet {
            shieldNode.isHidden = !isShieldActive
        }
    }
    
    // Charge Visual Elements
    private let chargeIndicatorNode = SKShapeNode()
    
    /// The current charge status of the Wave Cannon, from 0.0 (empty) to 1.0 (fully charged).
    public var chargeLevel: CGFloat = 0.0 {
        didSet {
            if chargeLevel <= 0.0 {
                chargeIndicatorNode.isHidden = true
            } else {
                chargeIndicatorNode.isHidden = false
                let scale = min(1.5, chargeLevel * 1.5)
                chargeIndicatorNode.xScale = scale
                chargeIndicatorNode.yScale = scale
                
                if chargeLevel >= 1.0 {
                    // Fully charged pulsating indicator
                    chargeIndicatorNode.strokeColor = Bool.random() ? .white : .orange
                    chargeIndicatorNode.fillColor = SKColor(red: 1.0, green: 0.6, blue: 0.1, alpha: 0.5)
                } else {
                    // Charging indicator
                    chargeIndicatorNode.strokeColor = SKColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0)
                    chargeIndicatorNode.fillColor = SKColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.2)
                }
            }
        }
    }
    
    public override var isHidden: Bool {
        didSet {
            if isHidden {
                flameNode.isHidden = true
                thrusterEmitter?.particleBirthRate = 0
                thrusterEmitter?.resetSimulation()
                chargeLevel = 0.0
            }
        }
    }
    
    // MARK: - Initializer
    
    /// Initializes a new retro spaceship.
    public override init() {
        super.init()
        setupShip()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupShip()
    }
    
    // MARK: - Setup Helpers
    
    private func setupShip() {
        // Setup a sharp retro spaceship triangle outline path pointing along +x (right).
        let shipPath = CGMutablePath()
        if let first = vertices.first {
            shipPath.move(to: first)
            for pt in vertices.dropFirst() {
                shipPath.addLine(to: pt)
            }
            shipPath.closeSubpath()
        }
        
        self.path = shipPath
        self.strokeColor = .cyan
        self.fillColor = .clear
        self.lineWidth = 2.0
        self.lineJoin = .miter
        
        // Setup flame node path pointing backwards (left from the rear center indentation)
        let flamePath = CGMutablePath()
        flamePath.move(to: CGPoint(x: -8, y: 0))
        flamePath.addLine(to: CGPoint(x: -16, y: 5))
        flamePath.addLine(to: CGPoint(x: -24, y: 0))
        flamePath.addLine(to: CGPoint(x: -16, y: -5))
        flamePath.closeSubpath()
        
        flameNode.path = flamePath
        flameNode.strokeColor = .orange
        flameNode.fillColor = .clear
        flameNode.lineWidth = 1.5
        flameNode.isHidden = true
        self.addChild(flameNode)
        
        // Setup Shield Node
        let shieldPath = CGPath(ellipseIn: CGRect(x: -28, y: -28, width: 56, height: 56), transform: nil)
        shieldNode.path = shieldPath
        shieldNode.strokeColor = SKColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0)
        shieldNode.fillColor = SKColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.08)
        shieldNode.lineWidth = 1.5
        shieldNode.isHidden = true
        self.addChild(shieldNode)
        
        // Setup Charge Indicator at the ship's nose (18, 0)
        let chargePath = CGPath(ellipseIn: CGRect(x: -6, y: -6, width: 12, height: 12), transform: nil)
        chargeIndicatorNode.path = chargePath
        chargeIndicatorNode.strokeColor = SKColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0)
        chargeIndicatorNode.fillColor = SKColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.2)
        chargeIndicatorNode.lineWidth = 1.2
        chargeIndicatorNode.position = CGPoint(x: 18, y: 0)
        chargeIndicatorNode.isHidden = true
        self.addChild(chargeIndicatorNode)
        
        // Setup emitter node for procedural particle thruster
        let emitter = SKEmitterNode()
        emitter.particleTexture = makeParticleTexture()
        emitter.particleBirthRate = 0 // Started/stopped via isThrusting
        emitter.particleLifetime = 0.25
        emitter.particleLifetimeRange = 0.1
        emitter.particleSpeed = 200.0
        emitter.particleSpeedRange = 50.0
        emitter.emissionAngle = .pi // Pointing backwards from local ship space
        emitter.emissionAngleRange = 0.35 // about 20 degrees spread
        emitter.xAcceleration = 0
        emitter.yAcceleration = 0
        emitter.particleScale = 1.2
        emitter.particleScaleRange = 0.4
        emitter.particleScaleSpeed = -2.0 // Shrunk to 0 quickly
        emitter.particleAlpha = 1.0
        emitter.particleAlphaRange = 0.0
        emitter.particleAlphaSpeed = -1.0 // Fade out
        emitter.particleColorBlendFactor = 1.0
        
        let colorSequence = SKKeyframeSequence(
            keyframeValues: [NSColor.yellow, NSColor.orange, NSColor.red, NSColor.clear],
            times: [0.0, 0.3, 0.7, 1.0] as [NSNumber]
        )
        emitter.particleColorSequence = colorSequence
        
        emitter.position = CGPoint(x: -12, y: 0)
        self.thrusterEmitter = emitter
        self.addChild(emitter)
    }
    
    private func makeParticleTexture() -> SKTexture {
        let size = CGSize(width: 4, height: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil,
                                width: Int(size.width),
                                height: Int(size.height),
                                bitsPerComponent: 8,
                                bytesPerRow: 0,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        
        context.setFillColor(NSColor.white.cgColor)
        context.fillEllipse(in: CGRect(origin: .zero, size: size))
        
        let cgImage = context.makeImage()!
        return SKTexture(cgImage: cgImage)
    }
    
    // MARK: - Update & Physics
    
    /// Updates the spaceship's orientation, velocity, and position.
    public func update(deltaTime: TimeInterval, isThrusting: Bool, rotationInput: CGFloat) {
        let dt = CGFloat(deltaTime)
        
        // 1. Update zRotation based on rotationInput and rotationSpeed
        zRotation += rotationInput * rotationSpeed * dt
        
        // 2. Add thrust acceleration if thrust is active
        if isThrusting {
            let accelX = thrustAcceleration * cos(zRotation)
            let accelY = thrustAcceleration * sin(zRotation)
            velocity.x += accelX * dt
            velocity.y += accelY * dt
            
            // Retro flickering flame effect (randomized size/scaling and color)
            flameNode.isHidden = false
            let randomScaleX = CGFloat.random(in: 0.7...1.3)
            let randomScaleY = CGFloat.random(in: 0.8...1.2)
            flameNode.xScale = randomScaleX
            flameNode.yScale = randomScaleY
            flameNode.strokeColor = Bool.random() ? .orange : .red
            
            // Enable particle emitter emission
            thrusterEmitter?.particleBirthRate = 180
        } else {
            flameNode.isHidden = true
            thrusterEmitter?.particleBirthRate = 0
        }
        
        // Animate Shield Pulsing
        if isShieldActive {
            let pulse = 1.0 + 0.05 * sin(CGFloat(ProcessInfo.processInfo.systemUptime) * 6.0)
            shieldNode.xScale = pulse
            shieldNode.yScale = pulse
        }
        
        // Ensure particle target is the scene so they trail behind naturally
        if let emitter = thrusterEmitter, emitter.targetNode == nil, let scene = self.scene {
            emitter.targetNode = scene
        }
        
        // 3. Apply linear friction
        let frictionFactor = pow(frictionDecayRate, dt)
        velocity.x *= frictionFactor
        velocity.y *= frictionFactor
        
        // 4. Clamp maximum velocity
        let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        if speed > maxVelocity {
            velocity.x = (velocity.x / speed) * maxVelocity
            velocity.y = (velocity.y / speed) * maxVelocity
        }
        
        // 5. Update position based on velocity
        position.x += velocity.x * dt
        position.y += velocity.y * dt
    }
    
    /// Wraps the spaceship around screen boundaries.
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
    
    /// Returns world-space coordinates of the ship's vertices.
    public func getWorldVertices() -> [CGPoint] {
        let cosTheta = cos(zRotation)
        let sinTheta = sin(zRotation)
        // Skalierung berücksichtigen, damit z.B. das Compress-Power-Up (Schiff auf ~30%) auch die
        // Kollisionsfläche schrumpft – nicht nur die Optik.
        return vertices.map { pt in
            let sx = pt.x * xScale
            let sy = pt.y * yScale
            return CGPoint(
                x: position.x + sx * cosTheta - sy * sinTheta,
                y: position.y + sx * sinTheta + sy * cosTheta
            )
        }
    }
    
    // MARK: - Drone Targeting helper
    
    /// Returns target positions for R-Type Options to follow the ship with a spacing offset.
    public func getOptionTargetPosition(index: Int, totalOptions: Int) -> CGPoint {
        let baseAngle = zRotation + .pi // Directly behind the ship
        let spacing: CGFloat = 38.0
        let angleOffset: CGFloat
        if totalOptions <= 1 {
            angleOffset = 0
        } else {
            let step = CGFloat.pi / 4.5
            angleOffset = (CGFloat(index) - CGFloat(totalOptions - 1) / 2.0) * step
        }
        let targetAngle = baseAngle + angleOffset
        return CGPoint(
            x: position.x + spacing * cos(targetAngle),
            y: position.y + spacing * sin(targetAngle)
        )
    }
}
