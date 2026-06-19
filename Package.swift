// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "exploids",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "exploids", targets: ["GameCore"])
    ],
    targets: [
        .executableTarget(
            name: "GameCore",
            path: "Sources/GameCore",
            resources: [
                // Hintergrundmusik (mp3) – über Bundle.module zur Laufzeit geladen.
                .copy("Music"),
                // Retro-Pixel-Font (Press Start 2P, OFL) – beim Start registriert.
                .copy("Fonts")
            ]
        ),
        .testTarget(
            name: "GameCoreTests",
            dependencies: ["GameCore"],
            path: "Tests/GameCoreTests"
        )
    ]
)
