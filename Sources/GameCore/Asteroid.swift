import SpriteKit
import AppKit

/// A structure representing a 3D vector for asteroid vertices.
public struct Vector3D: Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public var z: CGFloat
    
    public init(x: CGFloat, y: CGFloat, z: CGFloat) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// A subclass of `SKShapeNode` representing a procedurally generated retro asteroid with 3D wireframe rendering.
public final class Asteroid: SKShapeNode {
    
    /// Predefined size categories for asteroids.
    public enum AsteroidSize: CGFloat, CaseIterable, Sendable {
        case large = 40.0
        case medium = 20.0
        case small = 10.0
    }
    
    // MARK: - Properties
    
    /// The asteroid's current velocity vector in points per second.
    public var velocity: CGPoint = .zero
    
    /// The slow rotation speed in radians per second.
    public var angularVelocity: CGFloat = 0.0
    
    /// The size classification of this asteroid.
    public var sizeClass: AsteroidSize
    
    /// Whether this is an imploding type asteroid that collapses into a black hole when shot or grown.
    public let isImplodingType: Bool
    
    /// Whether this is a wobbling type asteroid that expands and detonates.
    public let isWobblingType: Bool
    
    /// The elapsed time in the current wobbling growth phase.
    public var timeInCurrentPhase: TimeInterval = 0.0
    
    /// The current phase index of the wobbling asteroid (0 = small, 1 = medium, 2 = large).
    public var wobblePhase: Int = 0
    
    /// The number of times this imploding asteroid has been shot by a player laser.
    public var hitCount: Int = 0

    /// Whether the asteroid has already been fully inside the visible screen at least once.
    /// Frisch gespawnte Asteroiden fliegen von außerhalb des Bildschirms herein. Solange das
    /// noch nicht passiert ist, darf `wrapAround()` sie NICHT an die gegenüberliegende Kante
    /// umklappen — sonst würden sie mitten im Bild erscheinen statt von der Kante einzufliegen.
    public var hasEnteredScreen: Bool = false
    
    /// The local vertices defining the 2D silhouette outline (used for background fill and collision).
    public private(set) var vertices: [CGPoint] = []
    
    // 3D Wireframe Properties
    private var local3DVertices: [Vector3D] = []
    private var edges: [(Int, Int)] = []
    private let wireframeNode = SKShapeNode()
    
    // 3D rotation angles
    public var pitch: CGFloat = 0.0
    public var yaw: CGFloat = 0.0
    
    // 3D rotation velocities (radians per second)
    public var pitchVelocity: CGFloat = 0.0
    public var yawVelocity: CGFloat = 0.0
    
    // MARK: - Initializer
    
    /// Initializes a new procedurally generated asteroid of a given size class.
    public init(sizeClass: AsteroidSize = .large, isImplodingType: Bool = false, isWobblingType: Bool = false) {
        self.isImplodingType = isImplodingType
        self.isWobblingType = isWobblingType
        // Wobbling type always starts small
        self.sizeClass = isWobblingType ? .small : sizeClass
        super.init()
        setupAsteroid()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        self.sizeClass = .large
        self.isImplodingType = false
        self.isWobblingType = false
        super.init(coder: aDecoder)
        setupAsteroid()
    }
    
    // MARK: - Setup Helpers
    
    public func growToNextSize(newSize: AsteroidSize) {
        guard isWobblingType else { return }
        self.sizeClass = newSize
        setupAsteroid()
        self.xScale = 1.0
        self.yScale = 1.0
    }
    
    private func setupAsteroid() {
        let radius = sizeClass.rawValue
        
        // Reset 3D wireframe configuration arrays to allow clean re-generation when growing
        local3DVertices.removeAll()
        edges.removeAll()
        
        // 1. Setup 2D Silhouette (for backdrop and collision)
        let numVertices = Int.random(in: 8...12)
        var generatedPoints: [CGPoint] = []
        for i in 0..<numVertices {
            let angle = (CGFloat(i) / CGFloat(numVertices)) * 2.0 * .pi
            let perturbedRadius = radius * CGFloat.random(in: 0.75...1.25)
            let x = perturbedRadius * cos(angle)
            let y = perturbedRadius * sin(angle)
            generatedPoints.append(CGPoint(x: x, y: y))
        }
        self.vertices = generatedPoints
        
        let astPath = CGMutablePath()
        if let first = generatedPoints.first {
            astPath.move(to: first)
            for pt in generatedPoints.dropFirst() {
                astPath.addLine(to: pt)
            }
            astPath.closeSubpath()
            
            // Add concentric inner core line for imploding vector styling
            if isImplodingType {
                astPath.addEllipse(in: CGRect(x: -radius * 0.45, y: -radius * 0.45, width: radius * 0.9, height: radius * 0.9), transform: .identity)
            }
        }
        self.path = astPath
        
        // C-64 inspired styling: Translucent fill, outline color
        // Imploding ones have a distinct warm orange/magenta warning color
        // Wobbling ones have a bright neon red outline
        let strokeColor: SKColor
        if isImplodingType {
            strokeColor = SKColor(red: 1.0, green: 0.3, blue: 0.8, alpha: 1.0)
        } else if isWobblingType {
            strokeColor = SKColor(red: 1.0, green: 0.1, blue: 0.1, alpha: 1.0)
        } else {
            strokeColor = .white
        }
        
        self.strokeColor = strokeColor
        self.fillColor = NSColor(white: 0.15, alpha: 0.8)
        self.lineWidth = 2.0
        self.lineJoin = .miter
        
        // 2. Setup 3D Wireframe (perturbed icosahedron)
        let phi = (1.0 + sqrt(5.0)) / 2.0
        let len = sqrt(1.0 + phi * phi)
        let h = 1.0 / len
        let w = phi / len
        
        let unitVertices = [
            Vector3D(x: 0, y: h, z: w),
            Vector3D(x: 0, y: h, z: -w),
            Vector3D(x: 0, y: -h, z: w),
            Vector3D(x: 0, y: -h, z: -w),
            Vector3D(x: h, y: w, z: 0),
            Vector3D(x: h, y: -w, z: 0),
            Vector3D(x: -h, y: w, z: 0),
            Vector3D(x: -h, y: -w, z: 0),
            Vector3D(x: w, y: 0, z: h),
            Vector3D(x: w, y: 0, z: -h),
            Vector3D(x: -w, y: 0, z: h),
            Vector3D(x: -w, y: 0, z: -h)
        ]
        
        // Perturb 3D vertices
        self.local3DVertices = unitVertices.map { v in
            let perturbedRadius = radius * CGFloat.random(in: 0.75...1.25)
            return Vector3D(
                x: v.x * perturbedRadius,
                y: v.y * perturbedRadius,
                z: v.z * perturbedRadius
            )
        }
        
        // Generate edges dynamically (2 * h)
        let expectedDist = 2.0 * h
        for i in 0..<12 {
            for j in (i + 1)..<12 {
                let dx = unitVertices[i].x - unitVertices[j].x
                let dy = unitVertices[i].y - unitVertices[j].y
                let dz = unitVertices[i].z - unitVertices[j].z
                let dist = sqrt(dx*dx + dy*dy + dz*dz)
                if abs(dist - expectedDist) < 0.01 {
                    self.edges.append((i, j))
                }
            }
        }
        
        // Configure wireframe child node
        wireframeNode.strokeColor = strokeColor
        wireframeNode.fillColor = .clear
        wireframeNode.lineWidth = 1.5
        wireframeNode.lineJoin = .round
        if wireframeNode.parent == nil {
            self.addChild(wireframeNode)
        }
        
        // 3. Setup Velocities
        let randomSpeed = CGFloat.random(in: 40.0...100.0)
        let randomAngle = CGFloat.random(in: 0..<(2.0 * .pi))
        self.velocity = CGPoint(
            x: randomSpeed * cos(randomAngle),
            y: randomSpeed * sin(randomAngle)
        )
        
        // Spin velocities
        self.angularVelocity = CGFloat.random(in: -1.2...1.2)
        self.pitchVelocity = CGFloat.random(in: -1.0...1.0)
        self.yawVelocity = CGFloat.random(in: -1.0...1.0)
        
        // Draw the initial frame
        updateWireframePath()
    }
    
    private func updateWireframePath() {
        let cosP = cos(pitch)
        let sinP = sin(pitch)
        let cosY = cos(yaw)
        let sinY = sin(yaw)
        
        // Project 3D vertices to 2D
        let projected = local3DVertices.map { v in
            let x1 = v.x
            let y1 = v.y * cosP - v.z * sinP
            let z1 = v.y * sinP + v.z * cosP
            
            let x2 = x1 * cosY + z1 * sinY
            let y2 = y1
            
            return CGPoint(x: x2, y: y2)
        }
        
        let path = CGMutablePath()
        
        // Draw outer 3D wireframe edges
        for (i, j) in edges {
            if i < projected.count, j < projected.count {
                path.move(to: projected[i])
                path.addLine(to: projected[j])
            }
        }
        
        // Draw secondary concentric inner 3D wireframe core for imploding types
        if isImplodingType {
            let innerProjected = projected.map { CGPoint(x: $0.x * 0.45, y: $0.y * 0.45) }
            for (i, j) in edges {
                if i < innerProjected.count, j < innerProjected.count {
                    path.move(to: innerProjected[i])
                    path.addLine(to: innerProjected[j])
                }
            }
        }
        
        wireframeNode.path = path
    }
    
    // MARK: - Updates
    
    /// Updates position and 3D rotation.
    public func update(deltaTime: TimeInterval) {
        let dt = CGFloat(deltaTime)
        
        position.x += velocity.x * dt
        position.y += velocity.y * dt
        zRotation += angularVelocity * dt
        
        pitch += pitchVelocity * dt
        yaw += yawVelocity * dt
        
        pitch = pitch.truncatingRemainder(dividingBy: 2.0 * .pi)
        yaw = yaw.truncatingRemainder(dividingBy: 2.0 * .pi)
        
        if isWobblingType {
            timeInCurrentPhase += deltaTime
            // wobble scale oscillates between 0.85 and 1.15 scale
            let wobbleScale = 1.0 + 0.15 * sin(CGFloat(ProcessInfo.processInfo.systemUptime * 18.0))
            self.xScale = wobbleScale
            self.yScale = wobbleScale
        }
        
        updateWireframePath()
    }
    
    /// Wraps the asteroid around screen boundaries.
    public func wrapAround(screenSize: CGSize) {
        let halfWidth = screenSize.width / 2
        let halfHeight = screenSize.height / 2

        // Solange der Asteroid noch von außen hereinfliegt (Mittelpunkt außerhalb des
        // sichtbaren Rechtecks), NICHT umklappen. Erst wenn sein Mittelpunkt einmal im Bild
        // war, gilt er als "eingetreten" und nimmt danach normal am Kanten-Umlauf teil.
        if !hasEnteredScreen {
            let centerInside = position.x >= -halfWidth && position.x <= halfWidth
                && position.y >= -halfHeight && position.y <= halfHeight
            if centerInside {
                hasEnteredScreen = true
            }
            return
        }

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
    
    /// Returns world-space coordinates of the 2D silhouette vertices (correctly transformed by scale).
    public func getWorldVertices() -> [CGPoint] {
        let cosTheta = cos(zRotation)
        let sinTheta = sin(zRotation)
        let scaleX = xScale
        let scaleY = yScale
        return vertices.map { pt in
            CGPoint(
                x: position.x + (pt.x * scaleX) * cosTheta - (pt.y * scaleY) * sinTheta,
                y: position.y + (pt.x * scaleX) * sinTheta + (pt.y * scaleY) * cosTheta
            )
        }
    }
}
