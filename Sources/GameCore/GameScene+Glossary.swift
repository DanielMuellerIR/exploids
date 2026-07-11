// GameScene+Glossary.swift — Aufbau der Glossar-Ansicht (buildGlossary/addGlossaryItem)
// und die berechneten Scroll-Grenzen der Liste.
// Reiner Datei-Split aus GameScene.swift — kein Verhalten geändert.

import SpriteKit

extension GameScene {
    /// Untere Scroll-Grenze (Startposition): der oberste Eintrag erscheint von unten.
    var glossaryScrollBottom: CGFloat { -600 }
    /// Obere Scroll-Grenze: weit genug, dass der unterste Eintrag oben hinausläuft, bevor umgebrochen wird.
    var glossaryScrollTop: CGFloat { -glossaryContentBottom + 450 }

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
    
    func buildGlossary() {
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
        // codereview-ok: UFO nur statische Glossar-Grafik (Init direkt auf position/velocity=.zero); kein Pfad verschiebt es in eine echte Szene — harmlos (2026-07-01)
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
