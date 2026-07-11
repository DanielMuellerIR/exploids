import Foundation

/// Replay-Archiv auf der Platte: schreibt die Aufnahme eines Laufs als Datei ins
/// Zielverzeichnis und hält die Anzahl begrenzt (die ältesten Dateien fliegen raus).
///
/// Aus `GameScene` extrahiert; reines Datei-I/O ohne Einfluss auf die Simulation.
/// Best-effort: Fehler werden geloggt, nie geworfen — ein fehlgeschlagenes Archiv
/// darf das Spielende nicht stören.
public struct ReplayArchive {

    /// Zielverzeichnis für die `.replay`-Dateien.
    public let directory: URL

    /// Höchstens so viele `.replay`-Dateien bleiben liegen (ältere werden gelöscht).
    public let limit: Int

    public init(directory: URL, limit: Int) {
        self.directory = directory
        self.limit = limit
    }

    /// Schreibt die Aufnahme als Datei und räumt danach das Archiv auf.
    /// Zeitstempel-Präfix (Date() NUR hier für den Dateinamen — nicht im Gameplay-Pfad)
    /// + Score + Level machen die Datei sortierbar und auswählbar („letztes/bestes Spiel").
    public func archive(_ replay: Replay, score: Int, level: Int) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let stamp = Self.timestampFormatter.string(from: Date())
            let url = directory.appendingPathComponent("\(stamp)_score-\(score)_lvl-\(level).replay")
            try replay.encoded().write(to: url)
            prune()
        } catch {
            print("Replay-Archiv: Schreiben fehlgeschlagen: \(error)")
        }
    }

    /// Löscht die ältesten `.replay`-Dateien, bis höchstens `limit` übrig sind
    /// (nach Name = Zeit sortiert).
    private func prune() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "replay" }), files.count > limit else { return }
        let oldestFirst = files.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in oldestFirst.prefix(files.count - limit) {
            try? fm.removeItem(at: url)
        }
    }

    /// Stabiler, sortierbarer Zeitstempel für Archiv-Dateinamen (lokale Zeit, POSIX-Locale).
    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f
    }()
}
