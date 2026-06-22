// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "exploids",
    platforms: [
        // GameCore ist plattformunabhängig (SpriteKit/AVFoundation) und gegen das iOS-SDK
        // verifiziert kompilierbar. Die App-Shell ExploidsMac ist weiterhin macOS-only; ein
        // iOS-App-Target (Xcode) wird die GameCore-Library als Abhängigkeit einbinden.
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        // Produktname bleibt "exploids", damit build-app.sh die Binary unverändert findet.
        .executable(name: "exploids", targets: ["ExploidsMac"]),
        // GameCore zusätzlich als Library-Produkt: So kann das iOS-App-Target (Xcode)
        // dieses Package als lokale Abhängigkeit einbinden und GameCore linken.
        .library(name: "GameCore", targets: ["GameCore"])
    ],
    targets: [
        // Plattformunabhängige Spiel-Engine als Library – kann später auch von einem
        // iOS-App-Target (Xcode) als Package-Abhängigkeit eingebunden werden.
        .target(
            name: "GameCore",
            path: "Sources/GameCore",
            resources: [
                // Hintergrundmusik (mp3) – über Bundle.module zur Laufzeit geladen.
                .copy("Music"),
                // Generierte Retro-Soundeffekte (AAC/.m4a) – optionaler Sample-Modus im SoundManager.
                .copy("SFX"),
                // Retro-Pixel-Font (Press Start 2P, OFL) – beim Start registriert.
                .copy("Fonts")
            ]
        ),
        // macOS-App-Shell (AppKit): Entry-Point, Fenster, Menü, Dock-Icon.
        .executableTarget(
            name: "ExploidsMac",
            dependencies: ["GameCore"],
            path: "Sources/ExploidsMac"
        ),
        .testTarget(
            name: "GameCoreTests",
            dependencies: ["GameCore"],
            path: "Tests/GameCoreTests"
        )
    ]
)
