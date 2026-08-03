# Aktiver Backlog

1. `isInvincible`-Cross-Type-Doppelschaden mit zwei Treffern im selben Frame
   reproduzieren; nur bei Beleg pro Kollisionsblock frisch auswerten.
2. `stepSimulation`/Kollision nur als separaten Hochrisiko-Refactor aufteilen; nach
   jedem Schnitt Golden Replay bitgenau verifizieren.
3. iOS-Port: Touch-/GameController-Gefühl auf Gerät, App-Icon/Launch-Screen/
   Asset-Catalog und Lifecycle polieren.
4. Vor App-Store- oder kommerzieller Distribution die zwei Free-Plan-Musiktracks
   durch rechtlich saubere eigene/CC0/lizenzierte Musik ersetzen.
5. Balance und möglichen Fixed-Timestep-Mikroruckler erst reproduzierbar messen.
6. Kuratiertes Promo-GIF aus einem guten Replay auswählen/rendern.
7. Scroll-Modus später als eigenständigen dritten Modus planen.
8. Der von SwiftPM erzeugte `Bundle.module`-Zugriff trägt den absoluten
   `.build`-Pfad des Build-Rechners als Zeichenkette ins Binary. Prüfen, ob ein
   Build-Schalter (Richtung `-Xswiftc -file-prefix-map`) ihn entfernt, ohne das
   Ressourcen-Bundle zu brechen; danach die Pfad-Prüfung in
   `Tests/cli-version.sh` auf den ganzen Repo-Pfad ausweiten.
9. `--version` der nackten SwiftPM-Binary meldet außerhalb eines Checkouts
   ehrlich `unknown`. Wer das ändern will, muss die Version beim Bauen einbetten
   (erzeugte Konstante oder SwiftPM-Plugin); das App-Bundle ist über die
   Info.plist bereits abgedeckt. Nur angehen, wenn die nackte Binary wirklich
   verteilt werden soll.

Veraltete Versions-/Push-Todos und bereits veröffentlichte Replay-/Demo-Arbeit nicht
als offen übernehmen; vor jedem Release den aktuellen Git-/Versionsstand neu prüfen.
