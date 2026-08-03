// ResourceBundle.swift
// Findet das mitgelieferte Ressourcen-Bundle von GameCore (Art/, Fonts/, Music/, SFX/)
// ausschliesslich ueber Pfade, die relativ zur laufenden Datei bestimmt werden.
//
// Warum nicht `Bundle.module`: SwiftPM erzeugt dafuer eine Hilfsdatei, in der der
// ABSOLUTE Pfad des Build-Rechners als Ausweichort fest eingebaut ist, zum Beispiel
// `/Users/<name>/git/exploids/.build/arm64-apple-macosx/release/exploids_GameCore.bundle`.
// Diese Zeichenkette landet dadurch in jedem ausgelieferten Binary (am 2026-08-03 im
// signierten Bundle nachgewiesen) und wird auf dem Build-Mac sogar wirklich benutzt —
// dort kann die App also Ressourcen aus dem Quellbaum laden, auf jedem anderen Mac
// nicht. Ausserdem beendet der erzeugte Zugriff den Prozess per `fatalError`, wenn er
// nichts findet.
//
// Der Finder hier laeuft nur ueber `Bundle.main` und das eigene Bundle. Das deckt die
// drei Faelle ab, in denen GameCore laeuft:
//   1. Exploids.app          -> Bundle neben den App-Ressourcen
//   2. nackte SwiftPM-Binary -> Bundle neben der ausfuehrbaren Datei
//   3. `swift test`          -> Bundle NEBEN dem .xctest-Bundle, nicht darin

import Foundation

/// Hilfsklasse, um ueber `Bundle(for:)` an das Bundle zu kommen, in dem GameCore steckt.
private final class GameCoreBundleToken {}

enum GameCoreResources {

    /// Das Ressourcen-Bundle von GameCore. Wird es nicht gefunden, liefert die
    /// Eigenschaft das eigene Bundle zurueck: Alle Aufrufer pruefen das Ergebnis von
    /// `url(forResource:)` ohnehin auf `nil` und weichen dann auf einen Platzhalter aus.
    /// Ein Abbruch waere hier die schlechtere Wahl — eine fehlende Textur soll das Spiel
    /// nicht beenden.
    static let bundle: Bundle = {
        let name = "exploids_GameCore.bundle"
        let selfBundle = Bundle(for: GameCoreBundleToken.self)

        var candidates: [URL] = []
        if let url = Bundle.main.resourceURL { candidates.append(url) }
        candidates.append(Bundle.main.bundleURL)
        if let url = selfBundle.resourceURL { candidates.append(url) }
        candidates.append(selfBundle.bundleURL)
        // Test-Runner: das Ressourcen-Bundle liegt neben dem .xctest-Bundle im
        // Build-Ordner, also eine Ebene ueber dessen eigenem Pfad.
        candidates.append(selfBundle.bundleURL.deletingLastPathComponent())
        if let exe = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent() {
            candidates.append(exe)
        }

        for base in candidates {
            if let found = Bundle(url: base.appendingPathComponent(name)) { return found }
        }
        return selfBundle
    }()
}
